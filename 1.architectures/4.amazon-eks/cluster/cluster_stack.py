from aws_cdk import (
    Stack,
    Fn,
    aws_eks as eks,
    aws_ec2 as ec2,
    aws_iam as iam
)

from constructs import Construct

import sys


class ClusterStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Lookup VPC

        vpc_id = self.node.try_get_context("vpc_id")
        vpc = ec2.Vpc.from_lookup(self,"VPC",vpc_id=vpc_id)

        # Role to access cluster
        eks_master_role_name = self.node.try_get_context("eks_master_role_name")
        admin_role = iam.Role(self, id=eks_master_role_name,
                              role_name=eks_master_role_name,
                              assumed_by=iam.AccountRootPrincipal(),
                              description="Role to allow admin access to EKS cluster")

        eks_cluster_name = self.node.try_get_context("eks_cluster_name")
        eks_version_config = self.node.try_get_context("eks_kubernetes_version")
        eks_version = eks.KubernetesVersion.of(eks_version_config)

        # EKS Cluster example: separate cluster and custom nodegroup creation
        cluster = eks.Cluster(self, id=eks_cluster_name,
                              cluster_name=eks_cluster_name,
                              version=eks_version,
                              default_capacity=0,
                              vpc=vpc,
                              masters_role=admin_role,
                              output_cluster_name=True,
                              output_config_command=True,
                              output_masters_role_arn=True)

        eks_sys_ng_instance_type = self.node.try_get_context("eks_sys_ng_instance_type")
        eks_sys_ng_min_size = self.node.try_get_context("eks_sys_ng_min_size")
        eks_sys_ng_desired_size = self.node.try_get_context("eks_sys_ng_desired_size")
        eks_sys_ng_max_size = self.node.try_get_context("eks_sys_ng_max_size")
        eks_sys_ng_disk_size = self.node.try_get_context("eks_sys_ng_disk_size")


        cluster.add_nodegroup_capacity("sys-node-group",
                                       instance_types=[ec2.InstanceType(eks_sys_ng_instance_type)],
                                       min_size=eks_sys_ng_min_size,
                                       desired_size=eks_sys_ng_desired_size,
                                       max_size=eks_sys_ng_max_size,
                                       disk_size=eks_sys_ng_disk_size,
        ) 
