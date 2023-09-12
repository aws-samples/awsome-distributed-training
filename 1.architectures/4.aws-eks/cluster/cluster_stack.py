from aws_cdk import (
    # Duration,
    Stack,
    # aws_sqs as sqs,
)

from constructs import Construct

import aws_cdk.aws_eks as eks
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_iam as iam
import sys
sys.path.append('../')
import config

class ClusterStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # The code that defines your stack goes here

        # example resource
        # queue = sqs.Queue(
        #     self, "ClusterQueue",
        #     visibility_timeout=Duration.seconds(300),
        # )

        # EKS Cluster example: one-liner with default node group
        #cluster = eks.Cluster(self,"HelloEKS", version=eks.KubernetesVersion.V1_27, default_capacity=2, default_capacity_instance=ec2.InstanceType.of(ec2.InstanceClass.M5,ec2.InstanceSize.SMALL)) 

        # Lookup VPC
        #my_vpc = ec2.Vpc.from_lookup(self,"VPC",vpc_id="vpc-*****************")
        my_vpc = ec2.Vpc.from_lookup(self,"VPC",vpc_name=config.vpc_name)

        # Role to access cluster
        admin_role = iam.Role(self, id=config.eks_master_role_name, role_name=config.eks_master_role_name, assumed_by=iam.AccountRootPrincipal(), description="Role to allow admin access to EKS cluster")

        # EKS Cluster example: separate cluster and custom nodegroup creation
        cluster = eks.Cluster(self, id=config.eks_cluster_name, cluster_name=config.eks_cluster_name, version=config.eks_kubernetes_version, default_capacity=0, vpc=my_vpc, masters_role=admin_role, output_cluster_name=True,output_config_command=True, output_masters_role_arn=True )
        cluster.add_nodegroup_capacity("sys-node-group",
                                       instance_types=[ec2.InstanceType(config.eks_sys_ng_instance_type)],
                                       min_size=config.eks_sys_ng_min_size,
                                       desired_size=config.eks_sys_ng_desired_size,
                                       max_size=config.eks_sys_ng_max_size,
                                       disk_size=config.eks_sys_ng_disk_size,
                                       #ami_type=config.eks_sys_ng_ami_type
        ) 
