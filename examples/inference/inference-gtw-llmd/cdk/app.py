
#!/usr/bin/env python3
"""CDK stack for SageMaker HyperPod Inference Gateway demo.

Deploys: VPC, EKS cluster, FSx Lustre, S3 bucket, IAM roles, and security groups.
"""
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_fsx as fsx,
    aws_iam as iam,
    aws_s3 as s3,
    CfnOutput,
    RemovalPolicy,
)
from aws_cdk.lambda_layer_kubectl_v31 import KubectlV31Layer
from constructs import Construct

ACCOUNT_ID = "REPLACE_WITH_YOUR_ACCOUNT_ID"
REGION = "us-west-2"
CLUSTER_NAME = "hyperpod-ig-demo"


class HyperPodInferenceGatewayStack(Stack):
    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # --- VPC ---
        vpc = ec2.Vpc(
            self, "HyperPodVpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public", subnet_type=ec2.SubnetType.PUBLIC, cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Private", subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS, cidr_mask=24
                ),
            ],
        )

        # --- Security Group ---
        sg = ec2.SecurityGroup(
            self, "HyperPodSG",
            vpc=vpc,
            description="HyperPod Inference Gateway SG",
            allow_all_outbound=True,
        )
        sg.add_ingress_rule(sg, ec2.Port.all_traffic(), "Allow all intra-cluster traffic")
        sg.add_ingress_rule(sg, ec2.Port.tcp_range(988, 1023), "FSx Lustre ports")

        # --- S3 Bucket for lifecycle scripts ---
        bucket = s3.Bucket(
            self, "LifecycleBucket",
            bucket_name=f"hyperpod-ig-demo-{ACCOUNT_ID}-{REGION}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # --- IAM: HyperPod Execution Role ---
        execution_role = iam.Role(
            self, "HyperPodExecutionRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("sagemaker.amazonaws.com"),
                iam.ServicePrincipal("eks.amazonaws.com"),
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3FullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
            ],
        )

        # --- EKS Cluster ---
        kubectl_layer = KubectlV31Layer(self, "KubectlV31Layer")

        private_subnets = vpc.select_subnets(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)

        cluster = eks.Cluster(
            self, "HyperPodEksCluster",
            cluster_name=CLUSTER_NAME,
            version=eks.KubernetesVersion.V1_31,
            vpc=vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            default_capacity=0,
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            kubectl_layer=kubectl_layer,
            masters_role=execution_role,
        )

        # --- FSx Lustre ---
        fsx_filesystem = fsx.LustreFileSystem(
            self, "HyperPodFsx",
            vpc=vpc,
            vpc_subnet=private_subnets.subnets[0],
            security_group=sg,
            storage_capacity_gib=1200,
            lustre_configuration=fsx.LustreConfiguration(
                deployment_type=fsx.LustreDeploymentType.SCRATCH_2,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

        # --- Outputs ---
        CfnOutput(self, "VpcId", value=vpc.vpc_id)
        CfnOutput(self, "EksClusterName", value=cluster.cluster_name)
        CfnOutput(self, "EksClusterEndpoint", value=cluster.cluster_endpoint)
        CfnOutput(self, "HyperPodRoleArn", value=execution_role.role_arn)
        CfnOutput(self, "FsxFileSystemId", value=fsx_filesystem.file_system_id)
        CfnOutput(self, "LifecycleBucketName", value=bucket.bucket_name)
        CfnOutput(
            self, "PrivateSubnetId",
            value=private_subnets.subnets[0].subnet_id,
        )
        CfnOutput(self, "SecurityGroupId", value=sg.security_group_id)


app = cdk.App()
HyperPodInferenceGatewayStack(
    app,
    "HyperPodInferenceGatewayStack",
    env=cdk.Environment(account=ACCOUNT_ID, region=REGION),
)
app.synth()

