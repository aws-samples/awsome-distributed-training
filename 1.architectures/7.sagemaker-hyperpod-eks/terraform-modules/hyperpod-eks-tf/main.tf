data "aws_eks_cluster" "existing_eks_cluster" {
  count = var.create_eks_module ? 0 : 1
  name  = var.existing_eks_cluster_name
}

data "aws_s3_bucket" "existing_s3_bucket" {
  count  =  var.create_s3_bucket_module ? 0 : (var.existing_s3_bucket_name != "" ? 1 : 0)
  bucket = var.existing_s3_bucket_name
}

locals {
  rig_mode                 = length(var.restricted_instance_groups) > 0
  vpc_id                   = var.create_vpc_module ? module.vpc[0].vpc_id : var.existing_vpc_id
  private_subnet_ids       = var.create_private_subnet_module ? module.private_subnet[0].private_subnet_ids : var.existing_private_subnet_ids
  security_group_id        = var.create_security_group_module ? module.security_group[0].security_group_id : var.existing_security_group_id
  s3_bucket_name           = !local.rig_mode ? (var.create_s3_bucket_module ? module.s3_bucket[0].s3_bucket_name : var.existing_s3_bucket_name) : null
  eks_cluster_name         = var.create_eks_module ? module.eks_cluster[0].eks_cluster_name : var.existing_eks_cluster_name
  sagemaker_iam_role_name  = var.create_sagemaker_iam_role_module ? module.sagemaker_iam_role[0].sagemaker_iam_role_name : var.existing_sagemaker_iam_role_name
  deploy_hyperpod          = var.create_hyperpod_module && !(var.create_eks_module && !var.create_helm_chart_module)
  karpenter_role_arn       = var.create_sagemaker_iam_role_module && length(module.sagemaker_iam_role[0].karpenter_role_arn) > 0 ? module.sagemaker_iam_role[0].karpenter_role_arn[0] : null
  nat_gateway_id           = var.create_vpc_module ? module.vpc[0].nat_gateway_1_id : var.existing_nat_gateway_id
  private_route_table_ids  = var.create_private_subnet_module ? module.private_subnet[0].private_route_table_ids : var.existing_private_route_table_ids
  eks_private_subnet_cidrs = [var.eks_private_subnet_1_cidr, var.eks_private_subnet_2_cidr]
  instance_groups          = !local.rig_mode ? var.instance_groups : {}
  enable_cert_manager      = !local.rig_mode && (var.create_hyperpod_training_operator_module || var.create_hyperpod_inference_operator_module) 
}

module "vpc" {
  count  = var.create_vpc_module ? 1 : 0
  source = "./modules/vpc"

  resource_name_prefix = var.resource_name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_1_cidr = var.public_subnet_1_cidr
  public_subnet_2_cidr = var.public_subnet_2_cidr
}

module "private_subnet" {
  count  = var.create_private_subnet_module ? 1 : 0
  source = "./modules/private_subnet"

  resource_name_prefix = var.resource_name_prefix
  vpc_id               = local.vpc_id
  private_subnet_cidrs = var.private_subnet_cidrs
  nat_gateway_id       = local.nat_gateway_id
}

module "security_group" {
  count  = var.create_security_group_module ? 1 : 0
  source = "./modules/security_group"

  resource_name_prefix       = var.resource_name_prefix
  vpc_id                     = local.vpc_id
  create_new_sg              = var.create_eks_module
  existing_security_group_id = var.existing_security_group_id
}

module "eks_cluster" {
  count  = var.create_eks_module ? 1 : 0
  source = "./modules/eks_cluster"

  resource_name_prefix = var.resource_name_prefix
  vpc_id               = local.vpc_id
  eks_cluster_name     = var.eks_cluster_name
  kubernetes_version   = var.kubernetes_version
  security_group_id    = local.security_group_id
  private_subnet_cidrs = local.eks_private_subnet_cidrs
  nat_gateway_id       = local.nat_gateway_id
  
}

module "s3_bucket" {
  count  = !local.rig_mode && var.create_s3_bucket_module ? 1 : 0
  source = "./modules/s3_bucket"

  resource_name_prefix = var.resource_name_prefix
}

module "vpc_endpoints" {
  count  = var.create_vpc_endpoints_module ? 1 : 0
  source = "./modules/vpc_endpoints"

  depends_on = [
      module.private_subnet, 
      module.security_group
  ]
  resource_name_prefix    = var.resource_name_prefix
  vpc_id                  = local.vpc_id
  private_route_table_ids = local.private_route_table_ids
  private_subnet_ids      = local.private_subnet_ids
  security_group_id       = local.security_group_id
  rig_mode                = local.rig_mode
  rig_rft_lambda_access   = var.rig_rft_lambda_access
  rig_rft_sqs_access      = var.rig_rft_sqs_access
  
}

module "lifecycle_script" {
  count  = !local.rig_mode && var.create_lifecycle_script_module ? 1 : 0
  source = "./modules/lifecycle_script"

  resource_name_prefix = var.resource_name_prefix
  s3_bucket_name       = local.s3_bucket_name
}

module "sagemaker_iam_role" {
  count  = var.create_sagemaker_iam_role_module ? 1 : 0
  source = "./modules/sagemaker_iam_role"

