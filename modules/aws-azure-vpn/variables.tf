variable "name" {
  description = "Name prefix for AWS resources."
  type        = string
}

variable "aws_vpn_gateway_id" {
  description = "AWS virtual private gateway ID."
  type        = string
}

variable "aws_bgp_asn" {
  description = "ASN of the AWS virtual private gateway."
  type        = number
}

variable "azure_bgp_asn" {
  description = "ASN of the Azure VPN gateway."
  type        = number
}

variable "azure_gateway_public_ip" {
  description = "Public IP of the Azure VPN gateway."
  type        = string
}

variable "azure_gateway_id" {
  description = "Azure VPN gateway ID."
  type        = string
}

variable "azure_resource_group_name" {
  description = "Azure resource group for the local network gateways and connections."
  type        = string
}

variable "azure_location" {
  description = "Azure region."
  type        = string
}

variable "tunnel_inside_cidrs" {
  description = "Two /30s from 169.254.21.0/24 and 169.254.22.0/24 (the APIPA ranges Azure accepts)."
  type        = list(string)
  default     = ["169.254.21.0/30", "169.254.22.0/30"]

  validation {
    condition     = length(var.tunnel_inside_cidrs) == 2 && alltrue([for c in var.tunnel_inside_cidrs : can(regex("^169\\.254\\.2[12]\\.[0-9]+/30$", c))])
    error_message = "Provide exactly two /30 blocks inside 169.254.21.0/24 or 169.254.22.0/24."
  }
}

variable "alert_email" {
  description = "Email notified when a tunnel goes down. Empty = no subscription."
  type        = string
  default     = ""
}

variable "azure_tags" {
  description = "Tags for Azure resources."
  type        = map(string)
  default     = {}
}
