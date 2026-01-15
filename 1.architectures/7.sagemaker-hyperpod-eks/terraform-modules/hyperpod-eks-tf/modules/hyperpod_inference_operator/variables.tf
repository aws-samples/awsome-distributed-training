variable "resource_name_prefix" {
  description = "Prefix to be used for all resources"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used by the EKS cluster"
  type        = string
}

variable "hyperpod_cluster_arn" {
  description = "ARN of the HyperPod cluster"
  type        = string
}

variable "access_logs_bucket_name" {
  description = "Name of the S3 bucket for access logs"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
  default     = "kube-system"
}

variable "helm_release_name" {
  description = "The name of the Helm release"
  type        = string
  default     = "hyperpod-inference-operator"
}

variable "helm_repo_revision" {
  description = "Git revision for the HyperPod Inference Operator"
  type        = string
}

variable "helm_repo_path" {
  description = "The path to the HyperPod Inference Operator Helm chart"
  type        = string
  default     = "helm_chart/HyperPodHelmChart/charts/inference-operator"
}