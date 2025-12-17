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

variable "security_group_id" {
  description = "ID of the security group for the EKS cluster"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "nat_gateway_id" {
  description = "ID of the NAT gateway for the EKS cluster"
  type        = string
}

variable "enable_cert_manager" {
  description = "Whether to install cert-manager EKS add-on"
  type        = bool
  default     = false
}

variable "cert_manager_version" {
  description = "Version of the cert-manager EKS add-on"
  type        = string
  default     = "v1.18.2-eksbuild.2"
}
