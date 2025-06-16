data "aws_iam_policy_document" "s3_mountpoint_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:mountpoint-s3-csi-driver"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [var.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "s3_mountpoint" {
  assume_role_policy = data.aws_iam_policy_document.s3_mountpoint_assume_role_policy.json
  name               = "${var.cluster_name}-s3-mountpoint-csi-driver"
  tags               = var.tags
}

data "aws_iam_policy_document" "s3_mountpoint" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion",
      "s3:ListBucketVersions"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}",
      "arn:aws:s3:::${var.s3_bucket_name}/*"
    ]
  }
}

resource "aws_iam_policy" "s3_mountpoint" {
  description = "S3 Mountpoint CSI Driver Policy"
  name        = "${var.cluster_name}-s3-mountpoint-csi-driver"
  policy      = data.aws_iam_policy_document.s3_mountpoint.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_mountpoint" {
  policy_arn = aws_iam_policy.s3_mountpoint.arn
  role       = aws_iam_role.s3_mountpoint.name
}

# Create the service account
resource "kubernetes_service_account" "s3_mountpoint" {
  metadata {
    name      = "mountpoint-s3-csi-driver"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_mountpoint.arn
    }
  }
}

# Deploy the Mountpoint for S3 CSI driver
resource "helm_release" "mountpoint_s3_csi_driver" {
  name       = "aws-mountpoint-s3-csi-driver"
  repository = "https://awslabs.github.io/mountpoint-s3-csi-driver"
  chart      = "aws-mountpoint-s3-csi-driver"
  namespace  = var.namespace
  version    = var.csi_driver_version

  set {
    name  = "node.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.s3_mountpoint.arn
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.s3_mountpoint.arn
  }

  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "node.tolerateAllTaints"
    value = "true"
  }

  depends_on = [kubernetes_service_account.s3_mountpoint]
}

# Create a storage class for S3 Mountpoint
resource "kubernetes_storage_class" "s3_mountpoint" {
  metadata {
    name = "s3-mountpoint-sc"
  }
  
  storage_provisioner = "s3.csi.aws.com"
  
  parameters = {
    bucketName = var.s3_bucket_name
    region     = var.region
  }
  
  volume_binding_mode = "Immediate"
}

# Example PVC for S3 Mountpoint
resource "kubernetes_persistent_volume_claim" "s3_mountpoint_example" {
  count = var.create_example_pvc ? 1 : 0
  
  metadata {
    name      = "s3-mountpoint-pvc"
    namespace = var.example_namespace
  }
  
  spec {
    access_modes = ["ReadWriteMany"]
    
    resources {
      requests = {
        storage = "1000Gi"
      }
    }
    
    storage_class_name = kubernetes_storage_class.s3_mountpoint.metadata[0].name
  }
}

# Example deployment using S3 Mountpoint
resource "kubernetes_deployment" "s3_mountpoint_example" {
  count = var.create_example_deployment ? 1 : 0
  
  metadata {
    name      = "s3-mountpoint-example"
    namespace = var.example_namespace
    labels = {
      app = "s3-mountpoint-example"
    }
  }
  
  spec {
    replicas = 1
    
    selector {
      match_labels = {
        app = "s3-mountpoint-example"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "s3-mountpoint-example"
        }
      }
      
      spec {
        container {
          image = "busybox:latest"
          name  = "busybox"
          
          command = ["/bin/sh"]
          args    = ["-c", "while true; do echo $(date) >> /mnt/s3/test.txt; sleep 30; done"]
          
          volume_mount {
            mount_path = "/mnt/s3"
            name       = "s3-volume"
          }
        }
        
        volume {
          name = "s3-volume"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.s3_mountpoint_example[0].metadata[0].name
          }
        }
      }
    }
  }
}