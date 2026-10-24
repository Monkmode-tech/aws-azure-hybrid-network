output "aws_region" {
  description = "AWS region (used by scripts/)."
  value       = var.aws_region
}

output "aws_vpc_cidr" {
  description = "AWS VPC CIDR."
  value       = local.aws_vpc_cidr
}

output "azure_vnet_cidr" {
  description = "Azure VNet CIDR."
  value       = local.azure_vnet_cidr
}

output "aws_vpc_id" {
  description = "AWS VPC ID."
  value       = module.aws_network.vpc_id
}

output "aws_private_route_table_id" {
  description = "AWS route table that should contain the BGP-learned Azure route."
  value       = module.aws_network.private_route_table_id
}

output "vpn_connection_id" {
  description = "AWS VPN connection ID."
  value       = module.vpn.vpn_connection_id
}

output "azure_resource_group" {
  description = "Azure resource group."
  value       = module.azure_network.resource_group_name
}

output "azure_gateway_name" {
  description = "Azure VPN gateway name."
  value       = module.azure_network.gateway_name
}

output "azure_connection_names" {
  description = "Azure connection names."
  value       = module.vpn.azure_connection_names
}

output "aws_vm_instance_id" {
  description = "AWS test VM (connect: aws ssm start-session --target <id>)."
  value       = module.aws_test_vm.instance_id
}

output "aws_vm_private_ip" {
  description = "AWS test VM private IP."
  value       = module.aws_test_vm.private_ip
}

output "azure_vm_name" {
  description = "Azure test VM name."
  value       = module.azure_test_vm.vm_name
}

output "azure_vm_private_ip" {
  description = "Azure test VM private IP."
  value       = module.azure_test_vm.private_ip
}
