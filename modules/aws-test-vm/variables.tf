variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the instance."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (for SSM endpoint egress)."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the instance."
  type        = string
}

variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR allowed in and out."
  type        = string
}

variable "instance_type" {
  description = "Graviton instance type."
  type        = string
  default     = "t4g.nano"
}
