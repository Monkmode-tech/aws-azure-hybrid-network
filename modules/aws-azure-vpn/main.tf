###############################################################################
# Cross-cloud site-to-site VPN with BGP
#
#   AWS virtual private gateway (ASN 64512)
#      tunnel 1  169.254.21.0/30   AWS .1  <->  Azure .2
#      tunnel 2  169.254.22.0/30   AWS .1  <->  Azure .2
#   Azure VPN gateway (ASN 65000, custom APIPA addresses)
#
# Both tunnels are up and BGP-peered at the same time; if one AWS tunnel
# endpoint goes down (e.g. AWS maintenance), BGP withdraws its routes and
# traffic continues over the other one.
#
# The crypto policy is pinned identically on both sides (IKEv2, AES-256,
# SHA-256, DH group 14, PFS group 14) instead of relying on defaults, so the
# tunnels negotiate deterministically.
###############################################################################

locals {
  tunnels = {
    tunnel1 = {
      inside_cidr = var.tunnel_inside_cidrs[0]
      azure_apipa = cidrhost(var.tunnel_inside_cidrs[0], 2)
    }
    tunnel2 = {
      inside_cidr = var.tunnel_inside_cidrs[1]
      azure_apipa = cidrhost(var.tunnel_inside_cidrs[1], 2)
    }
  }

  # Per-tunnel attributes AWS returns after the VPN connection is created.
  aws_tunnel = {
    tunnel1 = {
      outside_ip = aws_vpn_connection.this.tunnel1_address
      bgp_peer   = aws_vpn_connection.this.tunnel1_vgw_inside_address
      psk        = aws_vpn_connection.this.tunnel1_preshared_key
    }
    tunnel2 = {
      outside_ip = aws_vpn_connection.this.tunnel2_address
      bgp_peer   = aws_vpn_connection.this.tunnel2_vgw_inside_address
      psk        = aws_vpn_connection.this.tunnel2_preshared_key
    }
  }
}

#------------------------------------------------------------------------------
# Pre-shared keys (AWS rule: 8-64 chars, alphanumeric, must not start with 0)
#------------------------------------------------------------------------------
resource "random_password" "psk" {
  for_each = local.tunnels

  length  = 40
  special = false
}

#------------------------------------------------------------------------------
# AWS side
#------------------------------------------------------------------------------
resource "aws_customer_gateway" "azure" {
  bgp_asn    = var.azure_bgp_asn
  ip_address = var.azure_gateway_public_ip
  type       = "ipsec.1"

  tags = { Name = "${var.name}-azure-cgw" }
}

resource "aws_vpn_connection" "this" {
  vpn_gateway_id      = var.aws_vpn_gateway_id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_inside_cidr   = local.tunnels.tunnel1.inside_cidr
  tunnel1_preshared_key = "k${random_password.psk["tunnel1"].result}"
  tunnel2_inside_cidr   = local.tunnels.tunnel2.inside_cidr
  tunnel2_preshared_key = "k${random_password.psk["tunnel2"].result}"

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]
  tunnel1_startup_action               = "start"

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]
  tunnel2_startup_action               = "start"

  tags = { Name = "${var.name}-to-azure" }
}

#------------------------------------------------------------------------------
# Azure side: one local network gateway + connection per AWS tunnel
#------------------------------------------------------------------------------
resource "azurerm_local_network_gateway" "aws" {
  for_each = local.tunnels

  name                = "lgw-aws-${each.key}"
  location            = var.azure_location
  resource_group_name = var.azure_resource_group_name
  gateway_address     = local.aws_tunnel[each.key].outside_ip
  tags                = var.azure_tags

  bgp_settings {
    asn                 = var.aws_bgp_asn
    bgp_peering_address = local.aws_tunnel[each.key].bgp_peer
  }
}

resource "azurerm_virtual_network_gateway_connection" "aws" {
  for_each = local.tunnels

  name                       = "cn-aws-${each.key}"
  location                   = var.azure_location
  resource_group_name        = var.azure_resource_group_name
  type                       = "IPsec"
  virtual_network_gateway_id = var.azure_gateway_id
  local_network_gateway_id   = azurerm_local_network_gateway.aws[each.key].id
  shared_key                 = local.aws_tunnel[each.key].psk
  connection_protocol        = "IKEv2"
  bgp_enabled                = true
  tags                       = var.azure_tags

  custom_bgp_addresses {
    primary = each.value.azure_apipa
  }

  ipsec_policy {
    dh_group         = "DHGroup14"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS2048"
    sa_lifetime      = 3600
  }
}

#------------------------------------------------------------------------------
# Tunnel health alarm
#------------------------------------------------------------------------------
resource "aws_sns_topic" "vpn_alerts" {
  # checkov:skip=CKV_AWS_26: CloudWatch alarms cannot publish to topics encrypted with the AWS-managed aws/sns key, and a CMK for a non-sensitive tunnel-state alert is not worth its cost here
  name = "${var.name}-vpn-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.vpn_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "tunnel_down" {
  alarm_name          = "${var.name}-vpn-tunnel-down"
  alarm_description   = "At least one AWS-Azure tunnel is down (redundancy lost). Both down = Azure unreachable."
  namespace           = "AWS/VPN"
  metric_name         = "TunnelState"
  dimensions          = { VpnId = aws_vpn_connection.this.id }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.vpn_alerts.arn]
  ok_actions          = [aws_sns_topic.vpn_alerts.arn]
}
