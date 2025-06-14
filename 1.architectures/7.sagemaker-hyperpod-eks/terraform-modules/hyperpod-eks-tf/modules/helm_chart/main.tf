data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.eks_cluster_name
}

resource "null_resource" "git_clone" {
  triggers = {
    helm_repo_url = var.helm_repo_url
    # Add a random trigger to force recreation
    random = uuid()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting git clone operation..."
      echo "Cleaning up existing directory..."
      rm -rf /tmp/helm-repo
      echo "Creating fresh directory..."
      mkdir -p /tmp/helm-repo
      echo "Cloning from ${var.helm_repo_url}..."
      git clone ${var.helm_repo_url} /tmp/helm-repo
      echo "Contents of /tmp/helm-repo:"
      ls -la /tmp/helm-repo
      echo "Git clone complete"
    EOT
  }
}

resource "null_resource" "helm_dep_update" {
  triggers = {
    helm_repo_url = var.helm_repo_url
    git_clone = null_resource.git_clone.id
    # Add a random trigger to force recreation
    random = uuid()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Starting helm dependency update..."
      echo "Checking for /tmp/helm-repo..."
      if [ ! -d "/tmp/helm-repo" ]; then
        echo "Error: /tmp/helm-repo directory does not exist"
        exit 1
      fi
      
      echo "Checking for chart directory..."
      if [ ! -d "/tmp/helm-repo/${var.helm_repo_path}" ]; then
        echo "Error: Chart directory ${var.helm_repo_path} not found"
        echo "Contents of /tmp/helm-repo:"
        ls -la /tmp/helm-repo
        exit 1
      fi

      echo "Running helm dependency update..."
      helm dependency update /tmp/helm-repo/${var.helm_repo_path}
      echo "Helm dependency update complete"
    EOT
  }

  depends_on = [null_resource.git_clone]
}


resource "helm_release" "hyperpod" {
  name       = var.helm_release_name
  chart      = "/tmp/helm-repo/${var.helm_repo_path}"
  namespace  = var.namespace

  depends_on = [
    null_resource.git_clone,
    null_resource.helm_dep_update
  ]

  # Force recreation of the helm release when git repo changes
  lifecycle {
    replace_triggered_by = [
      null_resource.git_clone,
      null_resource.helm_dep_update
    ]
  }
}
