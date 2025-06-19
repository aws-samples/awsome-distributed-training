output "karpenter_role_arn" {
  description = "ARN of the Karpenter IAM role"
  value       = try(module.karpenter[0].iam_role_arn, "")
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = try(module.karpenter[0].node_instance_profile_name, "")
}

output "karpenter_queue_name" {
  description = "Name of the Karpenter SQS queue"
  value       = try(module.karpenter[0].queue_name, "")
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the load balancer controller IAM role"
  value       = try(module.load_balancer_controller_irsa_role[0].iam_role_arn, "")
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = module.ebs_csi_irsa_role.iam_role_arn
}

output "efs_csi_driver_role_arn" {
  description = "ARN of the EFS CSI driver IAM role"
  value       = module.efs_csi_irsa_role.iam_role_arn
}

output "node_health_dashboard_url" {
  description = "URL of the CloudWatch dashboard for node health monitoring"
  value       = var.enable_node_health_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.node_health[0].dashboard_name}" : ""
}

output "node_health_sns_topic_arn" {
  description = "ARN of the SNS topic for node health alerts"
  value       = var.enable_sns_alerts ? aws_sns_topic.node_health_alerts[0].arn : ""
}