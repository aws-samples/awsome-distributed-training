---
title : "1. In Your Own Account"
weight : 1
---
If deploying this **outside of an AWS run event** you'll need to do the following:

### Deploy the AWS CloudFormation Stack

We have provided an cloudformation template that helps you to setup vpc, subnets, EKS cluster and necessary SageMaker Permissions. The template can be used in 3 scenarios
1. **Full Deployment** - Use full deployment mode if you want to create a new VPC and EKS cluster.
2. **Integrative Deployment** - Use integrative deployment mode if you want to use your own VPC and EKS cluster, but need to create an additional /16 CIDR block, a private subnet, and a security group for the SageMaker HyperPod Cluster.
3. **Minimal Deployment** - Use minimal deployment mode if you want to use your own VPC and EKS cluster, and you want to manage the subnet and security group configurations in your environment by yourself. This optional only creates SageMaker HyperPod specific resources like role, bucket needed for cluster creation. 

Click on the tab for each deployment option to learn more about the parameters that has to be set in order to use it.

:::::tabs{variant="container" activeTabId="Full Deployment"}
::::tab{id="Full Deployment" label="Full Deployment"}
Use full deployment mode if you want to create a new VPC and EKS cluster for the workshop. 

:::expand{header="Parameter Requirements" defaultExpanded=false}
Set the following parameters accordingly if you want to use full deployment mode. 
- Set `CreateEKSCluster` to `true`
- Provide the `AvailabilityZoneId` (`usw2-az2` for the `us-west-2` region by default). Update this parameter based on your region and the Availability Zone that you have accelerated compute capacity in. An additional CIDR block will be added to your VPC with a /16 private subnet in the specified Availability Zone. This private subnet will be used to deploy the HyperPod cross-account elastic network intefaces (ENIs), which give you access to the HyperPod capacity you deploy.
- Accept all other defaults (or modify VPC CIDR ranges as desired)
:::

:::expand{header="Ignored Parameters" defaultExpanded=false}
These parameters are ignored because all the referenced resources are being created for you. 
- `CreateSubnet`
- `NatGatewayId`
- `SecurityGroupId`
- `VpcId`
:::

:::expand{header="Resources Created" defaultExpanded=false}
The following resources will be created by the CloudFormation stack in full deployment mode. 
- A new VPC (`110.192.0.0/16` by default)
- An EKS Cluster 
- An additional /16 CIDR block (`10.1.0.0/16` by default)
- A private subnet (`10.1.0.0/16` by default) to host the HyperPod compute node ENIs in the Availability Zone of your choice based on where you have capacity (specified using the `AvailabilityZoneId` parameter). 
- A security group for use with EKS, HyperPod, and FSx for Lustre to allow communication between the respective ENIs. 
- An S3 bucket for storing lifecycle scripts 
- A SageMaker execution role required for HyperPod and EKS integrated operations. 
:::

::::
::::tab{id="Integrative Deployment" label="Integrative Deployment"}
Use integrative deployment mode if you want to use your own VPC and EKS cluster, but need to create an additional /16 CIDR block, a private subnet, and a security group for the workshop. 
:::expand{header="Parameter Requirements" defaultExpanded=false}
Set the following parameters accordingly if you want to use integrative deployment mode. 
- Set `CreateEKSCluster` to `false`
- Set `CreateSubnet` to `true`
- Provide the `AvailabilityZoneId` (`usw2-az2` for the `us-west-2` region by default). Update this parameter based on your region and the Availability Zone that you have accelerated compute capacity in. An additional CIDR block will be added to your VPC with a /16 private subnet in the specified Availability Zone. This private subnet will be used to deploy the HyperPod cross-account elastic network intefaces (ENIs), which give you access to the HyperPod capacity you deploy.
- Provide the `NatGatewayId`. This parameter is used to create a route to the internet from the newly create private subnet
- Provide the `SecurityGroupId`. This parameter is used to identify the security group associated with your EKS cluster so that a newly created security group can be configured with rules to allow communication with the EKS control plane. 
- Provide the `VpcId`. This paremeter is used to attach an additional /16 CIDR block (10.1.0.0/16 by default) to your existing VPC. 
- Provide the `PrivateSubnet1CIDR`. This parameter is used to specify the desired range to use for the additional /16 CIDR block and private subnet (10.1.0.0/16 by default). Please configure a CIDR range that does not overlap with your existing VPC. 

:::

:::expand{header="Ignored Parameters" defaultExpanded=false}
These parameters are ignored because you are using a preprovisioned VPC and EKS Cluster. 
- `EKSPrivateSubnet1CIDR`
- `EKSPrivateSubnet2CIDR`
- `EKSPrivateSubnet3CIDR`
- `KubernetesVersion`
- `PublicSubnet1CIDR`
- `PublicSubnet2CIDR`
- `PublicSubnet3CIDR`
- `VpcCIDR`

:::

