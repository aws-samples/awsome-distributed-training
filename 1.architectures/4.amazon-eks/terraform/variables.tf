variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-reference"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  description = "Private subnets for EKS cluster"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnets for EKS cluster"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Default Node Group Variables
variable "default_instance_types" {
  description = "List of instance types for default node group"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge"]
}

variable "default_min_size" {
  description = "Minimum number of nodes in default node group"
  type        = number
  default     = 1
}

variable "default_max_size" {
  description = "Maximum number of nodes in default node group"
  type        = number
  default     = 10
}

variable "default_desired_size" {
  description = "Desired number of nodes in default node group"
  type        = number
  default     = 3
}

variable "default_health_check_grace_period" {
  description = "Grace period for health checks on default node group (seconds)"
  type        = number
  default     = 300
}

variable "default_health_check_type" {
  description = "Health check type for default node group (EC2 or ELB)"
  type        = string
  default     = "EC2"
  validation {
    condition     = contains(["EC2", "ELB"], var.default_health_check_type)
    error_message = "Health check type must be either EC2 or ELB."
  }
}

# GPU Node Group Variables
variable "gpu_instance_types" {
  description = "List of GPU instance types for GPU node group"
  type        = list(string)
  default     = ["g4dn.xlarge", "g4dn.2xlarge", "p3.2xlarge"]
}

variable "gpu_min_size" {
  description = "Minimum number of nodes in GPU node group"
  type        = number
  default     = 0
}

variable "gpu_max_size" {
  description = "Maximum number of nodes in GPU node group"
  type        = number
  default     = 5
}

variable "gpu_desired_size" {
  description = "Desired number of nodes in GPU node group"
  type        = number
  default     = 1
}

variable "gpu_health_check_grace_period" {
  description = "Grace period for health checks on GPU node group (seconds) - GPU nodes need longer startup time"
  type        = number
  default     = 600
}

variable "gpu_health_check_type" {
  description = "Health check type for GPU node group (EC2 or ELB)"
  type        = string
  default     = "EC2"
  validation {
    condition     = contains(["EC2", "ELB"], var.gpu_health_check_type)
    error_message = "Health check type must be either EC2 or ELB."
  }
}

# FSx for Lustre Variables
variable "fsx_storage_capacity" {
  description = "Storage capacity for FSx Lustre in GiB"
  type        = number
  default     = 1200
}

variable "fsx_deployment_type" {
  description = "Deployment type for FSx Lustre"
  type        = string
  default     = "SCRATCH_2"
  validation {
    condition     = contains(["SCRATCH_1", "SCRATCH_2", "PERSISTENT_1", "PERSISTENT_2"], var.fsx_deployment_type)
    error_message = "Valid values for fsx_deployment_type are SCRATCH_1, SCRATCH_2, PERSISTENT_1, or PERSISTENT_2."
  }
}

variable "fsx_per_unit_storage_throughput" {
  description = "Per unit storage throughput for FSx Lustre in MB/s/TiB"
  type        = number
  default     = 50
}

variable "fsx_s3_import_path" {
  description = "S3 import path for FSx Lustre"
  type        = string
  default     = null
}

variable "fsx_s3_export_path" {
  description = "S3 export path for FSx Lustre"
  type        = string
  default     = null
}

# S3 Mountpoint Variables
variable "s3_mountpoint_bucket_name" {
  description = "S3 bucket name for Mountpoint"
  type        = string
  default     = ""
}

variable "s3_mountpoint_namespace" {
  description = "Kubernetes namespace for S3 Mountpoint CSI driver"
  type        = string
  default     = "kube-system"
}

# Addon Variables
# Karpenter Configuration
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

variable "karpenter_default_capacity_types" {
  description = "Capacity types for Karpenter default node pool"
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "karpenter_default_instance_types" {
  description = "Instance types for Karpenter default node pool"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge", "m5.2xlarge", "m5a.large", "m5a.xlarge", "m5a.2xlarge", "c5.large", "c5.xlarge", "c5.2xlarge"]
}

variable "karpenter_gpu_capacity_types" {
  description = "Capacity types for Karpenter GPU node pool"
  type        = list(string)
  default     = ["on-demand"]
}

variable "karpenter_gpu_instance_types" {
  description = "Instance types for Karpenter GPU node pool"
  type        = list(string)
  default     = ["g4dn.xlarge", "g4dn.2xlarge", "g4dn.4xlarge", "g5.xlarge", "g5.2xlarge", "p3.2xlarge", "p3.8xlarge"]
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

variable "enable_node_health_monitoring" {
  description = "Enable CloudWatch monitoring for node health and auto-repair"
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