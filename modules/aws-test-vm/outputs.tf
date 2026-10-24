output "instance_id" {
  description = "EC2 instance ID (for SSM)."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP Azure uses to reach the VM."
  value       = aws_instance.this.private_ip
}
