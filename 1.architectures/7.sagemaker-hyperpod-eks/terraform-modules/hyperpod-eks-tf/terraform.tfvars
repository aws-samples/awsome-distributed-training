resource_name_prefix = "sagemaker-hyperpod-eks"
aws_region           = "us-west-2"

# VPC Module Variables
create_vpc_module    = true
vpc_cidr             = "10.192.0.0/16"
public_subnet_1_cidr = "10.192.10.0/24"
public_subnet_2_cidr = "10.192.11.0/24"
existing_vpc_id      = ""

# Private Subnet Module Variables
create_private_subnet_module = true
private_subnet_cidrs          = ["10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16", "10.4.0.0/16"]
existing_nat_gateway_id      = ""
existing_private_subnet_ids   = []

# Security Group Module Variables
create_security_group_module = true
existing_security_group_id   = ""


# EKS Cluster Module Variables
create_eks_module            = true
kubernetes_version           = "1.33"
eks_cluster_name             = "sagemaker-hyperpod-eks-cluster"
existing_eks_cluster_name    = ""

# EKS Subnet Configuration
# Option 1: Create new subnets for EKS (default)
create_eks_subnets           = true
eks_private_subnet_1_cidr    = "10.192.7.0/28"
eks_private_subnet_2_cidr    = "10.192.8.0/28"

# Option 2: Use existing subnets for EKS (uncomment and set create_eks_subnets = false)
# create_eks_subnets           = false
# existing_eks_subnet_ids      = ["", ""]

# S3 Bucket Module Variables
create_s3_bucket_module = true
existing_s3_bucket_name = ""

# S3 Endpoint Module Variables
create_vpc_endpoints_module     = true
existing_private_route_table_ids = []

# ============================================================================
# CLOSED NETWORK CONFIGURATION
# ============================================================================
# SET ALL TO TRUE FOR CLOSED NETWORK CONFIGURATION (Besides specific VPC endpoints if you have them already)

# EKS API Endpoint Access (CRITICAL for closed networks)

eks_endpoint_private_access = false   # Required for nodes in private subnets to join cluster
eks_endpoint_public_access  = true  # `True` is required for cluster deployment - Set to `False` after cluster creation to disable public access in closed networks

# Control which VPC endpoints to create for closed network environments.
# All endpoints default to true. Set to false to skip creation.

create_s3_endpoint          = true  # S3 gateway endpoint - Always set to true (even without closed network)
create_ec2_endpoint         = false  # CRITICAL - AWS CNI plugin needs this to assign IPs to pods
create_ecr_api_endpoint     = false  # Required for ECR authentication
create_ecr_dkr_endpoint     = false  # Required for pulling container images
create_sts_endpoint         = false  # Required for IAM role assumption (IRSA)
create_logs_endpoint        = false  # Required for CloudWatch Logs
create_monitoring_endpoint  = false  # CloudWatch metrics
create_ssm_endpoint         = false  # Systems Manager access
create_ssmmessages_endpoint = false  # Session Manager
create_ec2messages_endpoint = false  # SSM Agent communication

# VPC Endpoint Security - Allow HTTPS from VPC CIDR
create_vpc_endpoint_ingress_rule = false  # Recommended for closed networks


# ============================================================================
# END OF CLOSED NETWORK CONFIGURATION
# ============================================================================


# Lifecycle Script Module Variables
create_lifecycle_script_module = true

# SageMaker IAM Role Module Variables
create_sagemaker_iam_role_module = true
existing_sagemaker_iam_role_name = ""

# Helm Chart Module Variables
create_helm_chart_module = true
helm_repo_path           = "helm_chart/HyperPodHelmChart"
namespace                = "kube-system"
helm_release_name        = "hyperpod-dependencies"

# HyperPod Cluster Module Variables
create_hyperpod_module       = true
hyperpod_cluster_name        = "ml-cluster"
auto_node_recovery           = true
continuous_provisioning_mode = true

# For the instance_groups variable, you'll need to define specific groups. Here's an example:
instance_groups = [
  {
    name                      = "instance-group-1"
    instance_type             = "ml.g5.8xlarge"
    instance_count            = 8
    availability_zone_id      = "usw2-az2"
    ebs_volume_size_in_gb     = 100
    threads_per_core          = 2
    enable_stress_check       = true
    enable_connectivity_check = true
    lifecycle_script          = "on_create.sh"
  }
]
