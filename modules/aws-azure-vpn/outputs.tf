output "vpn_connection_id" {
  description = "AWS Site-to-Site VPN connection ID."
  value       = aws_vpn_connection.this.id
}

output "tunnel_outside_ips" {
  description = "Public endpoints of the two AWS tunnels."
  value       = [aws_vpn_connection.this.tunnel1_address, aws_vpn_connection.this.tunnel2_address]
}

output "azure_connection_names" {
  description = "Azure connection resource names."
  value       = [for c in azurerm_virtual_network_gateway_connection.aws : c.name]
}

output "azure_apipa_addresses" {
  description = "Azure-side BGP addresses (one per tunnel)."
  value       = [for t in local.tunnels : t.azure_apipa]
}
