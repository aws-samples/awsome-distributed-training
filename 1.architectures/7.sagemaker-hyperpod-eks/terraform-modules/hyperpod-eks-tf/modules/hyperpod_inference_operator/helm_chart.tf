resource "kubernetes_namespace_v1" "keda" {
  metadata {
    name = "keda"
  }
}

resource "null_resource" "git_checkout" {
  provisioner "local-exec" {
    command = <<-EOT
      cd /tmp/helm-repo
      git reset --hard HEAD
      git clean -fd
      git checkout ${var.helm_repo_revision}
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

resource "helm_release" "inference_operator" {
  name       = var.helm_release_name
  chart      = "/tmp/helm-repo/${var.helm_repo_path}"
  namespace  = var.namespace
  dependency_update = true
  wait = false
  
  set  = [
    {
        name  = "region"
        value = data.aws_region.current.region
    },
    {
        name  = "eksClusterName"
        value = var.eks_cluster_name
    },
    {
        name  = "hyperpodClusterArn"
        value = var.hyperpod_cluster_arn
    },
    {
        name  = "executionRoleArn"
        value = aws_iam_role.inference_operator.arn
    },
    {
        name  = "s3.serviceAccountRoleArn"
        value = aws_iam_role.s3_csi_sa.arn
    },
    {
        name  = "s3.node.serviceAccount.create"
        value = "false"
    },
    {
        name  = "keda.podIdentity.aws.irsa.roleArn"
        value = aws_iam_role.keda.arn
    },
    {
        name  = "tlsCertificateS3Bucket"
        value = "s3://${aws_s3_bucket.tls_certificates.id}"
    },
    {
        name  = "alb.region"
        value = data.aws_region.current.region
    },
    {
        name  = "alb.clusterName"
        value = var.eks_cluster_name
    },
    {
        name  = "alb.vpcId"
        value = var.vpc_id
    },
    {
        name  = "jumpstartGatedModelDownloadRoleArn"
        value = aws_iam_role.gated.arn
    },
    {
        name  = "fsx.enabled"
        value = "false"
    },
    {
        name  = "cert-manager.enabled"
        value = "false"
    }
  ]

  depends_on = [
    null_resource.git_checkout,
    kubernetes_namespace_v1.keda,
    kubernetes_service_account_v1.alb_controller,
    kubernetes_service_account_v1.s3_csi
  ]
}

resource "null_resource" "git_cleanup" {
  provisioner "local-exec" {
    command = <<-EOT
      cd /tmp/helm-repo
      git checkout main
    EOT
  }
  
  depends_on = [helm_release.inference_operator]
  
  triggers = {
    always_run = timestamp()
  }
}
