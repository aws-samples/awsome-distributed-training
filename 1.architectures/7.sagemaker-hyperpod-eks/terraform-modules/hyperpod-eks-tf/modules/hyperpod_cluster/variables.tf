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

variable "node_provisioning_mode" { 
  description = "Determines the scaling strategy for the SageMaker HyperPod cluster. When set to 'Continuous', enables continuous scaling which dynamically manages node provisioning. Set to null to disable continuous provisioning and use standard scaling approach."
  type        = string
  default     = "Continuous"
  validation {
    condition     = var.node_provisioning_mode == null || var.node_provisioning_mode == "Continuous"
    error_message = "Node provisioning mode must be either 'Continuous' or null"
  }
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
