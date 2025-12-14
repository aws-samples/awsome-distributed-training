variable "resource_name_prefix" {
  description = "Prefix to be used for all resources created by this module"
  type        = string
  default     = "sagemaker-hyperpod-eks"
}

variable "vpc_id" {
  description = "The ID of the VPC where endpoints will be created"
  type        = string
}

variable "security_group_id" {
  description = "The security group ID for the VPC endpoints"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for VPC endpoints"
  type        = list(string)
}

variable "create_grafana_workspace" {
  description = "Specify whether to create new grafana workspace"
  type        = bool
  default     = false
}

variable "create_prometheus_workspace" {
  description = "Specify whether to create new prometheus workspace"
  type        = bool
  default     = false
}

variable "prometheus_workspace_id" {
  description = "The ID of the existing Amazon Managed Service for Prometheus (AMP) workspace"
  type        = string
  default     = ""
}

variable "prometheus_workspace_arn" {
  description = "The ARN of the existing Amazon Managed Service for Prometheus (AMP) workspace"
  type        = string
  default     = ""
}

variable "prometheus_workspace_endpoint" {
  description = "The Endpoint of the existing Amazon Managed Service for Prometheus (AMP) workspace"
  type        = string
  default     = ""
}

variable "create_hyperpod_observability_role" {
  description = "Specify whether to create new role for Hyperpod Observability AddOn"
  type        = bool
  default     = false
}

variable "hyperpod_observability_role_arn" {
  description = "The role to be used with Hyperpod Observability AddOn"
  type        = string
  default     = ""
}

variable "create_grafana_role" {
  description = "Specify whether to create new role for Hyperpod Observability Grafana Custom Resources"
  type        = bool
  default     = false
}

variable "grafana_role" {
  description = "The role to be used with Hyperpod Observability Grafana Custom Resources"
  type        = string
  default     = ""
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
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