output "hyperpod_cluster_arn" {
  description = "The ARN of the HyperPod cluster"
  value       = awscc_sagemaker_cluster.hyperpod_cluster.cluster_arn
}

output "hyperpod_cluster_name" {
  description = "The name of the HyperPod cluster"
  value       = awscc_sagemaker_cluster.hyperpod_cluster.cluster_name
}

output "instance_group_names" {
  description = "Names of all instance groups created"
  value       = keys(var.instance_groups)
}

output "restricted_instance_group_names" {
  description = "Names of restricted instance groups created"
  value       = keys(var.restricted_instance_groups)
}

output "hyperpod_cluster_status" {
  description = "The status of the HyperPod cluster"
  value       = awscc_sagemaker_cluster.hyperpod_cluster.cluster_status

}

output "hpto_iam_role_arn" {
  description = "ARN of the HPTO IAM role"
  value       = var.enable_training_operator ? aws_iam_role.hpto_role[0].arn : null
}

output "hpto_iam_role_name" {
  description = "Name of the HPTO IAM role"
  value       = var.enable_training_operator ? aws_iam_role.hpto_role[0].name : null
}

output "hpto_pod_identity_association_arn" {
  description = "ARN of the HPTO Pod Identity Association"
  value       = var.enable_training_operator ? aws_eks_pod_identity_association.hpto_pod_identity[0].association_arn : null
}

output "hpto_addon_arn" {
  description = "ARN of the HPTO addon"
  value       = var.enable_training_operator ? aws_eks_addon.hpto_addon[0].arn : null
}

output "task_governance_addon_arn" {
  description = "ARN of the task governance addon"
  value       = var.enable_task_governance ? aws_eks_addon.task_governance[0].arn : null
}

output "nodes_ready" {
  description = "Indicates HyperPod nodes are ready"
  value       = var.enable_task_governance || var.enable_training_operator || var.wait_for_nodes ? null_resource.wait_for_hyperpod_nodes[0].id : null
}
