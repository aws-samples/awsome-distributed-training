# Service Accounts
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller_sa.arn
    }
  }
}

resource "kubernetes_service_account" "s3_csi" {
  metadata {
    name      = "s3-csi-driver-sa"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_csi_sa.arn
    }
    labels = {
      "app.kubernetes.io/component"   = "csi-driver"
      "app.kubernetes.io/instance"    = "aws-mountpoint-s3-csi-driver"
      "app.kubernetes.io/managed-by"  = "EKS"
      "app.kubernetes.io/name"        = "aws-mountpoint-s3-csi-driver"
    }
  }
}