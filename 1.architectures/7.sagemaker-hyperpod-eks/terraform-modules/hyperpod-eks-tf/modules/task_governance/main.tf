# EKS Addon for Task Governance
resource "aws_eks_addon" "task_governance" {
  cluster_name = var.eks_cluster_name
  addon_name   = "amazon-sagemaker-hyperpod-taskgovernance"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "null_resource" "wait_for_kueue_webhook" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for kueue-controller-manager deployment to be ready..."
      kubectl wait --for=condition=available deployment/kueue-controller-manager \
        -n kueue-system \
        --timeout=300s
      echo "Kueue controller manager is ready"
    EOT
  }

  depends_on = [aws_eks_addon.task_governance]
}