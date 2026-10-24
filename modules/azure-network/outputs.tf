output "resource_group_name" {
  description = "Resource group holding all Azure resources."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region."
  value       = azurerm_resource_group.this.location
}

output "workload_subnet_id" {
  description = "Workload subnet ID."
  value       = azurerm_subnet.workload.id
}

output "gateway_id" {
  description = "VPN gateway ID."
  value       = azurerm_virtual_network_gateway.this.id
}

output "gateway_name" {
  description = "VPN gateway name."
  value       = azurerm_virtual_network_gateway.this.name
}

output "gateway_public_ip" {
  description = "Public IP of the Azure VPN gateway (the AWS customer gateway address)."
  value       = azurerm_public_ip.gateway.ip_address
}
