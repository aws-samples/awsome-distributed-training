variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "fsdp-training-cluster"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "Instance type for training nodes"
  type        = string
  default     = "ml.g5.8xlarge"

  validation {
    condition     = can(regex("^(ml\\.g5|ml\\.p4d|ml\\.p4de|ml\\.p5en)", var.node_instance_type))
    error_message = "Instance type must be a GPU-enabled SageMaker instance type (ml.g5, ml.p4d, ml.p4de, ml.p5en)."
  }
}

variable "node_count" {
  description = "Number of nodes in the cluster"
  type        = number
  default     = 4

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_efa" {
  description = "Enable EFA (Elastic Fabric Adapter)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "pytorch-fsdp"
    Environment = "training"
  }
}
