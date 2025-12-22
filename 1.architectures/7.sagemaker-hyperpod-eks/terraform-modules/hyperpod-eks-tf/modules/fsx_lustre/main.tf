data "aws_region" "current" {}

locals {
    wait_for_fsx_csi_driver = var.create_new_filesystem || var.inference_operator_enabled
}

# IAM role for FSx CSI driver
resource "aws_iam_role" "fsx_csi_driver_role" {
  name = "${var.resource_name_prefix}-fsx-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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

resource "aws_iam_role_policy_attachment" "fsx_csi_driver_policy" {
  role       = aws_iam_role.fsx_csi_driver_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonFSxFullAccess"
}

# FSx CSI driver addon
resource "aws_eks_addon" "fsx_lustre_csi_driver" {
  cluster_name             = var.eks_cluster_name
  addon_name               = "aws-fsx-csi-driver"
  service_account_role_arn = aws_iam_role.fsx_csi_driver_role.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Wait for FSx CSI driver to be available (required for the HPIO and dynamic provisioning)
resource "null_resource" "wait_for_fsx_csi_driver" {
  count = local.wait_for_fsx_csi_driver ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${var.eks_cluster_name}
      kubectl wait --for=condition=available deployment/fsx-csi-controller -n kube-system --timeout=300s 
    EOT
  }

  depends_on = [aws_eks_addon.fsx_lustre_csi_driver]
}


# StorageClass for dynamic provisioning
resource "kubernetes_storage_class_v1" "fsx_dynamic" {
  count = var.create_new_filesystem ? 1 : 0

  metadata {
    name = "fsx-sc"
  }
  storage_provisioner = "fsx.csi.aws.com"
  parameters = {
    subnetId                     = var.subnet_id
    securityGroupIds             = var.security_group_id
    deploymentType              = "PERSISTENT_2"
    automaticBackupRetentionDays = "0"
    copyTagsToBackups           = "true"
    perUnitStorageThroughput    = "${var.throughput}"
    dataCompressionType         = var.data_compression_type
    fileSystemTypeVersion       = var.file_system_type_version
  }
  mount_options = ["flock"]
  
  depends_on = [null_resource.wait_for_fsx_csi_driver]
}

# Sample PVC that triggers FSx creation
resource "kubernetes_persistent_volume_claim_v1" "fsx_sample" {
  count = var.create_new_filesystem ? 1 : 0

  metadata {
    name      = "fsx-claim"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteMany"]
    storage_class_name = "fsx-sc"
    resources {
      requests = {
        storage = "${var.storage_capacity}Gi"
      }
    }
  }
  
  depends_on = [kubernetes_storage_class_v1.fsx_dynamic]
}
