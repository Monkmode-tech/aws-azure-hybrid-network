variable "name" {
  description = "Name prefix."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR (a /21 from the IP plan)."
  type        = string
}

variable "amazon_side_asn" {
  description = "Private BGP ASN for the AWS virtual private gateway."
  type        = number
  default     = 64512
}

variable "log_retention_days" {
  description = "Flow log retention."
  type        = number
  default     = 30
}
