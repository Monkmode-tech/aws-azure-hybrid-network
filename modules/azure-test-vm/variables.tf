variable "name" {
  description = "Name suffix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "subnet_id" {
  description = "Workload subnet (NSG admits only the AWS VPC)."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key (e.g. contents of ~/.ssh/id_ed25519.pub). The private key never leaves your machine."
  type        = string
}

variable "vm_size" {
  description = "VM size."
  type        = string
  default     = "Standard_B1s"
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
