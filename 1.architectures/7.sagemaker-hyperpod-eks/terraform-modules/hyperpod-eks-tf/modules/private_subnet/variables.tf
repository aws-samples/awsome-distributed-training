variable "resource_name_prefix" {
  description = "Prefix to be used for all resources created by this module"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_cidr" {
  description = "The IP range (CIDR notation) for the private subnet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zone_id" {
  description = "The Availability Zone Id you wish to create a private subnet in"
  type        = string
  default     = "usw2-az2"

  validation {
    condition     = can(regex("^[a-z]{3,4}[0-9]-az[0-9]$", var.availability_zone_id))
    error_message = "The Availability Zone Id must match the expression ^[a-z]{3,4}[0-9]-az[0-9]$. For example, use1-az4, usw2-az2, or apse1-az2."
  }
}

variable "nat_gateway_id" {
  description = "The Id of a NAT Gateway to route internet bound traffic"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
