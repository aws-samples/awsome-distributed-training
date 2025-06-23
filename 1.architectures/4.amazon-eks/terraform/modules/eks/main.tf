module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.21"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  cluster_encryption_config = var.cluster_encryption_config

  cluster_addons = var.cluster_addons

  eks_managed_node_groups = var.eks_managed_node_groups

  node_security_group_additional_rules = var.node_security_group_additional_rules

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = module.eks_managed_node_group_role.iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]

  tags = var.tags
}

resource "aws_iam_role" "eks_managed_node_group_role" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_managed_node_group_role_policy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonFSxClientFullAccess"
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_managed_node_group_role.name
}

resource "aws_iam_instance_profile" "eks_managed_node_group_instance_profile" {
  name = "${var.cluster_name}-node-group-instance-profile"
  role = aws_iam_role.eks_managed_node_group_role.name

  tags = var.tags
}

data "aws_ssm_parameter" "eks_ami_release_version" {
  for_each = var.eks_managed_node_groups
  
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2${each.value.ami_type == "AL2_x86_64_GPU" ? "-gpu" : ""}/recommended/release_version"
}

resource "aws_launch_template" "eks_managed_node_group" {
  for_each = var.eks_managed_node_groups

  name_prefix   = "${var.cluster_name}-${each.key}-"
  image_id      = data.aws_ami.eks_default[each.key].id
  instance_type = each.value.instance_types[0]

  vpc_security_group_ids = [module.eks.node_security_group_id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name        = var.cluster_name
    endpoint            = module.eks.cluster_endpoint
    ca_certificate      = module.eks.cluster_certificate_authority_data
    bootstrap_arguments = each.value.ami_type == "AL2_x86_64_GPU" ? "--container-runtime containerd --use-max-pods false --b64-cluster-ca ${module.eks.cluster_certificate_authority_data} --apiserver-endpoint ${module.eks.cluster_endpoint}" : ""
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type          = "gp3"
      iops                 = 3000
      throughput           = 125
      encrypted            = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${each.key}"
    })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "eks_default" {
  for_each = var.eks_managed_node_groups
  
  most_recent = true
  owners      = ["602401143452"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}