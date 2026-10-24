###############################################################################
# AWS <-> Azure hybrid network lab
#
#   AWS VPC 172.16.32.0/21 (us-east-2)  ==IPsec + BGP==  Azure VNet 172.16.40.0/21 (East US)
#
# Address plan: docs/ip-plan.md (from the CLCS 635 multi-site subnet design).
# Dependency order handled by Terraform:
#   Azure public IP -> AWS customer gateway -> AWS VPN connection (tunnel IPs,
#   keys) -> Azure local network gateways -> Azure connections
###############################################################################

locals {
  aws_vpc_cidr    = cidrsubnet(var.company_supernet, 2, 0) # 172.16.32.0/21
  azure_vnet_cidr = cidrsubnet(var.company_supernet, 2, 1) # 172.16.40.0/21

  tunnel_inside_cidrs = ["169.254.21.0/30", "169.254.22.0/30"]
  azure_apipa         = [for c in local.tunnel_inside_cidrs : cidrhost(c, 2)]

  azure_tags = {
    project    = "aws-azure-hybrid-network"
    managed-by = "terraform"
    owner      = var.owner
  }
}

module "aws_network" {
  source = "../../modules/aws-network"

  name            = var.name
  aws_region      = var.aws_region
  vpc_cidr        = local.aws_vpc_cidr
  amazon_side_asn = var.aws_bgp_asn
}

module "azure_network" {
  source = "../../modules/azure-network"

  name            = var.name
  location        = var.azure_location
  vnet_cidr       = local.azure_vnet_cidr
  aws_vpc_cidr    = local.aws_vpc_cidr
  gateway_sku     = var.azure_gateway_sku
  azure_bgp_asn   = var.azure_bgp_asn
  apipa_addresses = local.azure_apipa
  tags            = local.azure_tags
}

module "vpn" {
  source = "../../modules/aws-azure-vpn"

  name                      = var.name
  aws_vpn_gateway_id        = module.aws_network.vpn_gateway_id
  aws_bgp_asn               = var.aws_bgp_asn
  azure_bgp_asn             = var.azure_bgp_asn
  azure_gateway_public_ip   = module.azure_network.gateway_public_ip
  azure_gateway_id          = module.azure_network.gateway_id
  azure_resource_group_name = module.azure_network.resource_group_name
  azure_location            = module.azure_network.location
  tunnel_inside_cidrs       = local.tunnel_inside_cidrs
  alert_email               = var.alert_email
  azure_tags                = local.azure_tags
}

module "aws_test_vm" {
  source = "../../modules/aws-test-vm"

  name            = var.name
  vpc_id          = module.aws_network.vpc_id
  vpc_cidr        = local.aws_vpc_cidr
  subnet_id       = module.aws_network.private_subnet_ids[0]
  azure_vnet_cidr = local.azure_vnet_cidr
}

module "azure_test_vm" {
  source = "../../modules/azure-test-vm"

  name                = var.name
  location            = module.azure_network.location
  resource_group_name = module.azure_network.resource_group_name
  subnet_id           = module.azure_network.workload_subnet_id
  ssh_public_key      = var.ssh_public_key
  vm_size             = var.azure_vm_size
  tags                = local.azure_tags
}
