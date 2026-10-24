variable "name" {
  description = "Name suffix for Azure resources (rg-<name>, vnet-<name>, ...)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "vnet_cidr" {
  description = "VNet CIDR (a /21 from the IP plan)."
  type        = string
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR, the only source the workload NSG admits."
  type        = string
}

variable "gateway_sku" {
  description = "VPN gateway SKU. AZ SKUs are zone-redundant; non-AZ VpnGw SKUs are being retired."
  type        = string
  default     = "VpnGw1AZ"
}

variable "azure_bgp_asn" {
  description = "Private BGP ASN for the Azure VPN gateway (avoid 65515-65520, reserved by Azure)."
  type        = number
  default     = 65000
}

variable "apipa_addresses" {
  description = "Custom APIPA BGP addresses for the gateway; must equal the customer-side inside addresses of the AWS tunnels."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every Azure resource."
  type        = map(string)
  default     = {}
}
