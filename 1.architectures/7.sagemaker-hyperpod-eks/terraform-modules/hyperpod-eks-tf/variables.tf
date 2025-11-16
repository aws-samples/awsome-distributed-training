variable "resource_name_prefix" {
  description = "Prefix to be used for all resources"
  type        = string
  default     = "sagemaker-hyperpod-eks"
}

variable "aws_region" {
  description = "AWS Region to be targeted for deployment"
  type        = string
  default     = "us-west-2"
}

# VPC Module Variables
variable "create_vpc_module" {
  description = "Whether to create VPC module"
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

# Private Subnet Module Variables
variable "create_private_subnet_module" {
  description = "Whether to create private subnet module"
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

# Security Group Module Variables
variable "create_security_group_module" {
  description = "Whether to create security group module"
  type        = bool
  default     = true
}

variable "existing_security_group_id" {
  description = "The ID of an existing security group"
  type        = string
  default     = ""
}

# EKS Cluster Module Variables
variable "create_eks_module" {
  description = "Whether to create EKS cluster module"
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

# S3 Bucket Module Variables
variable "create_s3_bucket_module" {
  description = "Whether to create S3 bucket module"
  type        = bool
  default     = true
}

variable "existing_s3_bucket_name" {
  description = "The name of an existing S3 bucket"
  type        = string
  default     = ""
}

# S3 Endpoint Module Variables
variable "create_s3_endpoint_module" {
  description = "Whether to create S3 endpoint module"
  type        = bool
  default     = true
}

variable "existing_private_route_table_id" {
  description = "The ID of an existing private route table"
  type        = string
  default     = ""
}

# Lifecycle Script Module Variables
variable "create_lifecycle_script_module" {
  description = "Whether to create lifecycle script module"
  type        = bool
  default     = true
}

# SageMaker IAM Role Module Variables
variable "create_sagemaker_iam_role_module" {
  description = "Whether to create SageMaker IAM role module"
  type        = bool
  default     = true
}

variable "existing_sagemaker_iam_role_name" {
  description = "The name of an existing SageMaker IAM role"
  type        = string
  default     = ""
}

variable "rig_input_s3_bucket" {
  description = "The name of the RIG input S3 bucket"
  type        = string
  default     = null 
}

variable "rig_output_s3_bucket" {
  description = "The name of the RIG output S3 bucket"
  type        = string
  default     = null
}

variable "gated_access" {
  description = "Whether to include gated access permissions"
  type        = bool
  default     = true
}

variable "rig_rft_lambda_access" {
  description = "Whether to include Lambda access permissions for RFT"
  type        = bool 
  default     = true
}

variable "rig_rft_sqs_access" {
    description = "Whether to include SQS access permissions for RFT"
  type        = bool 
  default     = true
}

# Helm Chart Module Variables
variable "create_helm_chart_module" {
  description = "Whether to create Helm chart module"
  type        = bool
  default     = true
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

variable "helm_repo_revision" {
  description = "Git revision for normal mode"
  type        = string
  default     = "c5275ddbbca58164d1f5bd3a2811e0fc952f7ff4"
}

variable "helm_repo_revision_rig" {
  description = "Git revision for RIG mode"
  type        = string
  default     = "c00832cd40698943b61e53802114658a61ba45f4"
}

variable "enable_gpu_operator" {
  description = "Whether to enable the GPU operator"
  type        = bool
  default     = false
}

variable "enable_mlflow" {
  description = "Whether to enable the MLFlow"
  type        = bool
  default     = true
}

variable "enable_kubeflow_training_operators" {
  description = "Whether to enable the Kubeflow training operators"
  type        = bool
  default     = true
}

variable "enable_cluster_role_and_bindings" {
  description = "Whether to enable the cluster role and bindings"
  type        = bool
  default     = true
}
variable "enable_namespaced_role_and_bindings" {
  description = "Whether to enable the namespaced role and bindings"
  type        = bool
  default     = true
}

variable "enable_nvidia_device_plugin" {
  description = "Whether to enable the NVIDIA device plugin"
  type        = bool
  default     = true
}

variable "enable_neuron_device_plugin" {
  description = "Whether to enable the Neuron device plugin"
  type        = bool
  default     = true
}

variable "enable_mpi_operator" {
  description = "Whether to enable the MPI operator"
  type        = bool
  default     = true
}

variable "enable_deep_health_check" {
  description = "Whether to enable the deep health check"
  type        = bool
  default     = true
}

variable "enable_job_auto_restart" {
  description = "Whether to enable the job auto restart"
  type        = bool
  default     = true
}

variable "enable_hyperpod_patching" {
  description = "Whether to enable the hyperpod patching"
  type        = bool
  default     = true
}

variable "rig_script_path" {
  description = "The path to the RIG script"
  type        = string
  default     = "helm_chart/install_rig_dependencies.sh"
}

# HyperPod Cluster Module Variables
variable "create_hyperpod_module" {
  description = "Whether to create HyperPod cluster module"
  type        = bool
  default     = true
}

variable "hyperpod_cluster_name" {
  description = "Name of the HyperPod cluster"
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
  default     = true
}

variable "karpenter_autoscaling" {
  description = "Whether to enable Karpenter autoscaling"
  type        = bool
  default     = false
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