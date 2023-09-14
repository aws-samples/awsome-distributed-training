import aws_cdk.aws_eks as eks

vpc_name="ML EKS VPC"
eks_cluster_name="eks-cdk"
eks_master_role_name="EKSMaster"
eks_sys_ng_instance_type="m5.large"
eks_sys_ng_disk_size=50
eks_sys_ng_min_size=1
eks_sys_ng_desired_size=2
eks_sys_ng_max_size=10
#eks_sys_ng_ami_type=eks.NodegroupAmiType.AL2_X86_64
eks_kubernetes_version=eks.KubernetesVersion.V1_27