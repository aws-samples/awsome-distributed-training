data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Karpenter
module "karpenter" {
  count   = var.enable_karpenter ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.21"

  cluster_name = var.cluster_name

  irsa_oidc_provider_arn          = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  # Since Karpenter is running on EKS Managed Node Group,
  # we need to ensure the access entry is not created for the Karpenter node IAM role
  # Reference: https://github.com/aws/karpenter/issues/4002
  create_access_entry = false

  tags = var.tags
}

resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version

  values = [
    <<-EOT
    settings:
      clusterName: ${var.cluster_name}
      clusterEndpoint: ${var.cluster_endpoint}
      interruptionQueue: ${try(module.karpenter[0].queue_name, "")}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${try(module.karpenter[0].iam_role_arn, "")}
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: karpenter.sh/provisioner-name
              operator: DoesNotExist
    EOT
  ]

  depends_on = [module.karpenter]
}

# Karpenter EC2NodeClass for default nodes
resource "kubectl_manifest" "karpenter_node_class_default" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      instanceStorePolicy: RAID0
      amiFamily: AL2
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      instanceProfile: ${try(module.karpenter[0].node_instance_profile_name, "")}
      userData: |
        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name}
        # Install additional packages
        yum update -y
        yum install -y amazon-ssm-agent amazon-cloudwatch-agent
        systemctl enable amazon-ssm-agent
        systemctl start amazon-ssm-agent
        systemctl enable amazon-cloudwatch-agent
        systemctl start amazon-cloudwatch-agent
      tags:
        Name: "Karpenter-${var.cluster_name}-default"
        Environment: ${var.tags.Environment}
        NodeType: "default"
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter EC2NodeClass for GPU nodes
resource "kubectl_manifest" "karpenter_node_class_gpu" {
  count = var.enable_karpenter && var.enable_nvidia_device_plugin ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: gpu
    spec:
      instanceStorePolicy: RAID0
      amiFamily: AL2
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      instanceProfile: ${try(module.karpenter[0].node_instance_profile_name, "")}
      userData: |
        #!/bin/bash
        /etc/eks/bootstrap.sh ${var.cluster_name} --container-runtime containerd
        # Install NVIDIA drivers and container runtime
        yum update -y
        yum install -y nvidia-driver-latest-dkms nvidia-container-toolkit
        yum install -y amazon-ssm-agent amazon-cloudwatch-agent
        
        # Configure containerd for GPU support
        mkdir -p /etc/containerd
        cat > /etc/containerd/config.toml << EOF
        version = 2
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
          BinaryName = "/usr/bin/nvidia-container-runtime"
          SystemdCgroup = true
        EOF
        
        systemctl restart containerd
        systemctl enable amazon-ssm-agent
        systemctl start amazon-ssm-agent
        systemctl enable amazon-cloudwatch-agent
        systemctl start amazon-cloudwatch-agent
      tags:
        Name: "Karpenter-${var.cluster_name}-gpu"
        Environment: ${var.tags.Environment}
        NodeType: "gpu"
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool for default workloads
resource "kubectl_manifest" "karpenter_node_pool_default" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        metadata:
          labels:
            provisioner: karpenter
            node-type: default
        spec:
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1beta1
            kind: EC2NodeClass
            name: default
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ${jsonencode(var.karpenter_default_capacity_types)}
            - key: node.kubernetes.io/instance-type
              operator: In
              values: ${jsonencode(var.karpenter_default_instance_types)}
          nodePolicy:
            terminationGracePeriod: 30s
      limits:
        cpu: 1000
        memory: 1000Gi
      disruption:
        consolidationPolicy: WhenUnderutilized
        consolidateAfter: 30s
        expireAfter: 30m
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class_default]
}

# Karpenter NodePool for GPU workloads
resource "kubectl_manifest" "karpenter_node_pool_gpu" {
  count = var.enable_karpenter && var.enable_nvidia_device_plugin ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: gpu
    spec:
      template:
        metadata:
          labels:
            provisioner: karpenter
            node-type: gpu
            nvidia.com/gpu: "true"
        spec:
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1beta1
            kind: EC2NodeClass
            name: gpu
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ${jsonencode(var.karpenter_gpu_capacity_types)}
            - key: node.kubernetes.io/instance-type
              operator: In
              values: ${jsonencode(var.karpenter_gpu_instance_types)}
            - key: karpenter.k8s.aws/instance-gpu-count
              operator: Gt
              values: ["0"]
          taints:
            - key: nvidia.com/gpu
              value: "true"
              effect: NoSchedule
          nodePolicy:
            terminationGracePeriod: 60s
      limits:
        cpu: 1000
        memory: 1000Gi
        nvidia.com/gpu: 100
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
        expireAfter: 60m
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class_gpu]
}

