output "vm_name" {
  description = "Azure VM name (for az vm run-command)."
  value       = azurerm_linux_virtual_machine.this.name
}

output "private_ip" {
  description = "Private IP AWS uses to reach the VM."
  value       = azurerm_network_interface.this.private_ip_address
}
