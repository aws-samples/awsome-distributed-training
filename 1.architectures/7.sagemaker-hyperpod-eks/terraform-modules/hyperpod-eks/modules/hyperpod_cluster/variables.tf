variable "resource_name_prefix" {
  description = "Prefix to be used for all resources created by this module"
  type        = string
  default     = "sagemaker-hyperpod-eks"
}

variable "hyperpod_cluster_name" {
  description = "Name of SageMaker HyperPod Cluster"
  type        = string
  default     = "ml-cluster"
}

variable "node_recovery" {
  description = "Specifies whether to enable or disable the automatic node recovery feature"
  type        = string
  default     = "Automatic"
  validation {
    condition     = contains(["Automatic", "None"], var.node_recovery)
    error_message = "Node recovery must be either 'Automatic' or 'None'"
  }
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

variable "sagemaker_iam_role_name" {
  description = "The name of the IAM role that SageMaker will use"
  type        = string
}

variable "private_subnet_id" {
  description = "The Id of the private subnet for HyperPod cross-account ENIs"
  type        = string
}

variable "security_group_id" {
  description = "The Id of your cluster security group"
  type        = string
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket used to store the cluster lifecycle scripts"
  type        = string
}
