output "task_governance_addon_arn" {
  description = "ARN of the task governance addon"
  value       = aws_eks_addon.task_governance.arn 
}