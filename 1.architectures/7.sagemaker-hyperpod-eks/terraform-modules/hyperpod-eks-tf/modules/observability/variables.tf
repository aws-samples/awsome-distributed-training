variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where endpoints will be created"
}

variable "security_group_id" {
  type        = string
  description = "The security group ID for the VPC endpoints"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for VPC endpoints"
}

variable "resource_name_prefix" {
  type        = string
  default     = "sagemaker-hyperpod-eks"
  description = "Prefix to be used for all resources"
}

variable "create_grafana_workspace" {
  type        = string
  default     = "false"
  description = "Specify whether to create new grafana workspace"
  validation {
    condition     = contains(["true", "false", "disabled"], var.create_grafana_workspace)
    error_message = "Must be 'true', 'false', or 'disabled'."
  }
}

variable "create_prometheus_workspace" {
  type        = bool
  default     = false
  description = "Specify whether to create new prometheus workspace"
}

variable "prometheus_workspace_id" {
  type        = string
  default     = ""
  description = "The ID of the existing Amazon Managed Service for Prometheus (AMP) workspace"
}

variable "prometheus_workspace_arn" {
  type        = string
  default     = ""
  description = "The ARN of the existing Amazon Managed Service for Prometheus (AMP) workspace"
}

variable "prometheus_workspace_endpoint" {
  type        = string
  default     = ""
  description = "The Endpoint of the existing Amazon Managed Service for Prometheus (AMP) workspace"
}

variable "create_hyperpod_observability_role" {
  type        = bool
  default     = false
  description = "Specify whether to create new role for Hyperpod Observability AddOn"
}

variable "hyperpod_observability_role_arn" {
  type        = string
  default     = ""
  description = "The role to be used with Hyperpod Observability AddOn"
}

variable "create_grafana_role" {
  type        = bool
  default     = false
  description = "Specify whether to create new role for Hyperpod Observability Grafana Custom Resources"
}

variable "grafana_role" {
  type        = string
  default     = ""
  description = "The role to be used with Hyperpod Observability Grafana Custom Resources"
}

variable "eks_cluster_name" {
  type        = string
  description = "The name of the EKS cluster"
}

variable "grafana_workspace_name" {
  description = "Name of the Grafana workspace"
  type        = string
}

variable "grafana_workspace_arn" {
  description = "ARN of existing Grafana workspace"
  type        = string
}

variable "grafana_workspace_role_arn" {
  description = "ARN of the IAM role for Grafana workspace"
  type        = string
}

variable "grafana_service_account_name" {
  description = "Name of the service account"
  type        = string
}

variable "training_metric_level" {
  description = "Level of training metrics"
  type        = string
  default     = "BASIC"
}

variable "task_governance_metric_level" {
  description = "Level of task governance metrics"
  type        = string
  default     = "DISABLED"
}

variable "scaling_metric_level" {
  description = "Level of scaling metrics"
  type        = string
  default     = "DISABLED"
}

variable "cluster_metric_level" {
  description = "Level of cluster metrics"
  type        = string
  default     = "BASIC"
}

variable "node_metric_level" {
  description = "Level of node metrics"
  type        = string
  default     = "BASIC"
}

variable "network_metric_level" {
  description = "Level of network metrics"
  type        = string
  default     = "DISABLED"
}

variable "accelerated_compute_metric_level" {
  description = "Level of accelerated compute metrics"
  type        = string
  default     = "BASIC"
}

variable "logging_enabled" {
  description = "Enable logging"
  type        = bool
  default     = false
}

