# IAM Role for HPTO
# resource "aws_iam_role" "hpto_role" {
#   count = var.enable_training_operator ? 1 : 0

#   name = "${var.resource_name_prefix}-hpto-role"
#   path = "/"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "AllowEksAuthToAssumeRoleForPodIdentity"
#         Effect = "Allow"
#         Principal = {
#           Service = "pods.eks.amazonaws.com"
#         }
#         Action = [
#           "sts:AssumeRole",
#           "sts:TagSession"
#         ]
#       }
#     ]
#   })
# }

# # IAM Policy for HPTO
# resource "aws_iam_role_policy_attachment" "hpto-policy" {
#   count = var.enable_training_operator ? 1 : 0

#   role       = aws_iam_role.hpto_role[0].name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerHyperPodTrainingOperatorAccess"
# }

# Wait for HyperPod nodes and Pod Identity Agent
resource "null_resource" "wait_for_hyperpod_nodes" {
  count = var.wait_for_nodes ? 1 : 0
  
  provisioner "local-exec" {
    command = "${path.module}/../../scripts/wait-for-hyperpod-nodes.sh ${data.aws_region.current.region} ${var.eks_cluster_name} ${var.hyperpod_cluster_name}"
  }
  depends_on = [awscc_sagemaker_cluster.hyperpod_cluster]
}

# # Pod Identity Association for HPTO
# resource "aws_eks_pod_identity_association" "hpto_pod_identity" {
#   count = var.enable_training_operator ? 1 : 0

#   cluster_name    = var.eks_cluster_name
#   namespace       = "aws-hyperpod"
#   service_account = "hp-training-operator-controller-manager"
#   role_arn        = aws_iam_role.hpto_role[0].arn

#   depends_on = [null_resource.wait_for_hyperpod_nodes]
# }

# EKS Addon for Cert Manager (required for HPTO and HPIO)
resource "aws_eks_addon" "cert_manager" {
  count         = var.enable_cert_manager ? 1 : 0
  cluster_name  = var.eks_cluster_name
  addon_name    = "cert-manager"
  addon_version = var.cert_manager_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  configuration_values = jsonencode({
    replicaCount = 1
    tolerations = [
      {
        operator = "Exists"
        effect   = "NoSchedule"
      },
      {
        operator = "Exists"
        effect   = "NoExecute"
      },
      {
        operator = "Exists"
        effect   = "PreferNoSchedule"
      }
    ]
    webhook = {
      replicaCount = 1
      tolerations = [
        {
          operator = "Exists"
          effect   = "NoSchedule"
        },
        {
          operator = "Exists"
          effect   = "NoExecute"
        },
        {
          operator = "Exists"
          effect   = "PreferNoSchedule"
        }
      ]
    }
    cainjector = {
      replicaCount = 1
      tolerations = [
        {
          operator = "Exists"
          effect   = "NoSchedule"
        },
        {
          operator = "Exists"
          effect   = "NoExecute"
        },
        {
          operator = "Exists"
          effect   = "PreferNoSchedule"
        }
      ]
    }
  })
  depends_on = [null_resource.wait_for_hyperpod_nodes]
}

# # EKS Addon for Task Governance
# resource "aws_eks_addon" "task_governance" {
#   count = var.enable_task_governance ? 1 : 0

#   cluster_name = var.eks_cluster_name
#   addon_name   = "amazon-sagemaker-hyperpod-taskgovernance"
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"

#   depends_on = [null_resource.wait_for_hyperpod_nodes]
# }

# Wait for cert-manager to be ready
resource "null_resource" "wait_for_cert_manager" {
  count = var.enable_cert_manager ? 1 : 0
  
  provisioner "local-exec" {
    command = "${path.module}/../../scripts/wait-for-cert-manager.sh ${data.aws_region.current.region} ${var.eks_cluster_name}"
  }
  
  depends_on = [aws_eks_addon.cert_manager]
}

# # EKS Addon for HPTO
# resource "aws_eks_addon" "hpto_addon" {
#   count = var.enable_training_operator ? 1 : 0
  
#   cluster_name             = var.eks_cluster_name
#   addon_name               = "amazon-sagemaker-hyperpod-training-operator"
#   resolve_conflicts_on_create = "OVERWRITE"

#   depends_on = [
#     aws_eks_pod_identity_association.hpto_pod_identity,
#     null_resource.wait_for_cert_manager
#   ]
# }