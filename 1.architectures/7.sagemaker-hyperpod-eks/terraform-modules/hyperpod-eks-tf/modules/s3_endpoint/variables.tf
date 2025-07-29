variable "vpc_id" {
  description = "The ID of the VPC you wish to use to create an S3 endpoint"
  type        = string
}

variable "private_route_table_id" {
  description = "The Id of your private route table"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

