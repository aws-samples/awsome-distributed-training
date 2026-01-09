variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where to create the cluster"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where the EKS cluster will be deployed"
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "List of subnet IDs where the EKS cluster control plane will be deployed"
  type        = list(string)
}

variable "cluster_endpoint_private_access" {
  description = "Indicates whether or not the Amazon EKS private API server endpoint is enabled"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access" {
  description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_encryption_config" {
  description = "Configuration block with encryption configuration for the cluster"
  type = list(object({
    provider_key_arn = string
    resources        = list(string)
  }))
  default = []
}

variable "cluster_addons" {
  description = "Map of cluster addon configurations to enable for the cluster"
  type = map(object({
    most_recent = optional(bool)
    version     = optional(string)
  }))
  default = {}
}

variable "eks_managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type = map(object({
    name           = string
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    ami_type       = string
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    update_config = object({
      max_unavailable_percentage = number
    })
    health_check_grace_period = optional(number)
    health_check_type         = optional(string)
    tags = map(string)
  }))
  default = {}
}

variable "node_security_group_additional_rules" {
  description = "List of additional security group rules to add to the node security group"
  type        = any
  default     = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}