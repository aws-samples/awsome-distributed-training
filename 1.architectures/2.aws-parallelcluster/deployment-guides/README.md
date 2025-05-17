Here, we provide detailed instruction for the cluster deployment in various different setup scenario

### 3.3. Deploy parallelcluster-prerequisites

In this section, you deploy a custom [_Amazon Virtual Private Cloud_](https://aws.amazon.com/vpc/) (Amazon VPC) network and security groups, as well as supporting services such as FSx for Lustre using the CloudFormation template called `parallelcluster-prerequisites.yaml`. This template is region agnostic and enables you to create a VPC with the required network architecture to run your workloads.

Please follow the steps below to deploy your resources:

1. Click on this link to deploy to CloudFormation:

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateUrl=https://awsome-distributed-training.s3.amazonaws.com/templates/parallelcluster-prerequisites.yaml&stackName=parallelcluster-prerequisites)

The cloudformation stack uses FSx for Lustre Persistent_2 deployment type. If you wish to use Persistent_1 deployment type please use the link below:

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/quickcreate?templateUrl=https://awsome-distributed-training.s3.amazonaws.com/templates/parallelcluster-prerequisites-p1.yaml&stackName=parallelcluster-prerequisites)

They need to open the link and specify the region and availability zone where they have their compute resources. Fill out "Availability Zone configuration for the subnets", and create the stack. 

![parallelcluster-prerequisites-cfn](../../0.docs/parallelcluster-prerequisites-cfn.png)

### 3.4. Associate Lustre storage with S3 bucket with data-repository-association (DRA)

In this step, you will create a [Data Repository Association (DRA)](https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html) between the S3 bucket and FSx Lustre Filesystem.

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

## 5. Architecture Overview

![AWS ParallelCluster diagram](../../0.docs/parallelcluster-arch-diagram.png)

### 5.1. Compute

Compute is represented through the following:

- **Head-node**: login and controller node that users will use to submit jobs. 
- **Compute-gpu**: is the queue (or partition) to run your ML training jobs. 

### 5.2. On-Demand Capacity Reservation (ODCR)

On-Demand Capacity Reservation (ODCR) is a tool for reserving capacity without having to launch and run the EC2 instances. ODCR is practically **the only way** to launch capacity-constrained instances like `p5.48xlarge`, `p5e.48xlarge`, or `p5en.48xlarge`. In addition, the CRs for these instance types are typically *created by AWS*, not by users, which affects how to correctly configure the cluster networking (section [5.3](#53-network-efa-elastic-fabric-adapter)).

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
### 5.3. Amazon EC2 Capacity Blocks (CB) for ML
[Amazon EC2 Capacity Blocks for ML](https://aws.amazon.com/ec2/capacity-blocks/) is another way to reserve compute capacity for your ML workloads. Unlike ODCR, Capacity Blocks allows you to reserve capacity for a specific time window (from 1 to 14 days) with a specific start time. This is particularly useful for planned ML training jobs that require high-performance instances like P4d, P4de, P5, P5e and P5en. Pricing varies by region and instance type. You can find the complete pricing information and available instance types in each region on the [Amazon EC2 Capacity Blocks for ML pricing page](https://aws.amazon.com/ec2/capacityblocks/pricing/).

To get Capacity Blocks:

1. Contact your AWS account team to request access to Capacity Blocks for ML
2. Once approved, you can purchase blocks through the [AWS Management Console](https://console.aws.amazon.com/ec2/home#CapacityReservations) or AWS CLI
3. After purchase, you'll receive a Capacity Block ID (e.g., `cb-12345678901234567`)

To configure AWS ParallelCluster to use your Capacity Block, add the following configuration to your compute resources in the cluster config file:

```yaml
Scheduling:
  SlurmQueues:
    - Name: compute-gpu
      CapacityType: CAPACITY_BLOCK
      ComputeResources:
        - Name: distributed-ml
          InstanceType: p5.48xlarge  # Must match the instance type in your CB
          MinCount: 1  # Must equal MaxCount
          MaxCount: 1  # Must equal MinCount
          CapacityReservationTarget:
            CapacityReservationId: cb-12345678901234567  # Your CB ID
```

Important notes about using Capacity Blocks with AWS ParallelCluster:

1. The `CapacityType` must be set to `CAPACITY_BLOCK` for the queue where you want to use the CB
2. The `InstanceType` must match the instance type specified in your CB
3. `MinCount` must equal `MaxCount` and be greater than 0, as all instances in the CB are managed as static nodes
4. The cluster will be created even if the CB is not yet active - instances will launch automatically when the CB becomes active
5. When the CB end time is reached, nodes will be moved back to a reservation/maintenance state
6. You'll need to resubmit/requeue jobs to a new queue/compute-resource when the CB is no longer active

### 5.4. PlacementGroup setting for your reservation

Applications will make use of [Elastic Fabric Adapter (EFA)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html) for enhanced networking during distributed training. To achieve optimal network latency instances should be placed in a placement groups using either the `PlacementGroup` flag or by specifying a targeted [On-Demand Capacity reservation (ODCR)](#52-on-demand-capacity-reservation-odcr).

It is important to note the targeted ODCR for GPU/Trn instances are typically not created by users. Instead, AWS will create the CR with placement group assigned, then deliver (i.e., share) the CR to users. Users must accept the CR (e.g., via their AWS console) before they can use it to launch the GPU/Trn instances. The same is true for CB.

__When using the AWS-assisted targeted ODCR or CB, you have to disable the `PlacementGroup` setting for AWS Parallel Cluster__, otherwise this placement group option creates a specific placement group that may conflict with the placement group assigned in your ODCR, causing instance launch failures *Insufficient Capacity Error* (*ICE*).

```yaml
PlacementGroup:
  Enabled: false
```

### 5.5. Storage

Storage comes in 3 flavors:

- **Local**: head and compute nodes have 200GiB of EBS volume mounted on `/`. In addition, the headnode has an EBS volume of `200GiB` mounted on `/apps` The compute nodes have NVMe drives striped in RAID0 and mounted as `/local_scratch`.
- **File network storage**: The head-node shares `/home` and `/apps` to the whole cluster through NFS. These directories are automatically mounted on every instance in the cluster and accessible through the same path. `/home` is a regular home directory, `/apps` is a shared directory where applications or shared files can be stored. Please note that none should be used for data intensive tasks.
- **High performance filesystem**: An [FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html) filesystem can be accessed from every cluster node on `/fsx`. This is where users would store their datasets. This file system has been sized to 4.8TiB and provides 1.2GB/s of aggregated throughput. You can modify its size and the throughput per TB provisioned in the config file following the service [documentation](https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html).

### 5.6. Installing applications & libraries

You can chose to use a custom image or post-install scripts to install your application stack.

- **Custom images**: the image needs to be pre-built before creating a cluster. They are preferred for drivers, kernel modules or libraries regularly used and seeing little to no updates. This option is preferred to ensure repeatability. You can use custom images as follows:

    ```yaml
    Image:
      Os: ubuntu2022 #system type
      CustomAmi: PLACEHOLDER_CUSTOM_AMI_ID #replace by custom imageAMI ID
    ```

    If not using a custom image, remove the `CustomAmi` field.

- **Post-install scripts**: these scripts will be executed at instance boot (head+compute). This option is recommended for quick testing and will increase instance boot time. You can run post-install scripts through `CustomActions` for the head node and the compute nodes. The `distributed-training-p4de_postinstall_scripts.yaml` uses the post-install scripts from this [repo](https://github.com/aws-samples/aws-parallelcluster-post-install-scripts) to enable the container support.


* [Vanilla cluster deployment](vanilla-pcluster.md)
* [Pcluster with observability stack deployment](pcluster-observability.md)