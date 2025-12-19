# EKS Addon for Task Governance
resource "aws_eks_addon" "task_governance" {
  cluster_name = var.eks_cluster_name
  addon_name   = "amazon-sagemaker-hyperpod-taskgovernance"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}