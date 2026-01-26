variable "resource_name_prefix" {
  description = "Prefix to be used for all resources created by this module"
  type        = string
  default     = "sagemaker-hyperpod-eks"
}

variable "vpc_id" {
  description = "The ID of the VPC you wish to use to create an S3 endpoint"
  type        = string
}

variable "private_route_table_ids" {
  description = "List of private route table IDs for HyperPod subnets"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for HyperPod subnets"
  type        = list(string)
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

# Closed Network - VPC Endpoint Configuration
variable "create_s3_endpoint" {
  description = "Create S3 gateway endpoint (required for container images and data access)"
  type        = bool
  default     = true
}

variable "create_ec2_endpoint" {
  description = "Create EC2 interface endpoint (CRITICAL - required for AWS CNI plugin to assign IPs to pods)"
  type        = bool
  default     = true
}

variable "create_ecr_api_endpoint" {
  description = "Create ECR API interface endpoint (required for ECR authentication and image metadata)"
  type        = bool
  default     = true
}

variable "create_ecr_dkr_endpoint" {
  description = "Create ECR DKR interface endpoint (required for pulling container images from ECR)"
  type        = bool
  default     = true
}

variable "create_sts_endpoint" {
  description = "Create STS interface endpoint (required for IAM role assumption and IRSA)"
  type        = bool
  default     = true
}

variable "create_logs_endpoint" {
  description = "Create CloudWatch Logs interface endpoint (required for sending logs to CloudWatch)"
  type        = bool
  default     = true
}

variable "create_monitoring_endpoint" {
  description = "Create CloudWatch Monitoring interface endpoint (required for sending metrics to CloudWatch)"
  type        = bool
  default     = true
}

variable "create_ssm_endpoint" {
  description = "Create SSM interface endpoint (recommended for Systems Manager access)"
  type        = bool
  default     = true
}

variable "create_ssmmessages_endpoint" {
  description = "Create SSM Messages interface endpoint (recommended for Session Manager)"
  type        = bool
  default     = true
}

variable "create_ec2messages_endpoint" {
  description = "Create EC2 Messages interface endpoint (recommended for SSM Agent communication)"
  type        = bool
  default     = true
}