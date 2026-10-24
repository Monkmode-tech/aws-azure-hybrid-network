variable "name" {
  description = "Name used on both clouds."
  type        = string
  default     = "hybrid-lab"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "caleb-tetteh"
}

variable "company_supernet" {
  description = "Company IPv4 block (/19). Split into four /21 sites: AWS, Azure, on-premises, growth."
  type        = string
  default     = "172.16.32.0/19"

  validation {
    condition     = can(cidrhost(var.company_supernet, 0)) && endswith(var.company_supernet, "/19")
    error_message = "company_supernet must be a /19 (see docs/ip-plan.md)."
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-2"
}

variable "azure_location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "azure_subscription_id" {
  description = "Azure subscription to deploy into (az account show --query id -o tsv)."
  type        = string
}

variable "aws_bgp_asn" {
  description = "BGP ASN of the AWS side."
  type        = number
  default     = 64512
}

variable "azure_bgp_asn" {
  description = "BGP ASN of the Azure side."
  type        = number
  default     = 65000
}

variable "azure_gateway_sku" {
  description = "Azure VPN gateway SKU (BGP needs VpnGw1 or higher)."
  type        = string
  default     = "VpnGw1AZ"
}

variable "azure_vm_size" {
  description = "Azure test VM size."
  type        = string
  default     = "Standard_B1s"
}

variable "ssh_public_key" {
  description = "SSH public key for the Azure VM (contents of your .pub file)."
  type        = string
}

variable "alert_email" {
  description = "Email for VPN tunnel-down alerts."
  type        = string
  default     = ""
}