  resource_name_prefix  = var.resource_name_prefix
  s3_bucket_name        = local.s3_bucket_name
  rig_input_s3_bucket   = var.rig_input_s3_bucket
  rig_output_s3_bucket  = var.rig_output_s3_bucket
  eks_cluster_name      = local.eks_cluster_name
  security_group_id     = local.security_group_id
  private_subnet_ids    = local.private_subnet_ids
  vpc_id                = local.vpc_id
  rig_mode              = local.rig_mode
  gated_access          = var.gated_access
  rig_rft_lambda_access = var.rig_rft_lambda_access
  rig_rft_sqs_access    = var.rig_rft_sqs_access
  karpenter_autoscaling = var.karpenter_autoscaling
}

module "helm_chart" {
  count  = var.create_helm_chart_module ? 1 : 0
  source = "./modules/helm_chart"

  depends_on = [module.eks_cluster]

  resource_name_prefix                = var.resource_name_prefix
  helm_repo_path                      = var.helm_repo_path
  namespace                           = var.namespace
  helm_release_name                   = var.helm_release_name
  eks_cluster_name                    = local.eks_cluster_name
  helm_repo_revision                  = var.helm_repo_revision
  helm_repo_revision_rig              = var.helm_repo_revision_rig
  enable_gpu_operator                 = var.enable_gpu_operator
  enable_mlflow                       = var.enable_mlflow
  enable_kubeflow_training_operators  = var.enable_kubeflow_training_operators 
  enable_cluster_role_and_bindings    = var.enable_cluster_role_and_bindings
  enable_namespaced_role_and_bindings = var.enable_namespaced_role_and_bindings
  enable_team_role_and_bindings       = var.enable_team_role_and_bindings
  enable_nvidia_device_plugin         = var.enable_nvidia_device_plugin
  enable_neuron_device_plugin         = var.enable_neuron_device_plugin
  enable_mpi_operator                 = var.enable_mpi_operator
  enable_deep_health_check            = var.enable_deep_health_check
  enable_job_auto_restart             = var.enable_job_auto_restart
  enable_hyperpod_patching            = var.enable_hyperpod_patching 
  rig_script_path                     = var.rig_script_path
  rig_mode                            = local.rig_mode
}

module "hyperpod_cluster" {
  count  = local.deploy_hyperpod ? 1 : 0
  source = "./modules/hyperpod_cluster"

  depends_on = [
    module.helm_chart,
    module.eks_cluster,
    module.private_subnet,
    module.security_group,
    module.s3_bucket,
    module.vpc_endpoints,
    module.sagemaker_iam_role
  ]

  resource_name_prefix         = var.resource_name_prefix
  hyperpod_cluster_name        = var.hyperpod_cluster_name
  auto_node_recovery           = var.auto_node_recovery
  instance_groups              = local.instance_groups
  restricted_instance_groups   = var.restricted_instance_groups
  private_subnet_ids           = local.private_subnet_ids
  security_group_id            = local.security_group_id
  eks_cluster_name             = local.eks_cluster_name
  s3_bucket_name               = local.s3_bucket_name
  sagemaker_iam_role_name      = local.sagemaker_iam_role_name
  rig_mode                     = local.rig_mode
  karpenter_autoscaling        = var.karpenter_autoscaling
  continuous_provisioning_mode = var.continuous_provisioning_mode
  karpenter_role_arn           = local.karpenter_role_arn 
}

module "observability" {
  count  = var.create_observability_module ? 1 : 0
  source = "./modules/observability"

  depends_on = [
    module.eks_cluster,
    module.security_group,
    module.private_subnet
  ]

  resource_name_prefix               = var.resource_name_prefix
  vpc_id                             = local.vpc_id
  security_group_id                  = local.security_group_id
  private_subnet_ids                 = local.private_subnet_ids
  eks_cluster_name                   = local.eks_cluster_name
  create_grafana_workspace           = var.create_grafana_workspace
  create_prometheus_workspace        = var.create_prometheus_workspace
  prometheus_workspace_id            = var.prometheus_workspace_id
  prometheus_workspace_arn           = var.prometheus_workspace_arn
  prometheus_workspace_endpoint      = var.prometheus_workspace_endpoint
  create_hyperpod_observability_role = var.create_hyperpod_observability_role
  hyperpod_observability_role_arn    = var.hyperpod_observability_role_arn
  create_grafana_role                = var.create_grafana_role
  grafana_role                       = var.grafana_role
  grafana_workspace_name             = var.grafana_workspace_name
  grafana_workspace_arn              = var.grafana_workspace_arn
  grafana_workspace_role_arn         = var.grafana_workspace_role_arn
  grafana_service_account_name       = var.grafana_service_account_name
  training_metric_level              = var.training_metric_level
  task_governance_metric_level       = var.task_governance_metric_level
  scaling_metric_level               = var.scaling_metric_level
  cluster_metric_level               = var.cluster_metric_level
  node_metric_level                  = var.node_metric_level
  network_metric_level               = var.network_metric_level
  accelerated_compute_metric_level   = var.accelerated_compute_metric_level
  logging_enabled                    = var.logging_enabled
}

module "hyperpod_training_operator" {
  count  = var.create_hyperpod_training_operator_module ? 1 : 0
  source = "./modules/hyperpod_training_operator"

  resource_name_prefix = var.resource_name_prefix
  eks_cluster_name     = local.eks_cluster_name

  depends_on = [
    module.eks_cluster,
    module.helm_chart, 
    module.hyperpod_cluster
  ]
}

