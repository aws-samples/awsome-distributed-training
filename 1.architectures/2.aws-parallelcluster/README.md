# AWS ParallelCluster Distributed Training Reference Architecture

This README provides a "vanilla" reference architectures and deployment guide for setting up distributed training clusters using [AWS ParallelCluster](https://github.com/aws/aws-parallelcluster). These architectures are optimized for machine learning workloads and include configurations for high-performance computing instances (P and Trn EC2 families) with shared filesystems (FSx for Lustre and OpenZFS). Key features are including:

- Pre-configured for distributed training workloads
- Integrated with FSx for Lustre for high-performance storage and OpenZFS for home directory
- Support for On-Demand Capacity Reservations (ODCR) and Capacity Blocks (CB)
- Optimized networking with Elastic Fabric Adapter (EFA)

![AWS ParallelCluster diagram](../../0.docs/core-infra-architecture.png)

The infrastructure consists of the two layers:

### `parallelcluster-rerequisites`

The core infrastructure for your training cluster that has 3 components.

* An [Amazon Virtual Private Cloud (VPC)](https://aws.amazon.com/vpc/) with one public and one private subnet.
* An [Amazon FSx for Lustre](https://aws.amazon.com/fsx/lustre/) high performance file system to store training and checkpointing data.
* An [Amazon FSx for OpenZFS](https://aws.amazon.com/fsx/openzfs/) file system to store home directories data.


### `parallelcluster`

The AWS ParallelCluster is an open-source cluster management tool that makes it easy to deploy and manage High Performance Computing (HPC) clusters on AWS. It automates the creation of the infrastructure needed for HPC workloads, including:

- **Head-node**: A login and controller node that users connect to for submitting jobs and managing the cluster. This node runs the scheduler (Slurm) and other management services.
- **Compute-nodes**: Worker nodes that execute the actual computational workloads. These are dynamically provisioned based on job requirements and can scale up or down automatically.

The architecture follows a traditional HPC design pattern where users interact with the head node to submit jobs, and the scheduler distributes those jobs to the compute nodes. For ML workloads, the compute nodes are typically equipped with GPUs (like P4d, P5, etc.) or AWS Trainium accelerators.



## Prerequisites

First, clone the repository and move to this directory:

```bash
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd awsome-distributed-training/1.architectures/2.aws-parallelcluster
```

Then create a directory under home directory to store cluster config files:

```bash
# For example
export AWS_REGION=ap-northeast-1 
export CLUSTER_NAME=ml-cluster
export PCLUSTER_VERSION=3.13.0
export CONFIG_DIR="~/${AWS_REGION}_${CLUSTER_NAME}_${PCLUSTER_VERSION}"

mkdir -p ${CONFIG_DIR}
```


The rest of this section describes following required/optional components.

- AWS Account with administrator permissions
- AWS ParallelCluster CLI for cluster deployment and management
- Reserved accelerated instance capacity (P/Trn instances) through  On-Demand Capacity Reservation (ODCR) or EC2 Capacity Blocks (CB) for ML
- EC2 Key Pair for SSH access
- (Optional) S3 bucket for data persistence
- (Optional) Custom AMI for pre-installed dependencies

#### AWS Account with appropriate permissions to create and manage resources

To deploy AWS ParallelCluster, you need to be an Administrator user of the AWS account. See [this issue](https://github.com/aws/aws-parallelcluster/issues/2060) for the related discussion.  You need to use the IAM user to create clusters using AWS ParallelCluster CLI from local console, for that you need to 

#### AWS ParallelCluster CLI for cluster deployment and management

> explain AWS parallelcluster CLI with the corresponding link on AWS documentation.
You need Python 3.7 or later installed on your local environment:


```bash
export VIRTUAL_ENV_PATH=~/pcluster_env # change the path to your liking
```

```bash
# Update pip and the virtual env module
python3 -m pip install --upgrade pip
python3 -m pip install --user --upgrade virtualenv
python3 -m virtualenv ${VIRTUAL_ENV_PATH} # create the virtual env
source ${VIRTUAL_ENV_PATH}/bin/activate # activate the environment
pip3 install awscli # install the AWS CLI
pip3 install aws-parallelcluster==3.13.0 # then AWS ParallelCluster
```

You can follow the [documentation](https://docs.aws.amazon.com/parallelcluster/latest/ug/commands-v3.html) to review the list of all AWS ParallelCluster commands.

#### Reserved accelerated instance capacity (P/Trn instances) through  On-Demand Capacity Reservation (ODCR) or EC2 Capacity Blocks (CB) for ML

Distributed training usually requires P or Trn instances, both of which are high demand and hard to launch from ondemand pool. It is strongly recommended to reserve the capacity using On-Demand Capacity Reservation (ODCR) or EC2 Capacity Blocks (CB) for ML. 

On-Demand Capacity Reservation (ODCR) is a tool for reserving capacity without having to launch and run the EC2 instances. The CRs for P or Trn instances are typically *created by AWS*, not by users, which affects how to correctly configure the cluster networking (section [5.3](#53-network-efa-elastic-fabric-adapter)).

[Amazon EC2 Capacity Blocks for ML](https://aws.amazon.com/ec2/capacity-blocks/) is another way to reserve compute capacity for your ML workloads. Unlike ODCR, Capacity Blocks allows you to reserve capacity for a specific time window (from 1 to 14 days) with a specific start time. This is particularly useful for planned ML training jobs that require high-performance P/Trn instances. Pricing varies by region and instance type. You can find the complete pricing information and available instance types in each region on the [Amazon EC2 Capacity Blocks for ML pricing page](https://aws.amazon.com/ec2/capacityblocks/pricing/).

__You need following information before proceed__:

* An ODCR (usually P or Trn instances) on the account. You can check:
  * AZ for the capacity `AZ`.
  * Number of instances in the CR `ODCR_ID`.

Click on this link to deploy the S3 bucket:

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateUrl=https://awsome-distributed-training.s3.amazonaws.com/templates/0.private-bucket.yaml&stackName=cluster-data-bucket)

#### EC2 Key Pair for SSH access

The EC2 key pair enables your to connect to your cluster on the head-node through ssh or [AWS Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html). We will cover for SSH here.

You can list your public keys on your [AWS Console](https://console.aws.amazon.com/ec2/home?#KeyPairs:) and you may also check your SSH directory for the private keys (`~/.ssh` if using Linux or OSX).


First export the name of the key pair you have or will create:

```bash
export KEYPAIR_NAME=${KEYPAIR_NAME} # use your own keypair here
```

If you do not have a keypair that you can use then we will create one with the command below (see [this documentation](https://docs.aws.amazon.com/parallelcluster/latest/ug/set-up-keypair.html)).

```bash
cd ~/.ssh
# Create the key pair using the AWS CLI and retrieve the private part (.pem file)
aws ec2 create-key-pair --key-name ${KEYPAIR_NAME} \
                        --query KeyMaterial \
                        --key-type ed25519 \
                        --region $AWS_REGION \
                        --output text > ${KEYPAIR_NAME}.pem

# The above command will also generate a private key in the current directory.
# We must change the access rights to the current user only, otherwise the ssh
# client refuses to use this private key to open an ssh connection.
sudo chmod 600 ${KEYPAIR_NAME}.pem
```

#### (Optional) S3 bucket for data persistence




## Cluster deployment

To create cluster, please refer to [deployment-guides](./deployment-guides). Under the directory we have instructions for following patterns of cluster deployments.


### Deploy parallelcluster-prerequisites

In this section, you deploy a custom [_Amazon Virtual Private Cloud_](https://aws.amazon.com/vpc/) (Amazon VPC) network and security groups, as well as supporting services such as FSx for Lustre using the CloudFormation template called `parallelcluster-prerequisites.yaml`. This template is region agnostic and enables you to create a VPC with the required network architecture to run your workloads.

Please follow the steps below to deploy your resources:

1. Click on this link to deploy to CloudFormation:

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateUrl=https://awsome-distributed-training.s3.amazonaws.com/templates/parallelcluster-prerequisites.yaml&stackName=parallelcluster-prerequisites)

The cloudformation stack uses FSx for Lustre Persistent_2 deployment type. If you wish to use Persistent_1 deployment type please use the link below:

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateUrl=https://awsome-distributed-training.s3.amazonaws.com/templates/parallelcluster-prerequisites-p1.yaml&stackName=parallelcluster-prerequisites)

They need to open the link and specify the region and availability zone where they have their compute resources. Fill out "Availability Zone configuration for the subnets", and create the stack. 

![parallelcluster-prerequisites-cfn](../../0.docs/parallelcluster-prerequisites-cfn.png)

#### (Optional) Associate Lustre storage with S3 bucket with data-repository-association (DRA)

If you have deployed your S3 data repository in the previous step In this step, you will create a [Data Repository Association (DRA)](https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html) between the S3 bucket and FSx Lustre Filesystem.

```bash
export AWS_REGION=ap-northeast-1
export STACK_ID_VPC=parallelcluster-prerequisites 
export FSX_ID=`aws cloudformation describe-stacks \
    --stack-name ${STACK_ID_VPC} \
    --query 'Stacks[0].Outputs[?OutputKey==\`FSxLustreFilesystemId\`].OutputValue' \
    --region ${AWS_REGION} \
    --output text`
```

Note: `DATA_BUCKET_NAME`  is the bucket created in [Step0: Check resource info](https://quip-amazon.com/wDrEAxaBEI3A#temp:C:fdV996b34e8ad4e4dc3ac2ef128b). 
Create DRA as follows:

```bash
aws fsx create-data-repository-association \
    --file-system-id ${FSX_ID} \
    --file-system-path "/data" \
    --data-repository-path s3://${DATA_BUCKET_NAME} \
    --s3 AutoImportPolicy='{Events=[NEW,CHANGED,DELETED]},AutoExportPolicy={Events=[NEW,CHANGED,DELETED]}' \
    --batch-import-meta-data-on-create \
    --region ${AWS_REGION}
```

You shall see output like below:

```
{
    "Association": {
        "AssociationId": "dra-0295ef8c2a0e78886",
        "ResourceARN": "arn:aws:fsx:ap-northeast-1:483026362307:association/fs-0160ebe1881498442/dra-0295ef8c2a0e78886",
        "FileSystemId": "fs-0160ebe1881498442",
        "Lifecycle": "CREATING",
        "FileSystemPath": "/data",
        "DataRepositoryPath": "s3://genica-cluster-data-483026362307",
        "BatchImportMetaDataOnCreate": true,
        "ImportedFileChunkSize": 1024,
        "S3": {
            "AutoImportPolicy": {
                "Events": [
                    "NEW",
                    "CHANGED",
                    "DELETED"
                ]
            },
            "AutoExportPolicy": {
                "Events": [
                    "NEW",
                    "CHANGED",
                    "DELETED"
                ]
            }
        },
        "Tags": [],
        "CreationTime": "2024-10-22T09:06:57.151000+09:00"
    }
}
```

You can query the status of the DRA creation as below:

```bash
aws fsx describe-data-repository-associations \
    --filters "Name=file-system-id,Values=${FSX_ID}" --query "Associations[0].Lifecycle" --output text
    --region ${AWS_REGION}
```

Wait until the output becomes `AVAILABLE` . You also can check the status of DRA on AWS console:

## Deploy ParallelCluster

This section goes through all the steps necessary to deploy the architecture discussed in the previous section. *Make sure to check [prerequisites](https://github.com/aws-samples/awsome-distributed-training/tree/geniac/1.architectures/2.aws-parallelcluster#2-pre-requisites) before proceed.**


In this example, are going to deploy PCluster with P5 instances.


```bash
source env_vars
export KEY_PAIR_NAME=<your keypair name without .pem> # You need to create a keypair prior to this ste
export CAPACITY_RESERVATION_ID=cr-<YOUR CRID> # Please check EC2 console
export INSTANCE=p5.48xlarge
export NUM_INSTANCES=4
bash create_config.sh
```

This command will create a file called `env_vars`.

Then create cluster with the following command:

```bash
source env_vars
cat templates/cluster-vanilla.yaml | envsubst > configs/cluster-vanilla.yaml
```
> [!ALERT]

> By default, `PlacementGroup` is set to `False` in this config. In most of the cases, capacity is provided through AWS-provided CR or CB.  When using the AWS-assisted targeted ODCR or CB, you're strongly recommended to disable the `PlacementGroup` setting for AWS Parallel Cluster, otherwise this placement group option creates a specific placement group that may conflict with the placement group assigned in your ODCR/CB, causing instance launch failures *Insufficient Capacity Error* (*ICE*).


> [!TIP]  
> If you are working on CloudShell, your environment might not have `envsubst`. In that case, please install the command with `sudo yum install gettext`

```bash
pcluster create-cluster -n ml-cluster -c configs/cluster-vanilla.yaml -r ${AWS_REGION} --rollback-on-failure false
```

You will see the output like follows:

```
{
  "cluster": {
    "clusterName": "ml-cluster",
    "cloudformationStackStatus": "CREATE_IN_PROGRESS",
    "cloudformationStackArn": "arn:aws:cloudformation:ap-northeast-1:483026362307:stack/ml-cluster-p5/f0f12000-9012-11ef-8989-060ea463320f",
    "region": "ap-northeast-1",
    "version": "3.11.1",
    "clusterStatus": "CREATE_IN_PROGRESS",
    "scheduler": {
      "type": "slurm"
    }
  },
  "validationMessages": [
    {
      "level": "WARNING",
      "type": "DetailedMonitoringValidator",
      "message": "Detailed Monitoring is enabled for EC2 instances in your compute fleet. The Amazon EC2 console will display monitoring graphs with a 1-minute period for these instances. Note that this will increase the cost. If you want to avoid this and use basic monitoring instead, please set `Monitoring / DetailedMonitoring` to false."
    }
  ]
}
```

Then you can check progress of cluster creation on Cloudformation console
Alternatively, you can check the progress through `pcluster` command as follows:

```bash
pcluster list-clusters -r ${AWS_REGION}
```

## Connect to the Cluster

Once the cluster goes into **CREATE COMPLETE**, we can connect to the head node in one of two ways, either through the SSM or SSH.

**SSM Session Manager** is ideal for quick terminal access to the head node, it doesn't require any ports to be open on the head node, however it does require you to authenticate with the AWS account the instance it running in.

**SSH** can be used to connect to the cluster from a standard SSH client. This can be configured to use your own key via adding the public key or a new key can be provisioned.

### SSM Connect 
![ssm connect](../../../0.docs/ssm-connect.png)
You'll need to be authenticated to the AWS account that instance is running in and have permission to launch a SSM session . Once you're connected you'll have access to a terminal on the head node:

Now change to `ubuntu` user:

```bash
sudo su - ubuntu
```

![ssm user connect](../../../0.docs/ssm-connect-user.png)

### SSH access

Also, You can access to the headnode via SSH (if you set up keypair). You can retrieve IP address of the head node with the following command:

```bash
pcluster ssh --region ap-northeast-1 --cluster-name ml-cluster --identity_file ~/.ssh/ap-northeast-1.pem  --dryrun true 
```

It will show output like follows:

```bash
{
  "command": "ssh ubuntu@18.183.235.248 --identity_file /Users/mlkeita/.ssh/ap-northeast-1.pem"
}
```




#### Specification of reserved capacity in ParallelCluster config file (TODO: Move)
AWS ParallelCluster supports specifying the [CapacityReservationId](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html#yaml-Scheduling-SlurmQueues-CapacityReservationTarget) in the cluster's config file. If using a capacity reservation put the ID i.e. `cr-12356790abcd` in your config file by substituting the variable `PLACEHOLDER_CAPACITY_RESERVATION_ID`. It should look like the following:

  ```yaml
  CapacityReservationTarget:
      CapacityReservationId: cr-12356790abcd
  ```

If you have multiple ODCR's you can group them together into a [*Capacity Reservation Group*](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-cr-group.html), this allows you to launch instances from multiple ODCR's as part of the **same queue** of the cluster.

1. First create a group, this will return a group arn like: `arn:aws:resource-groups:us-east-2:123456789012:group/MyCRGroup`. Save that for later.

    ```bash
    aws resource-groups create-group --name MyCRGroup --configuration '{"Type":"AWS::EC2::CapacityReservationPool"}' '{"Type":"AWS::ResourceGroups::Generic", "Parameters": [{"Name": "allowed-resource-types", "Values": ["AWS::EC2::CapacityReservation"]}]}'
    ```

2. Next add your capacity reservations to that group:

    ```bash
    aws resource-groups group-resources --group MyCRGroup --resource-arns arn:aws:ec2:sa-east-1:123456789012:capacity-reservation/cr-1234567890abcdef1 arn:aws:ec2:sa-east-1:123456789012:capacity-reservation/cr-54321abcdef567890
    ```

3. Then add the group to your cluster's config like so:

    ```yaml
        CapacityReservationTarget:
            CapacityReservationResourceGroupArn: arn:aws:resource-groups:us-east-2:123456789012:group/MyCRGroup
    ```
## 8. References

* [AWS ParallelCluster wiki](https://github.com/aws/aws-parallelcluster/wiki)

