output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = [for s in aws_subnet.private : s.id]
}

output "private_route_table_id" {
  description = "Route table that receives BGP-learned routes to Azure."
  value       = aws_route_table.private.id
}

output "vpn_gateway_id" {
  description = "Virtual private gateway ID."
  value       = aws_vpn_gateway.this.id
}

output "flow_log_group" {
  description = "VPC flow log group."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
