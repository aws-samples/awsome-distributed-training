data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

resource "null_resource" "git_clone" {
  triggers = {
    helm_repo_url = var.helm_repo_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf /tmp/helm-repo
      git clone ${var.helm_repo_url} /tmp/helm-repo
    EOT
  }
}

resource "helm_release" "hyperpod" {
  name       = var.helm_release_name
  chart      = "/tmp/helm-repo/${var.helm_repo_path}"
  namespace  = var.namespace
  depends_on = [null_resource.git_clone]

  # Force recreation of the helm release when git repo changes
  lifecycle {
    replace_triggered_by = [
      null_resource.git_clone
    ]
  }
}
