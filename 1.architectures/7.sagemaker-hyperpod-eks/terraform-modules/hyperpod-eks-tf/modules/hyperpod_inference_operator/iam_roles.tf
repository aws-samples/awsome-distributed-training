
resource "aws_iam_role" "inference_operator" {
  name = "${var.resource_name_prefix}IORole"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_url_without_protocol}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${local.oidc_provider_url_without_protocol}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider_url_without_protocol}:sub" = "system:serviceaccount:*:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "inference_operator_policy" {
  name = "${var.resource_name_prefix}-InfOperator-Policy"
  role = aws_iam_role.inference_operator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject", 
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.tls_certificates.arn,
          "${aws_s3_bucket.tls_certificates.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "ECRAuthorization"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      {
        Sid    = "SageMakerAccess"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig", 
          "sagemaker:CreateEndpoint",
          "sagemaker:DeleteModel",
          "sagemaker:DeleteEndpointConfig",
          "sagemaker:DeleteEndpoint",
          "sagemaker:UpdateEndpoint",
          "sagemaker:DescribeModel",
          "sagemaker:DescribeEndpointConfig",
          "sagemaker:DescribeEndpoint",
          "sagemaker:DescribeCluster",
          "sagemaker:DescribeClusterInference",
          "sagemaker:UpdateClusterInference",
          "sagemaker:ListModels",
          "sagemaker:ListTags",
          "sagemaker:AddTags"
        ]
        Resource = [
          "arn:aws:sagemaker:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowPassRoleToSageMaker"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.resource_name_prefix}IORole"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "sagemaker.amazonaws.com"
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "keda" {
  name = "${var.resource_name_prefix}KedaRole"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_url_without_protocol}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${local.oidc_provider_url_without_protocol}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider_url_without_protocol}:sub" = "system:serviceaccount:kube-system:keda-operator"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "keda_policy" {
  name = "${var.resource_name_prefix}-keda-policy"
  role = aws_iam_role.keda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "gated" {
  name = "${var.resource_name_prefix}GateRole"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_url_without_protocol}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${local.oidc_provider_url_without_protocol}:aud" = "sts.amazonaws.com"
            "${local.oidc_provider_url_without_protocol}:sub" = "system:serviceaccount:*:hyperpod-inference-service-account*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "gated_policy" {
  name = "${var.resource_name_prefix}-Gated-Policy"
  role = aws_iam_role.gated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreatePresignedUrlAccess"
        Effect = "Allow"
        Action = ["sagemaker:CreateHubContentPresignedUrls"]
        Resource = [
          "arn:aws:sagemaker:${data.aws_region.current.name}:aws:hub/SageMakerPublicHub",
          "arn:aws:sagemaker:${data.aws_region.current.name}:aws:hub-content/SageMakerPublicHub/*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "alb_controller" {
  name = "${var.resource_name_prefix}-load-balancer-controller-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "s3_mountpoint" {
  name = "${var.resource_name_prefix}-s3-mountpoint-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MountpointFullBucketAccess"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::*"]
      },
      {
        Sid    = "MountpointObjectReadAccess"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::*/*"]
      }
    ]
  })
}

resource "aws_iam_role" "alb_controller_sa" {
  name = "${var.resource_name_prefix}-alb-controller-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_url_without_protocol}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url_without_protocol}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${local.oidc_provider_url_without_protocol}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller_policy" {
  role       = aws_iam_role.alb_controller_sa.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_iam_role" "s3_csi_sa" {
  name = "${var.resource_name_prefix}-inf-s3-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_url_without_protocol}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url_without_protocol}:sub" = "system:serviceaccount:kube-system:s3-csi-driver-sa"
            "${local.oidc_provider_url_without_protocol}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_csi_policy" {
  role       = aws_iam_role.s3_csi_sa.name
  policy_arn = aws_iam_policy.s3_mountpoint.arn
}