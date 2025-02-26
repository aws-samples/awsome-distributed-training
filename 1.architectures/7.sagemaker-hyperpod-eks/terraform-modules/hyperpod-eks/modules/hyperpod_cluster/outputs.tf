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
