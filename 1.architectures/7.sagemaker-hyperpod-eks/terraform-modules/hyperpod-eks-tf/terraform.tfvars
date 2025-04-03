resource_name_prefix = "sagemaker-hyperpod-eks"

# VPC Stack Variables
create_vpc            = true
vpc_cidr             = "10.192.0.0/16"
public_subnet_1_cidr = "10.192.10.0/24"
public_subnet_2_cidr = "10.192.11.0/24"
existing_vpc_id      = ""

# Private Subnet Stack Variables
create_private_subnet     = true
availability_zone_id     = "usw2-az2"
private_subnet_cidr      = "10.1.0.0/16"
existing_nat_gateway_id  = ""
existing_private_subnet_id = ""

# Security Group Stack Variables
create_security_group      = true
existing_security_group_id = ""

# EKS Cluster Stack Variables
create_eks               = true
kubernetes_version       = "1.31"
eks_cluster_name        = "sagemaker-hyperpod-eks-cluster"
eks_private_subnet_1_cidr = "10.192.7.0/28"
eks_private_subnet_2_cidr = "10.192.8.0/28"
eks_private_node_subnet_cidr = "10.192.9.0/24"
existing_eks_cluster_name = ""

# S3 Bucket Stack Variables
create_s3_bucket         = true
existing_s3_bucket_name  = ""

# S3 Endpoint Stack Variables
create_s3_endpoint               = true
existing_private_route_table_id  = ""

# Lifecycle Script Stack Variables
create_lifecycle_script = true

# SageMaker IAM Role Stack Variables
create_sagemaker_iam_role         = true
existing_sagemaker_iam_role_name  = ""

# Helm Chart Stack Variables
create_helm_chart   = true
helm_repo_url       = "https://github.com/aws/sagemaker-hyperpod-cli.git"
helm_repo_path      = "helm_chart/HyperPodHelmChart"
namespace           = "kube-system"
helm_release_name   = "hyperpod-dependencies"

# HyperPod Cluster Stack Variables
create_hyperpod        = true
hyperpod_cluster_name  = "ml-cluster"
node_recovery          = "Automatic"

# For the instance_groups variable, you'll need to define specific groups. Here's an example:
instance_groups = {
  group1 = {
    instance_type               = "ml.g5.8xlarge"
    instance_count             = 8
    ebs_volume_size           = 100
    threads_per_core          = 2
    enable_stress_check       = true
    enable_connectivity_check = true
    lifecycle_script          = "on_create.sh"
  }
}
