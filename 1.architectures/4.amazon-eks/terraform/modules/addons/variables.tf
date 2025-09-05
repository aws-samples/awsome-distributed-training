variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  type        = string
  default     = ""
}

variable "enable_karpenter" {
  description = "Enable Karpenter for node provisioning"
  type        = bool
  default     = true
}

variable "karpenter_chart_version" {
  description = "Version of the Karpenter Helm chart"
  type        = string
  default     = "v0.32.1"
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "karpenter_default_capacity_types" {
  description = "Capacity types for Karpenter default node pool"
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "karpenter_default_instance_types" {
  description = "Instance types for Karpenter default node pool"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge", "m5.2xlarge", "m5a.large", "m5a.xlarge", "m5a.2xlarge"]
}

variable "karpenter_gpu_capacity_types" {
  description = "Capacity types for Karpenter GPU node pool"
  type        = list(string)
  default     = ["on-demand"]
}

variable "karpenter_gpu_instance_types" {
  description = "Instance types for Karpenter GPU node pool"
  type        = list(string)
  default     = ["g4dn.xlarge", "g4dn.2xlarge", "g4dn.4xlarge", "g5.xlarge", "g5.2xlarge", "p3.2xlarge"]
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_nvidia_device_plugin" {
  description = "Enable NVIDIA device plugin for GPU support"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable metrics server"
  type        = bool
  default     = true
}

variable "enable_node_termination_handler" {
  description = "Enable AWS Node Termination Handler"
  type        = bool
  default     = true
}

variable "enable_node_health_monitoring" {
  description = "Enable CloudWatch monitoring for node health"
  type        = bool
  default     = true
}

variable "enable_sns_alerts" {
  description = "Enable SNS alerts for node health issues"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for node health alerts"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}