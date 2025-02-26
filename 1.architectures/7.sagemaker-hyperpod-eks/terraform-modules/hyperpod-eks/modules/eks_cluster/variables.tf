variable "resource_name_prefix" {
  description = "Prefix to be used for all resources created by this module"
  type        = string
  default     = "sagemaker-hyperpod-eks"
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "using_sm_code_editor" {
  description = "Import the SageMaker Code Editor IAM Role to create an EKS access entry?"
  type        = bool
  default     = false
}

variable "security_group_id" {
  description = "ID of the security group for the EKS cluster"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}
