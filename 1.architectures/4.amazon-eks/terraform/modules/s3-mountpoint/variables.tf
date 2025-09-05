variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  type        = string
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for the EKS cluster" 
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket to mount"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the S3 Mountpoint CSI driver"
  type        = string
  default     = "kube-system"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "csi_driver_version" {
  description = "Version of the Mountpoint S3 CSI driver"
  type        = string
  default     = "1.4.0"
}

variable "create_example_pvc" {
  description = "Whether to create an example PVC"
  type        = bool
  default     = false
}

variable "create_example_deployment" {
  description = "Whether to create an example deployment"
  type        = bool
  default     = false
}

variable "example_namespace" {
  description = "Namespace for example resources"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}