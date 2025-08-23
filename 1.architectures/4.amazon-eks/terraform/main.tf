terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

locals {
  name = var.cluster_name
  tags = {
    Environment = var.environment
    Project     = "EKS-Reference-Architecture"
    ManagedBy   = "Terraform"
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source = "./modules/vpc"
  
  name = local.name
  cidr = var.vpc_cidr
  
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "karpenter.sh/discovery" = local.name
  }
  
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.name
  }
  
  tags = local.tags
}

module "eks" {
  source = "./modules/eks"
  
  cluster_name    = local.name
  cluster_version = var.cluster_version
  
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets
  
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  
  cluster_encryption_config = [
    {
      provider_key_arn = aws_kms_key.eks.arn
      resources        = ["secrets"]
    }
  ]
  
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
  }
  
  # Karpenter requires at least one managed node group for system pods and Karpenter itself
  eks_managed_node_groups = var.enable_karpenter ? {
    # Minimal node group for Karpenter and system pods
    karpenter = {
      name = "${local.name}-karpenter"
      
      instance_types = ["m5.large"]
      capacity_type  = "ON_DEMAND"
      
      min_size     = 2
      max_size     = 3
      desired_size = 2
      
      ami_type = "AL2_x86_64"
      
      labels = {
        Environment = var.environment
        NodeGroup   = "karpenter"
        "karpenter.sh/discovery" = local.name
      }
      
      # Prevent Karpenter from managing these nodes
      taints = [
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
      
      update_config = {
        max_unavailable_percentage = 25
      }

      # Enable node auto repair
      health_check_grace_period = var.default_health_check_grace_period
      health_check_type         = var.default_health_check_type
      
      tags = merge(local.tags, {
        "karpenter.sh/discovery" = local.name
      })
    }
  } : {
    # Original node groups when Karpenter is disabled
    default = {
      name = "${local.name}-default"
      
      instance_types = var.default_instance_types
      capacity_type  = "ON_DEMAND"
      
      min_size     = var.default_min_size
      max_size     = var.default_max_size
      desired_size = var.default_desired_size
      
      ami_type = "AL2_x86_64"
      
      labels = {
        Environment = var.environment
        NodeGroup   = "default"
      }
      
      taints = []
      
      update_config = {
        max_unavailable_percentage = 25
      }

      # Enable node auto repair
      health_check_grace_period = var.default_health_check_grace_period
      health_check_type         = var.default_health_check_type
      
      tags = local.tags
    }
    
    gpu = {
      name = "${local.name}-gpu"
      
      instance_types = var.gpu_instance_types
      capacity_type  = "ON_DEMAND"
      
      min_size     = var.gpu_min_size
      max_size     = var.gpu_max_size
      desired_size = var.gpu_desired_size
      
      ami_type = "AL2_x86_64_GPU"
      
      labels = {
        Environment    = var.environment
        NodeGroup      = "gpu"
        "nvidia.com/gpu" = "true"
      }
      
      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
      
      update_config = {
        max_unavailable_percentage = 25
      }

      # Enable node auto repair - GPU nodes need longer grace period
      health_check_grace_period = var.gpu_health_check_grace_period
      health_check_type         = var.gpu_health_check_type
      
      tags = local.tags
    }
  }
  
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    ingress_cluster_all = {
      description                   = "Cluster to node all ports/protocols"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }
  
  tags = local.tags
}

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = local.tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/eks-${local.name}"
  target_key_id = aws_kms_key.eks.key_id
}

module "fsx_lustre" {
  source = "./modules/fsx-lustre"
  
  name                     = "${local.name}-lustre"
  subnet_ids               = [module.vpc.private_subnets[0]]
  security_group_ids       = [aws_security_group.fsx_lustre.id]
  storage_capacity         = var.fsx_storage_capacity
  deployment_type          = var.fsx_deployment_type
  per_unit_storage_throughput = var.fsx_per_unit_storage_throughput
  
  s3_import_path = var.fsx_s3_import_path
  s3_export_path = var.fsx_s3_export_path
  
  tags = local.tags
}

resource "aws_security_group" "fsx_lustre" {
  name        = "${local.name}-fsx-lustre"
  description = "Security group for FSx Lustre"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  ingress {
    from_port   = 1021
    to_port     = 1023
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.tags, {
    Name = "${local.name}-fsx-lustre"
  })
}

module "s3_mountpoint" {
  source = "./modules/s3-mountpoint"
  
  cluster_name            = module.eks.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  
  s3_bucket_name = var.s3_mountpoint_bucket_name
  namespace      = var.s3_mountpoint_namespace
  
  tags = local.tags
}

module "addons" {
  source = "./modules/addons"
  
  cluster_name            = module.eks.cluster_name
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  cluster_version         = var.cluster_version
  cluster_endpoint        = module.eks.cluster_endpoint
  vpc_id                  = module.vpc.vpc_id
  
  enable_karpenter = var.enable_karpenter
  karpenter_chart_version = var.karpenter_chart_version
  karpenter_default_capacity_types = var.karpenter_default_capacity_types
  karpenter_default_instance_types = var.karpenter_default_instance_types
  karpenter_gpu_capacity_types = var.karpenter_gpu_capacity_types
  karpenter_gpu_instance_types = var.karpenter_gpu_instance_types
  
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller
  enable_nvidia_device_plugin = var.enable_nvidia_device_plugin
  enable_metrics_server = var.enable_metrics_server
  enable_node_health_monitoring = var.enable_node_health_monitoring
  enable_sns_alerts = var.enable_sns_alerts
  alert_email = var.alert_email
  
  tags = local.tags
}