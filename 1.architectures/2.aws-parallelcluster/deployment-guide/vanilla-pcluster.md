

### 3.1. Cluster templates

Each reference architectures provides an example of cluster configuration (`.yaml`) for different use cases. The architectures most commonly used are:

### 3.2. What to replace in the templates

The `.yaml` templates contain placeholder variables that you need to replace before use.

- `CUSTOM_AMI_ID`: if using a custom AMI then replace with the custom AMI ID (`ami-12356790abcd`).
- `PUBLIC_SUBNET_ID`: change to the id of a public subnet to host the head-node (`subnet-12356790abcd`).
- `PRIVATE_SUBNET_ID`: change to the id of a public subnet to host the compute nodes (`subnet-12356790abcd`).
- `PLACEHOLDER_SSH_KEY`: ID of the SSH key you'd like to use to connect to the head-node, use the name of the key. You can also use AWS Systems Manager Session Manager (SSM).
- `CAPACITY_RESERVATION_ID`: if using a capacity reservation put the ID here (`cr-12356790abcd`).

In some of the templates you may need to update these placeholders:

- `PLACEHOLDER_MIN_INSTANCES`: the minimum number of instances you want in your cluster at any point in time.
- `PLACEHOLDER_MAX_INSTANCES`: the maximum number of instances you anticipate to scale to.