# AWS Load Balancer Controller
module "load_balancer_controller_irsa_role" {
  count   = var.enable_aws_load_balancer_controller ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                             = "${var.cluster_name}-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.enable_aws_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = try(module.load_balancer_controller_irsa_role[0].iam_role_arn, "")
  }

  set {
    name  = "region"
    value = data.aws_region.current.name
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  depends_on = [module.load_balancer_controller_irsa_role]
}

# NVIDIA Device Plugin
resource "helm_release" "nvidia_device_plugin" {
  count = var.enable_nvidia_device_plugin ? 1 : 0

  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  namespace  = "kube-system"
  version    = "0.14.1"

  set {
    name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key"
    value = "nvidia.com/gpu"
  }

  set {
    name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator"
    value = "In"
  }

  set {
    name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]"
    value = "true"
  }

  set {
    name  = "tolerations[0].key"
    value = "nvidia.com/gpu"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }

  set {
    name  = "tolerations[0].value"
    value = "true"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }
}

# Metrics Server
resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  set {
    name  = "args[0]"
    value = "--cert-dir=/tmp"
  }

  set {
    name  = "args[1]"
    value = "--secure-port=4443"
  }

  set {
    name  = "args[2]"
    value = "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
  }

  set {
    name  = "args[3]"
    value = "--kubelet-use-node-status-port"
  }

  set {
    name  = "args[4]"
    value = "--metric-resolution=15s"
  }
}

# EBS CSI Driver
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# EFS CSI Driver
module "efs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-efs-csi-driver"
  attach_efs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# Node Termination Handler
resource "helm_release" "aws_node_termination_handler" {
  count = var.enable_node_termination_handler ? 1 : 0

  name       = "aws-node-termination-handler"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  namespace  = "kube-system"
  version    = "0.21.0"

  set {
    name  = "enableSpotInterruptionDraining"
    value = "true"
  }

  set {
    name  = "enableRebalanceMonitoring"
    value = "true"
  }

  set {
    name  = "enableScheduledEventDraining"
    value = "true"
  }

  set {
    name  = "enableRebalanceDraining"
    value = "true"
  }

  set {
    name  = "nodeSelector.karpenter\\.sh/provisioner-name"
    value = ""
  }
}

# CloudWatch Dashboard for Node Health Monitoring
resource "aws_cloudwatch_dashboard" "node_health" {
  count          = var.enable_node_health_monitoring ? 1 : 0
  dashboard_name = "${var.cluster_name}-node-health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_count", "ClusterName", var.cluster_name],
            ["AWS/EKS", "cluster_failed_node_count", "ClusterName", var.cluster_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "EKS Node Count"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", { "stat" : "Sum" }],
            ["AWS/EC2", "StatusCheckFailed_Instance", { "stat" : "Sum" }],
            ["AWS/EC2", "StatusCheckFailed_System", { "stat" : "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "EC2 Status Check Failures"
          period  = 300
        }
      }
    ]
  })

  tags = var.tags
}

# CloudWatch Alarms for Node Health
resource "aws_cloudwatch_metric_alarm" "node_health_check_failed" {
  count = var.enable_node_health_monitoring ? 1 : 0

  alarm_name          = "${var.cluster_name}-node-health-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors EC2 instance status check failures for EKS nodes"
  alarm_actions       = var.enable_sns_alerts ? [aws_sns_topic.node_health_alerts[0].arn] : []

  dimensions = {
    AutoScalingGroupName = "*${var.cluster_name}*"
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "gpu_node_health_check_failed" {
  count = var.enable_node_health_monitoring && var.enable_nvidia_device_plugin ? 1 : 0

  alarm_name          = "${var.cluster_name}-gpu-node-health-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "600"  # Longer period for GPU nodes
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "This metric monitors EC2 instance status check failures for EKS GPU nodes"
  alarm_actions       = var.enable_sns_alerts ? [aws_sns_topic.node_health_alerts[0].arn] : []

  dimensions = {
    AutoScalingGroupName = "*${var.cluster_name}*gpu*"
  }

  tags = var.tags
}

# SNS Topic for Node Health Alerts
resource "aws_sns_topic" "node_health_alerts" {
  count = var.enable_sns_alerts ? 1 : 0
  name  = "${var.cluster_name}-node-health-alerts"
  
  tags = var.tags
}

resource "aws_sns_topic_subscription" "node_health_email" {
  count     = var.enable_sns_alerts && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.node_health_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Custom CloudWatch Log Group for Node Auto-Repair Events
resource "aws_cloudwatch_log_group" "node_auto_repair" {
  count             = var.enable_node_health_monitoring ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/node-auto-repair"
  retention_in_days = 30

  tags = var.tags
}