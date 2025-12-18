# IAM Role for HPTO
resource "aws_iam_role" "hpto_role" {
  count = var.enable_training_operator ? 1 : 0

  name = "${var.resource_name_prefix}-hpto-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEksAuthToAssumeRoleForPodIdentity"
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# IAM Policy for HPTO
resource "aws_iam_role_policy_attachment" "hpto-policy" {
  count = var.enable_training_operator ? 1 : 0

  role       = aws_iam_role.hpto_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerHyperPodTrainingOperatorAccess"
}

# Pod Identity Association for HPTO
resource "aws_eks_pod_identity_association" "hpto_pod_identity" {
  count = var.enable_training_operator ? 1 : 0

  cluster_name    = var.eks_cluster_name
  namespace       = "aws-hyperpod"
  service_account = "hp-training-operator-controller-manager"
  role_arn        = aws_iam_role.hpto_role[0].arn
}

# EKS Addon for HPTO
resource "aws_eks_addon" "hpto_addon" {
  count = var.enable_training_operator ? 1 : 0
  
  cluster_name             = var.eks_cluster_name
  addon_name               = "amazon-sagemaker-hyperpod-training-operator"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_pod_identity_association.hpto_pod_identity]
}

# EKS Addon for Task Governance
resource "aws_eks_addon" "task_governance" {
  count = var.enable_task_governance ? 1 : 0

  cluster_name = var.eks_cluster_name
  addon_name   = "amazon-sagemaker-hyperpod-taskgovernance"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [null_resource.wait_for_hyperpod_nodes[0]]
}