:::expand{header="Resources Created" defaultExpanded=false}
The following resources will be created by the CloudFormation stack in integrative deployment mode. 
- An additional /16 CIDR block (`10.1.0.0/16` by default)
- A private subnet (`10.1.0.0/16` by default) to host the HyperPod compute node ENIs in the Availability Zone of your choice based on where you have capacity (specified using the `AvailabilityZoneId` parameter). 
- A security group for use with EKS, HyperPod, and FSx for Lustre to allow communication between the respective ENIs. 
- An S3 bucket for storing lifecycle scripts 
- A SageMaker execution role required for HyperPod and EKS integrated operations. 
:::

::::
::::tab{id="Minimal Deployment" label="Minimal Deployment"}
Use minimal deployment mode if you want to use your own VPC and EKS cluster, and you want to manage the subnet and security group configurations in your environment by yourself. 
:::expand{header="Parameter Requirements" defaultExpanded=false}
Set the following parameters accordingly if you want to use minimal deployment mode. 
- Set `CreateEKSCluster` to `false`
- Set `CreateSubnet` to `false`
:::

:::expand{header="Ignored Parameters" defaultExpanded=false}
All other parameters are ignored with a minimal deployment
:::

:::expand{header="Resources Created" defaultExpanded=false}
The following resources will be created by the CloudFormation stack in minimal deployment mode. 
- An S3 bucket for storing lifecycle scripts 
- A SageMaker execution role required for HyperPod and EKS integrated operations. 
:::

::::
:::::

::::alert{header="Note:"}

The IAM principal (user or role) you use must have permissions to create the CloudFormation stack. In addition to permissions to perform the CloudFormation stack operations, the IAM principal also needs permissions to provision the resources defined in the CloudFormation template. 

:::expand{header="Add Required Permissions" defaultExpanded=false}
Follow this procedure if you don't already have the minimum required permissions to deploy the CloudFormation stack. 

Create the IAM policy:
```json 
cat > cfn-stack-policy.json << EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:CreateStack",
				"ec2:AuthorizeSecurityGroupEgress",
				"ec2:AuthorizeSecurityGroupIngress",
				"ec2:CreateNatGateway",
				"ec2:CreateTags",
				"ec2:CreateVpc",
				"ec2:CreateRouteTable",
				"ec2:AttachInternetGateway",
				"ec2:AssociateVpcCidrBlock",
				"ec2:AllocateAddress",
				"ec2:AssociateRouteTable",
				"ec2:CreateFlowLogs",
				"ec2:CreateSecurityGroup",
				"ec2:CreateInternetGateway",
                "ec2:CreateSubnet",
				"eks:CreateAddon",
				"eks:CreateAccessEntry",
				"eks:CreateCluster",
                "iam:CreateRole",
				"s3:CreateBucket"
            ],
            "Resource": "*"
        }
    ]
}
EOL
```
```bash 
aws iam create-policy \
    --policy-name cfn-stack-policy \
    --policy-document file://cfn-stack-policy.json \
    --region $AWS_REGION

```
Attach the policy to the IAM principal you plan to use to deploy the CloudFormation stack:
```bash 
# for an IAM role 
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/cfn-stack-policy \
    --role-name <YOUR-ROLE-HERE> \
    --region $AWS_REGION
```
```bash 
# for an IAM user
aws iam attach-user-policy \
    --policy-arn arn:aws:iam::aws:policy/cfn-stack-policy \
    --user-name <YOUR-USER-HERE> \
    --region $AWS_REGION
```

:::

