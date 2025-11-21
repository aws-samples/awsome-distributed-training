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

variable "private_subnet_id" {
  description = "The Id of the private subnet for HyperPod cross-account ENIs"
  type        = string
}

variable "security_group_id" {
  description = "The Id of your cluster security group"
  type        = string
}

variable "rig_mode" {
  description = "Whether restricted instance groups are configured"
  type        = bool
}

variable "rig_rft_lambda_access" {
  description = "Whether to include Lambda access permissions for RFT"
  type        = bool 
}

variable "rig_rft_sqs_access" {
    description = "Whether to include SQS access permissions for RFT"
  type        = bool 
}