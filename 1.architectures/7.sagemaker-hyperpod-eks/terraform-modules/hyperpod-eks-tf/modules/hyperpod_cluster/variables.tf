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

variable "auto_node_recovery" {
  description = "Whether to enable or disable the automatic node recovery feature"
  type        = bool
  default     = true
}

variable "continuous_provisioning_mode" {
  description = "whether to enable continuous node provisioning mode"
  type        = bool 
}

variable "instance_groups" {
  description = "Map of instance group configurations"
  type = map(object({
    instance_type             = string
    instance_count            = number
    ebs_volume_size_in_gb     = number
    threads_per_core          = number
    enable_stress_check       = bool
    enable_connectivity_check = bool
    lifecycle_script          = string
    image_id                  = optional(string)
    training_plan_arn         = optional(string)
  }))
  default = {}
}

variable "restricted_instance_groups" {
  description = "Map of restricted instance group configurations"
  type = map(object({
    instance_type                    = string
    instance_count                   = number
    ebs_volume_size_in_gb            = number
    threads_per_core                 = number
    enable_stress_check              = bool
    enable_connectivity_check        = bool
    fsxl_per_unit_storage_throughput = number
    fsxl_size_in_gi_b                = number
    training_plan_arn                = optional(string)
  }))
  default = {}
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

variable "rig_mode" {
  description = "Whether restricted instance groups are configured"
  type        = bool
}

variable "karpenter_autoscaling" {
  description = "Whether to enable Karpenter autoscaling"
  type        = bool
}
