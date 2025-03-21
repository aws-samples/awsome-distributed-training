variable "resource_name_prefix" {
  description = "Prefix to be used for all resources"
  type        = string
  default     = "sagemaker-hyperpod-eks"
}

# VPC Stack Variables
variable "create_vpc" {
  description = "Whether to create VPC stack"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "The IP range (CIDR notation) for the VPC"
  type        = string
  default     = "10.192.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "The IP range (CIDR notation) for the public subnet in the first Availability Zone"
  type        = string
  default     = "10.192.10.0/24"
}

variable "public_subnet_2_cidr" {
  description = "The IP range (CIDR notation) for the public subnet in the second Availability Zone"
  type        = string
  default     = "10.192.11.0/24"
}

variable "existing_vpc_id" {
  description = "The ID of an existing VPC to use if not creating a new one"
  type        = string
  default     = ""
}

# Private Subnet Stack Variables
variable "create_private_subnet" {
  description = "Whether to create private subnet stack"
  type        = bool
  default     = true
}

variable "availability_zone_id" {
  description = "The Availability Zone Id for private subnet"
  type        = string
  default     = "usw2-az2"
}

variable "private_subnet_cidr" {
  description = "The IP range (CIDR notation) for the private subnet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "existing_nat_gateway_id" {
  description = "The ID of an existing NAT Gateway"
  type        = string
  default     = ""
}

variable "existing_private_subnet_id" {
  description = "The ID of an existing private subnet"
  type        = string
  default     = ""
}

# Security Group Stack Variables
variable "create_security_group" {
  description = "Whether to create security group stack"
  type        = bool
  default     = true
}

variable "existing_security_group_id" {
  description = "The ID of an existing security group"
  type        = string
  default     = ""
}

# EKS Cluster Stack Variables
variable "create_eks" {
  description = "Whether to create EKS cluster stack"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "The Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "sagemaker-hyperpod-eks-cluster"
}

variable "existing_eks_cluster_name" {
  description = "The name of an existing EKS cluster"
  type        = string
  default     = ""
}

variable "eks_private_subnet_1_cidr" {
  description = "The IP range (CIDR notation) for the first EKS private subnet"
  type        = string
  default     = "10.192.7.0/28"
}

variable "eks_private_subnet_2_cidr" {
  description = "The IP range (CIDR notation) for the second EKS private subnet"
  type        = string
  default     = "10.192.8.0/28"
}

variable "eks_private_node_subnet_cidr" {
  description = "The IP range (CIDR notation) for the EKS private node subnet"
  type        = string
  default     = "10.192.9.0/24"
}

# S3 Bucket Stack Variables
variable "create_s3_bucket" {
  description = "Whether to create S3 bucket stack"
  type        = bool
  default     = true
}

variable "existing_s3_bucket_name" {
  description = "The name of an existing S3 bucket"
  type        = string
  default     = ""
}

# S3 Endpoint Stack Variables
variable "create_s3_endpoint" {
  description = "Whether to create S3 endpoint stack"
  type        = bool
  default     = true
}

variable "existing_private_route_table_id" {
  description = "The ID of an existing private route table"
  type        = string
  default     = ""
}

# Lifecycle Script Stack Variables
variable "create_lifecycle_script" {
  description = "Whether to create lifecycle script stack"
  type        = bool
  default     = true
}

# SageMaker IAM Role Stack Variables
variable "create_sagemaker_iam_role" {
  description = "Whether to create SageMaker IAM role stack"
  type        = bool
  default     = true
}

variable "existing_sagemaker_iam_role_name" {
  description = "The name of an existing SageMaker IAM role"
  type        = string
  default     = ""
}

# Helm Chart Stack Variables
variable "create_helm_chart" {
  description = "Whether to create Helm chart stack"
  type        = bool
  default     = true
}

variable "helm_repo_url" {
  description = "The URL of the Helm repo"
  type        = string
  default     = "https://github.com/aws/sagemaker-hyperpod-cli.git"
}

variable "helm_repo_path" {
  description = "The path to the HyperPod Helm chart"
  type        = string
  default     = "helm_chart/HyperPodHelmChart"
}

variable "namespace" {
  description = "The Kubernetes namespace"
  type        = string
  default     = "kube-system"
}

variable "helm_release_name" {
  description = "The name of the Helm release"
  type        = string
  default     = "hyperpod-dependencies"
}

# HyperPod Cluster Stack Variables
variable "create_hyperpod" {
  description = "Whether to create HyperPod cluster stack"
  type        = bool
  default     = true
}

variable "hyperpod_cluster_name" {
  description = "Name of the HyperPod cluster"
  type        = string
  default     = "ml-cluster"
}

variable "node_recovery" {
  description = "Node recovery mode"
  type        = string
  default     = "Automatic"
}

variable "instance_groups" {
  description = "Map of instance group configurations"
  type = map(object({
    instance_type       = string
    instance_count      = number
    ebs_volume_size    = number
    threads_per_core   = number
    enable_stress_check = bool
    enable_connectivity_check = bool
    lifecycle_script    = string
  }))
}