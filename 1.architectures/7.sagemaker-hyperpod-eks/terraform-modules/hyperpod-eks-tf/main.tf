locals {
  vpc_id = var.create_vpc ? module.vpc[0].vpc_id : var.existing_vpc_id
  private_subnet_id = var.create_private_subnet ? module.private_subnet[0].private_subnet_id : var.existing_private_subnet_id
  security_group_id = var.create_security_group ? module.security_group[0].security_group_id : var.existing_security_group_id
  s3_bucket_name = var.create_s3_bucket ? module.s3_bucket[0].s3_bucket_name : var.existing_s3_bucket_name
  eks_cluster_name = var.create_eks ? module.eks_cluster[0].eks_cluster_name : var.existing_eks_cluster_name
  sagemaker_iam_role_name = var.create_sagemaker_iam_role ? module.sagemaker_iam_role[0].sagemaker_iam_role_name : var.existing_sagemaker_iam_role_name
}

module "vpc" {
  count  = var.create_vpc ? 1 : 0
  source = "./modules/vpc"

  resource_name_prefix = var.resource_name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_1_cidr = var.public_subnet_1_cidr
  public_subnet_2_cidr = var.public_subnet_2_cidr
}

module "private_subnet" {
  count  = var.create_private_subnet ? 1 : 0
  source = "./modules/private_subnet"

  resource_name_prefix = var.resource_name_prefix
  vpc_id               = local.vpc_id
  availability_zone_id = var.availability_zone_id
  private_subnet_cidr  = var.private_subnet_cidr
  nat_gateway_id       = var.create_vpc ? module.vpc[0].nat_gateway_1_id : var.existing_nat_gateway_id
}

module "security_group" {
  count  = var.create_security_group ? 1 : 0
  source = "./modules/security_group"

  resource_name_prefix       = var.resource_name_prefix
  vpc_id                     = local.vpc_id
  create_new_sg              = var.create_eks
  existing_security_group_id = var.existing_security_group_id
}

module "eks_cluster" {
  count  = var.create_eks ? 1 : 0
  source = "./modules/eks_cluster"

  resource_name_prefix    = var.resource_name_prefix
  vpc_id                  = local.vpc_id
  eks_cluster_name        = var.eks_cluster_name
  kubernetes_version      = var.kubernetes_version
  security_group_id       = local.security_group_id
  private_subnet_cidrs = [var.eks_private_subnet_1_cidr, var.eks_private_subnet_2_cidr]
  private_node_subnet_cidr = var.eks_private_node_subnet_cidr
  nat_gateway_id       = var.create_vpc ? module.vpc[0].nat_gateway_1_id : var.existing_nat_gateway_id

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

  depends_on = [module.eks_cluster]

  resource_name_prefix = var.resource_name_prefix
  helm_repo_url       = var.helm_repo_url
  helm_repo_path      = var.helm_repo_path
  namespace           = var.namespace
  helm_release_name   = var.helm_release_name
  eks_cluster_name    = local.eks_cluster_name
}

module "hyperpod_cluster" {
  count  = var.create_hyperpod ? 1 : 0
  source = "./modules/hyperpod_cluster"

  depends_on = [
    module.helm_chart,
    module.eks_cluster,
    module.private_subnet,
    module.security_group,
    module.s3_bucket,
    module.s3_endpoint,
    module.sagemaker_iam_role
  ]

  resource_name_prefix    = var.resource_name_prefix
  hyperpod_cluster_name   = var.hyperpod_cluster_name
  node_recovery           = var.node_recovery
  instance_groups         = var.instance_groups
  private_subnet_id       = local.private_subnet_id
  security_group_id       = local.security_group_id
  eks_cluster_name        = local.eks_cluster_name
  s3_bucket_name          = local.s3_bucket_name
  sagemaker_iam_role_name = local.sagemaker_iam_role_name

}

# Data source for current AWS region
data "aws_region" "current" {}

data "aws_eks_cluster" "existing_eks_cluster" {
  count  = var.create_eks ? 0 : 1
  name = var.eks_cluster_name
}

data "aws_s3_bucket" "existing_s3_bucket" {
  count  = var.create_s3_bucket ? 0 : 1
  bucket = var.existing_s3_bucket_name
}