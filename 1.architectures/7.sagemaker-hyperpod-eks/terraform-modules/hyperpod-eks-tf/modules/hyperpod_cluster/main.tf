data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Create configurations for each instance group
  instance_groups_list = [
    for name, config in var.instance_groups : merge(
      {
        instance_group_name = name
        instance_type      = config.instance_type
        instance_count     = config.instance_count
        threads_per_core   = config.threads_per_core
        execution_role     = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.sagemaker_iam_role_name}"
        
        instance_storage_configs = [
          {
            ebs_volume_config = {
              volume_size_in_gb = config.ebs_volume_size
            }
          }
        ]

        life_cycle_config = {
          on_create     = config.lifecycle_script
          source_s3_uri = "s3://${var.s3_bucket_name}"
        }
      },
      # Only include on_start_deep_health_checks if at least one check is enabled
      config.enable_stress_check || config.enable_connectivity_check ? {
        on_start_deep_health_checks = distinct(concat(
          config.enable_stress_check ? ["InstanceStress"] : [],
          config.enable_connectivity_check ? ["InstanceConnectivity"] : []
        ))
      } : {}
    )
  ]
}


resource "awscc_sagemaker_cluster" "hyperpod_cluster" {
  cluster_name = var.hyperpod_cluster_name
  
  instance_groups = local.instance_groups_list

  node_recovery = var.node_recovery

  orchestrator = {
    eks = {
      cluster_arn = "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.eks_cluster_name}"
    }
  }

  vpc_config = {
    security_group_ids = [var.security_group_id]
    subnets           = [var.private_subnet_id]
  }
}