If `MIN` = `MAX` then you keep a fixed amount of instances at any point in time. If `MIN` < `MAX` then the cluster will keep a `MIN` number of instances and scale up to `MAX` if capacity beyond `MIN` is required to run jobs. Update this values by updating your cluster ([documentation](https://docs.aws.amazon.com/parallelcluster/latest/ug/using-pcluster-update-cluster-v3.html))

# [Lead SA Runbook] Vanilla PCluster Deployment

Lead SA will have an onboarding call with customers and assist them to create AWS ParallelCluster using the procured P5 capacity. This runbook is for the Lead SA and aiming to provide step-by-step guide on vanilla [AWS ParallelCluster (PCluster)](https://github.com/aws/aws-parallelcluster) deployment which supports following features:

|Feature	|Enabled	|
|---	|---	|
|Multi-user support	|FALSE	|
|Accounting	|FALSE	|
|Observability	|FALSE	|

- [ ] add script to deploy cluster
- [ ] cut branch on awsome-distributed-training and export the contents

## Introduction

This setup involves two main infrastructure components, `parallelcluster-prerequisites`  (the base infrastructure stack including VPC, FSx for Lustre, FSx for Open ZFS) and a PCluster itself. If you need guidance on additional components (such as multi-user support, accounting, and observability) please refer to the other Runbooks. You can find links to the document in [References section](https://quip-amazon.com/wDrEAxaBEI3A/Runbook-Vanilla-PCluster-Deployment#temp:C:fdV09aac85c19e04a3aa33506baf).
[Image: image.png]
Customer may create the `parallelcluster-prerequisites` stack prior to the onboarding call on Oct. 25th if they want to, however...
 🚨 Please deploy FSx for Luster with minimal capacity configuration (for now) 🚨 
Due to the limited FSxL capacity, deployment would likely fail if Cx increases `Capacity` or `PerUnitStorageThroughput` when they deploy the Cloudformation stack. Please make sure that Cx first deploys the stack “as is” (`Capacity`: 1.2 TiB, `PerUnitStorageThroughput` : 250 MB/s/TiB) and then try to scale up FSxL filesystem after Oct. 25th. Refer [Stage1: Infrastructure deployment](https://quip-amazon.com/wDrEAxaBEI3A#temp:C:fdVcab143c12c0f4174a628110fe) for the base infrastructure deployment. **Please make sure to deploy the stack on the availability zone P5 capacity will be procured.  Please refer [column R(AZ) of the engagement doc](https://quip-amazon.com/eQ1mAZdTbJVj/GENIAC-Cycle2-Customer-and-Engagement-Team)for to find out AZ ID.** 

## Cluster Deployment 

This section goes through all the steps necessary to deploy the architecture discussed in the previous section. Moreover, this section covers how to set up a [Data Repository Association (DRA)](https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html) between the S3 bucket and FSx Lustre Filesystem. With DRA, user can access to the objects in Amazon S3 bucket through Lustre filesystem.

### Stage0: Preflight check

Ask customer to select one person (Cx) who will share their screen and conduct following steps.
**Step0: Check resource info** 
The capacity should have been already accepted by Classmethod.  
Account specific info you will need:

* Customer Account ID
* AZ for P5 capacity (`apne1-az1`)
* Number of procured P5 instances
* Bucket name for the data S3 bucket. If it does not exists ask customer to create. This bucket will be used to persist all the data/model checkpoints throughout 6 months of the cluster operation. Please refer to the [Cloudformation template](https://github.com/aws-samples/awsome-distributed-training/blob/main/1.architectures/0.s3/0.private-bucket.yaml) for S3 deployment. You can use the following quick deployment link: https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://awsome-distributed-training.s3.amazonaws.com/templates/0.private-bucket.yaml&stackName=ML-S3
    The bucket name is referred as `${BUCKET_NAME_DATA}`.

**Local environment setup**

* terminal (local shell or cloudshell)
* Admin role is required
* NodeJS. You can install from https://nodejs.org/en/download/package-manager (Win/MacOS) or https://formulae.brew.sh/formula/node (MacOS)
* pcluster version: [v3.11.1](https://github.com/aws/aws-parallelcluster/releases/tag/v3.11.1) 

```
pip3 install -U "aws-parallelcluster==3.11.1"
```

🚨 Please use v3.11.1 instead of v3.11.0 due to following issue (we install enroot/pyxis through postinstall script) 🚨 

>Important message on PC 3.11. Based on an [issue discovered](https://amzn-aws.slack.com/archives/C017LP32MN3/p1728408306384719) we investigated further to reveal a problem with the our current implementation of Pyxis and Enroot on PC. We have published a GitHub [Issue and mitigation](https://github.com/aws/aws-parallelcluster/wiki/(3.11.0)-Job-submission-failure-caused-by-race-condition-in-Pyxis-configuration) for the same and are working on a Patch release 3.11.1 scheduled to come out next week. For now we have planned to send out a PHD notification when the patch has been released, the PHD will inform the customer on the mitigation and recommend to upgrade to 3.11.1. (edited) 



#### Generate an SSH Key-pair

#### SSH is [commonly](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html) used to connect to Amazon EC2 instances. To allow you to connect to your instances, you can generate a key-pair using the AWS CLI in your AWS Cloud9 instance. This example uses the key name lab-your-key but you can change the name of your key. Enter the following command to generate a key pair:

```
aws ec2 create-key-pair --key-name key --query KeyMaterial --output text > lab-your-key.pem
chmod 400 key.pem
```


```
cp ~/Downloads/ap-northeast-1.pem ~/.ssh 
chmod 600 ~/.ssh/ap-northeast-1.pem 
```

### Stage1: Infrastructure deployment

**Deploy parallelcluster-prerequisites**
Create [_Amazon Virtual Private Cloud_](https://aws.amazon.com/vpc/) (Amazon VPC) network and security groups, deploying supporting services such as FSx for Lustre in their VPC, and publishing their Slurm lifecycle scripts to an S3 bucket. Advice Cx to use[_CloudFormation stack_](https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateUrl=https://awsome-distributed-training.s3.amazonaws.com/templates/parallelcluster-prerequisites.yaml&stackName=parallelcluster-prerequisites.) to create those resources. They need to open the link and specify the region and availability zone where they have their compute resources. Fill out “Availability Zone configuration for the subnets”, and create the stack. 
🚨 Do not change FSx for Lustre (FSxL) configuration at this point 🚨 
Due to the limited FSxL capacity, deployment would likely fail if Cx increases `Capacity` or `PerUnitStorageThroughput` . Please make sure that Cx first deploys the stack “as is” and then try to scale up FSxL filesystem after Oct. 25th:
Proceed to the next step once the Cloud Formation stack creation completed.
**Associate Lustre storage with S3 bucket with data-repository-association (DRA)**
https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html
Wait for completion of the stack creation.
Run `create_config.sh`  script which will fetch resource info from the CloudFormation stack created in the previous step:

```
export AWS_REGION=ap-northeast-1
export INSTANCES=p5.48xlarge
export BUCKET_NAME_DATA=<ADD YOUR BUCKET NAME HERE>
curl 'https://static.us-east-1.prod.workshops.aws/public/cfe259f7-a9f1-4040-acd8-6cd911f1da63/static/scripts/create_config.sh' --output create_config.sh
bash create_config.sh
source env_vars
```

Note: `BUCKET_NAME_DATA`  is the bucket created in [Step0: Check resource info](https://quip-amazon.com/wDrEAxaBEI3A#temp:C:fdV996b34e8ad4e4dc3ac2ef128b). 
Create DRA as follows:

```
aws fsx create-data-repository-association \
    --file-system-id ${FSX_ID} \
    --file-system-path "/data" \
    --data-repository-path s3://${BUCKET_NAME_DATA} \
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

```
aws fsx describe-data-repository-associations \
    --filters "Name=file-system-id,Values=${FSX_ID}" --query "Associations[0].Lifecycle" --output text
```

Wait until the output becomes `AVAILABLE` . You also can check the status of DRA on AWS console:


### Stage2: Cluster deployment

In this stage, we are going to deploy PCluster with P5 instances.


```
source env_vars
export KEY_PAIR=<your keypair name without .pem>
export CAPACITY_RESERVATION_ID=cr-<YOUR CRID>
export NUM_INSTANCES=0
cat > config.yaml << EOF
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

Imds:
  ImdsSupport: v1.0
Image:
  Os: ubuntu2204
HeadNode:
  InstanceType: m5.8xlarge
  Networking:
    SubnetId: ${PUBLIC_SUBNET_ID}
    AdditionalSecurityGroups:
      - ${SECURITY_GROUP}
  Ssh:                         # Remove this field if you don't need SSH
    KeyName: ${KEY_PAIR}       # access to headnode without SSM
  LocalStorage:
    RootVolume:
      Size: 500
      DeleteOnTermination: true # that's your root and /home volume for users
  Iam:
    AdditionalIamPolicies: # grant ECR, SSM and S3 read access
      - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      - Policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
      - Policy: arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  CustomActions:
    OnNodeConfigured:
      Sequence:
        - Script: 'https://raw.githubusercontent.com/aws-samples/aws-parallelcluster-post-install-scripts/main/docker/postinstall.sh'
        - Script: 'https://raw.githubusercontent.com/aws-samples/aws-parallelcluster-post-install-scripts/main/nccl/postinstall.sh'
          Args:
            - v2.23.4-1 # NCCL version
            - v1.11.0-aws # AWS OFI NCCL version
  Imds:
    Secured: false
Scheduling:
  Scheduler: slurm
  SlurmSettings:
    ScaledownIdletime: 60
    QueueUpdateStrategy: DRAIN
    CustomSlurmSettings:
      # Simple accounting to text file /home/slurm/slurm-job-completions.txt.
      - JobCompType: jobcomp/filetxt
      - JobCompLoc: /home/slurm/slurm-job-completions.txt
      - JobAcctGatherType: jobacct_gather/linux
  SlurmQueues:
    - Name: compute-gpu
      CapacityType: ONDEMAND
      Networking:
        SubnetIds:
          - ${PRIVATE_SUBNET_ID}
        PlacementGroup:
          Enabled: true  # set this to false if using a targeted ODCR
        AdditionalSecurityGroups:
          - ${SECURITY_GROUP}
      ComputeSettings:
        LocalStorage:
          EphemeralVolume:
            MountDir: /scratch # each instance has a local scratch on NVMe
          RootVolume:
            Size: 200     
      ComputeResources:
        - Name: distributed-ml
          InstanceType: p5.48xlarge
          MinCount: ${NUM_INSTANCES} # if min = max then capacity is maintained and will
          MaxCount: ${NUM_INSTANCES} # not scale down
          Efa:
            Enabled: true
          CapacityReservationTarget:
            CapacityReservationId: ${CAPACITY_RESERVATION_ID}
      CustomActions:
        OnNodeConfigured:
          Sequence:
            - Script: 'https://raw.githubusercontent.com/aws-samples/aws-parallelcluster-post-install-scripts/main/docker/postinstall.sh'
            - Script: 'https://raw.githubusercontent.com/aws-samples/aws-parallelcluster-post-install-scripts/main/nccl/postinstall.sh'
              Args:
                - v2.23.4-1 # NCCL version
                - v1.11.0-aws # AWS OFI NCCL version
SharedStorage:
  - Name: HomeDirs
    MountDir: /home
    StorageType: FsxOpenZfs
    FsxOpenZfsSettings:
      VolumeId: ${FSXO_ID}
  - MountDir: /fsx
    Name: fsx
    StorageType: FsxLustre
    FsxLustreSettings:
      FileSystemId: ${FSX_ID}
Monitoring:
  DetailedMonitoring: true
  Logs:
    CloudWatch:
      Enabled: true # good for debug
  Dashboards:
    CloudWatch:
      Enabled: true # provide basic dashboards
Tags:
  - Key: 'Grafana'
    Value: 'true'
EOF
```

Then create cluster

```
 pcluster create-cluster -n ml-cluster -c config.yaml -r ${AWS_REGION}
```

You will see the output like follows:

```
{
  "cluster": {
    "clusterName": "ml-cluster-p5",
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
    },
    {
      "level": "WARNING",
      "type": "PlacementGroupCapacityReservationValidator",
      "message": "When using an open or targeted capacity reservation with an unrelated placement group, insufficient capacity errors may occur due to placement constraints outside of the reservation even if the capacity reservation has remaining capacity. Please consider either not using a placement group for the compute resource or creating a new capacity reservation in a related placement group."
    }
  ]
}
```

Then you can check progress of cluster creation on Cloudformation console
Alternatively, you can check the progress through `pcluster` command as follows:

```
pcluster list-clusters -r ${AWS_REGION}
```

### Step3:  Cluster sanity check

Access to the headnode via SSH over SSM or SSH (if you set up keypair). You can retrieve IP address of the head node with the following command

```
pcluster ssh --cluster-name ml-cluster --dry-run
```

If you want to access to the headnode SSH over SSM please refer to the workshop https://catalog.workshops.aws/ml-on-aws-parallelcluster/en-US/03-cluster/04-connect-cluster

Once login to the headnode, make sure you are working as a `ubuntu` user:
Then execute NCCL tests to make sure all the GPUs on the cluster functional:

```
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd awsome-distributed-training/micro-benchmarks/nccl-tests/slurm
```

```
sbatch nccl-tests-ami.sbatch /opt/nccl-tests/build/all_reduce_perf /opt/nccl/build/lib
watch squeue # wait for job to go into 'R' running
```



## References

* NCCL Tests — Understanding NCCL Bandwidth
    * https://github.com/aws-samples/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests#3-understanding-nccl-bandwidth