By default, the Amazon EKS service will automatically create an [AccessEntry](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-eks-accessentry.html) with [AmazonEKSClusterAdminPolicy](https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html#access-policy-permissions) permissions for the IAM principal that you use to deploy the CloudFormation stack, which includes an EKS cluster resource. You can create additional access entries later through the EKS management console or the AWS CLI. For more information, see the documentation on [managing access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html). 

:::expand{header="AWS CLI Examples" defaultExpanded=false}
The [create-access-entry](https://docs.aws.amazon.com/cli/latest/reference/eks/create-access-entry.html) command creates an access entry that gives an IAM principal access your EKS cluster: 
```bash 
aws eks create-access-entry \
 --cluster-name $EKS_CLUSTER_NAME \
 --principal-arn arn:aws:iam::xxxxxxxxxxxx:role/ExampleRole \
 --type STANDARD \
 --region $AWS_REGION
```
The [associate-access-policy](https://docs.aws.amazon.com/cli/latest/reference/eks/associate-access-policy.html) command associates an access policy and its scope to an access entry: 
```bash 
aws eks associate-access-policy \
 --cluster-name $EKS_CLUSTER_NAME \
 --principal-arn arn:aws:iam::xxxxxxxxxxxx:role/ExampleRole \
 --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
 --access-scope type=cluster \
 --region $AWS_REGION
```
If you are planning to use a Cloud9 environment, specify the ARN of a IAM Role as the `--principal-arn`, which can then be attached to the Cloud9 EC2 instance in a later step. 
:::
If you plan to deploy the same stack multiple times in the same AWS Region, be sure to adjust the stack name and `ResourceNamePrefix` parameter (`hyperpod-eks` by default) in order to avoid resource naming conflicts.

::::

:button[Deploy SageMaker HyperPod on EKS Stack]{variant="primary" href="https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0.s3.us-west-2.amazonaws.com/2433d39e-ccfe-4c00-9d3d-9917b729258e/hyperpod-eks-full-stack.yaml&stackName=hyperpod-eks-full-stack" external="true"}

> Note - It takes about 10 mins to deploy the stack. 

---

### Setup Your Environment

Next make sure you have a linux based development environment. If you need a linux based development environment, see section on connecting to [AWS CloudShell](/00-setup/01-cloudshell.md).

Ensure that you have the following tools installed: 

::::expand{header="Install the AWS CLI" defaultExpanded=false}

:::alert{header="Note:"}
The AWS CLI comes pre-installed on [AWS CloudShell](/00-setup/01-cloudshell.md). 
:::

Install the latest version of the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), you'll need version `2.14.3` as a minimum to run the SageMaker HyperPod commands:

::::tabs{variant="container" activeTabId="Linux_x86_64"}

:::tab{id="Linux_x86_64" label="Linux (x86_64)"}
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update
```
:::

:::tab{id="Linux_arm64" label="Linux (arm64)"}
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```
:::

:::tab{id="macOS" label="macOS (x86_64 and arm64)"}
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```
:::
::::

::::expand{header="Install kubectl" defaultExpanded=false}
:::alert{header="Note:"}
kubectl comes pre-installed on [AWS CloudShell](/00-setup/01-cloudshell.md). 
:::
You will use kubectl throughout the workshop to interact with the EKS cluster Kubernetes API server. The following commands correspond with Linux installations. See the [Kubernetes documentation](https://kubernetes.io/docs/tasks/tools/) for steps on how to install kubectl on [macOS](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/) or [Windows](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/). 

```bash
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.29.3/2024-04-19/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
```

::::

::::expand{header="Install eksctl" defaultExpanded=false}
You will use eksctl to [create an IAM OIDC provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) for your EKS cluster and install the [Amazon FSx for Lustre CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html) in a later step. The following commands correspond with Unix installations. See the [eksctl documentation](https://eksctl.io/installation/) for alternative instilation options. 

```bash
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

# (Optional) Verify checksum
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check

tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz

sudo mv /tmp/eksctl /usr/local/bin

```
::::

::::expand{header="Install Helm" defaultExpanded=false}
[Helm](https://helm.sh/) is a package manager for Kubernetes that will be used to istall various dependancies using [Charts](https://helm.sh/docs/topics/charts/), which bundle together all the resources needed to deploy an application to a Kubernetes cluster. 

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```
::::

---

### Review Your IAM Permissions

The following procedure shows you how to attach an IAM policy with the required permissions to manage HyperPod on EKS to an IAM principal. Make sure that you add all of the required permissions to the IAM role or user for cluster administration. 

Get the ARN of the Execution role that was created in the above CloudFormation stack. You'll need to pass this IAM role to the HyperPod service in a later step: 
```bash 
STACK_ID=hyperpod-eks-full-stack

EXECUTION_ROLE=`aws cloudformation describe-stacks \
    --stack-name $STACK_ID \
    --query 'Stacks[0].Outputs[?OutputKey==\`AmazonSagemakerClusterExecutionRoleArn\`].OutputValue' \
    --region $AWS_REGION \
    --output text`
```
Create the IAM policy:
```json
cat > hyperpod-eks-policy.json << EOL
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "${EXECUTION_ROLE}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sagemaker:CreateCluster",
                "sagemaker:DeleteCluster",
                "sagemaker:DescribeCluster",
                "sagemaker:DescribeCluterNode",
                "sagemaker:ListClusterNodes",
                "sagemaker:ListClusters",
                "sagemaker:UpdateCluster",
                "sagemaker:UpdateClusterSoftware",
                "sagemaker:DeleteClusterNodes",
                "eks:DescribeCluster",
                "eks:CreateAccessEntry",
                "eks:DescribeAccessEntry",
                "eks:DeleteAccessEntry",
                "eks:AssociateAccessPolicy",
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*"
        }
    ]
}
EOL
```
```bash 
aws iam create-policy \
    --policy-name hyperpod-eks-policy \
    --policy-document file://hyperpod-eks-policy.json \
    --region $AWS_REGION
```

Attach the policy to the IAM principal you plan to use for this workshop: 

For an IAM Role:

```bash 
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

aws iam attach-role-policy \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/hyperpod-eks-policy \
    --role-name <YOUR-ROLE-HERE> \
    --region $AWS_REGION
```
For an IAM User:

```bash 
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

aws iam attach-user-policy \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/hyperpod-eks-policy \
    --user-name <YOUR-USER-HERE> \
    --region $AWS_REGION
```