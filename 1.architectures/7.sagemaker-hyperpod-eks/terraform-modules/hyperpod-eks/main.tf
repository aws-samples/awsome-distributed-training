provider "aws" {
  region = "us-west-2" # Adjust as needed
}

locals {
  vpc_id = var.create_vpc ? module.vpc[0].vpc_id : var.existing_vpc_id
  private_subnet_id = var.create_private_subnet ? module.private_subnet[0].private_subnet_id : var.existing_private_subnet_id
  security_group_id = var.create_security_group ? module.security_group[0].security_group_id : var.existing_security_group_id
  s3_bucket_name = var.create_s3_bucket ? module.s3_bucket[0].bucket_name : var.existing_s3_bucket_name
  eks_cluster_name = var.create_eks ? module.eks[0].cluster_name : var.eks_cluster_name
  sagemaker_iam_role_name = var.create_sagemaker_iam_role ? module.sagemaker_iam_role[0].role_name : var.existing_sagemaker_iam_role_name
}

module "vpc" {
  count  = var.create_vpc ? 1 : 0
  source = "./modules/vpc"

  resource_name_prefix  = var.resource_name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_1_cidr = var.public_subnet_1_cidr
  public_subnet_2_cidr = var.public_subnet_2_cidr
}

module "private_subnet" {
  count  = var.create_private_subnet ? 1 : 0
  source = "./modules/private_subnet"

  resource_name_prefix = var.resource_name_prefix
  vpc_id              = local.vpc_id
  availability_zone_id = var.availability_zone_id
  private_subnet_cidr  = var.private_subnet_cidr
  nat_gateway_id      = var.create_vpc ? module.vpc[0].nat_gateway_id : var.existing_nat_gateway_id
}

module "security_group" {
  count  = var.create_security_group ? 1 : 0
  source = "./modules/security_group"

  resource_name_prefix = var.resource_name_prefix
  vpc_id              = local.vpc_id
  create_new_sg       = var.create_eks
  existing_sg_id      = var.existing_security_group_id
}

module "eks" {
  count  = var.create_eks ? 1 : 0
  source = "./modules/eks"

  resource_name_prefix     = var.resource_name_prefix
  vpc_id                  = local.vpc_id
  cluster_name            = var.eks_cluster_name
  kubernetes_version      = var.kubernetes_version
  security_group_id       = local.security_group_id
  private_subnet_1_cidr   = var.eks_private_subnet_1_cidr
  private_subnet_2_cidr   = var.eks_private_subnet_2_cidr
  using_sm_code_editor    = var.using_sm_code_editor
  participant_role_arn    = var.participant_role_arn
}

module "s3_bucket" {
  count  = var.create_s3_bucket ? 1 : 0
  source = "./modules/s3_bucket"

  resource_name_prefix = var.resource_name_prefix
}

module "s3_endpoint" {
  count  = var.create_s3_endpoint ? 1 : 0
  source = "./modules/s3_endpoint"

  vpc_id                 = local.vpc_id
  private_route_table_id = var.create_private_subnet ? module.private_subnet[0].private_route_table_id : var.existing_private_route_table_id
}

module "lifecycle_script" {
  count  = var.create_lifecycle_script ? 1 : 0
  source = "./modules/lifecycle_script"

  resource_name_prefix = var.resource_name_prefix
  s3_bucket_name      = local.s3_bucket_name
}

module "sagemaker_iam_role" {
  count  = var.create_sagemaker_iam_role ? 1 : 0
  source = "./modules/sagemaker_iam_role"

  resource_name_prefix = var.resource_name_prefix
  s3_bucket_name      = local.s3_bucket_name
}

module "helm_chart" {
  count  = var.create_helm_chart ? 1 : 0
  source = "./modules/helm_chart"

  depends_on = [module.eks]

  resource_name_prefix = var.resource_name_prefix
  helm_repo_url       = var.helm_repo_url
  helm_repo_path      = var.helm_repo_path
  namespace           = var.namespace
  helm_release        = var.helm_release
  eks_cluster_name    = local.eks_cluster_name
}

module "hyperpod_cluster" {
  count  = var.create_hyperpod ? 1 : 0
  source = "./modules/hyperpod_cluster"

  depends_on = [
    module.helm_chart,
    module.eks,
    module.private_subnet,
    module.security_group,
    module.s3_bucket,
    module.sagemaker_iam_role
  ]

  cluster_name        = var.hyperpod_cluster_name
  node_recovery       = var.node_recovery
  private_subnet_id   = local.private_subnet_id
  security_group_id   = local.security_group_id
  eks_cluster_name    = local.eks_cluster_name
  s3_bucket_name      = local.s3_bucket_name
  sagemaker_iam_role_name = local.sagemaker_iam_role_name

  # Accelerated instance group configuration
  accelerated_instance_group_name = var.accelerated_instance_group_name
  accelerated_instance_type      = var.accelerated_instance_type
  accelerated_instance_count     = var.accelerated_instance_count
  accelerated_ebs_volume_size    = var.accelerated_ebs_volume_size
  accelerated_threads_per_core   = var.accelerated_threads_per_core
  enable_instance_stress_check   = var.enable_instance_stress_check
  enable_instance_connectivity_check = var.enable_instance_connectivity_check
  accelerated_lifecycle_config_on_create = var.accelerated_lifecycle_config_on_create

  # General purpose instance group configuration
  create_general_purpose_group   = var.create_general_purpose_instance_group
  general_purpose_group_name     = var.general_purpose_instance_group_name
  general_purpose_instance_type  = var.general_purpose_instance_type
  general_purpose_instance_count = var.general_purpose_instance_count
  general_purpose_ebs_volume_size = var.general_purpose_ebs_volume_size
  general_purpose_threads_per_core = var.general_purpose_threads_per_core
  general_purpose_lifecycle_config_on_create = var.general_purpose_lifecycle_config_on_create
}

# Data source for current AWS region
data "aws_region" "current" {}
