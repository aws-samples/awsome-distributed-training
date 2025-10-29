# AWS Batch distributed training architectures

This architecture serves as an example to run distributed training jobs on p4d.24xlarge instances but can be easily be modified to accommodate other instance kinds (Trn or other P instances).

> **Important**: it is assumed that you deployed the VPC template [`2.vpc-one-az.yaml`](../1.vpc_network/2.vpc-oneaz.yaml) as our Batch template will fetch automatically the EFA Security Group ID (SG) and Subnet ID to setup the AWS Batch Compute Environment. Both the SG and Subnet are exported values from the VPC template.

This architecture consists of the following resources:

- [AWS Batch Compute Environment](https://docs.aws.amazon.com/batch/latest/userguide/compute_environments.html) for [Multi-node parallel jobs](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html). It is similar to a compute cluster.
- [AWS Batch Job Queue](https://docs.aws.amazon.com/batch/latest/userguide/job_queues.html) attached to the compute environment. It is similar to a queue for job schedulers (Slurm, LSF...).
- [EC2 Launch Template](https://docs.aws.amazon.com/autoscaling/ec2/userguide/launch-templates.html) which used to setup 4 EFA cards on our instance.
- [Job Definition](https://docs.aws.amazon.com/batch/latest/userguide/job_definitions.html) serves as a template for our jobs and refers to the container registry to pull containers
- [ECR Container Registry](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html) is used to store containers.

## Template

This template deploys AWS Batch and EC2 resources. It can be deployed via the console and the AWS CLI. Regardless of the deployment method it is assumed that you deployed the VPC template [`2.vpc-one-az.yaml`](../1.vpc_network/2.vpc-oneaz.yaml) prior to deploying that one.

- **Template file**: [`0.aws-batch-distributed-training.yaml`](./0.aws-batch-distributed-training.yaml)

### Quick Create

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://awsome-distributed-training.s3.amazonaws.com/templates/0.aws-batch-distributed-training.yaml&stackName=AWS-Batch)


## List of Parameters

The templates takes parameters that are mandatory and optional, see below for more details.

| Name                    | Type        | Details                                                               |
|-------------------------|-------------|-----------------------------------------------------------------------|
| `VPCStackParameter`     | Required    | Name of the VPC stack in CloudFormation.                              |
| `AMI`                   | Optional    | ID of the AMI if using a custom one otherwise leave blank             |
| `CapacityReservationId` | Optional    | Use that or the ResourceGroup to refer to an EC2 reservation          |
| `CapacityReservationResourceGroup`    | Optional    | Use that or the CapacityReservationId.                  |
| `EC2KeyPair`            | Optional    | EC2 key pair to use in case you want to connect through ssh for debug.|
| `CreatePlacementGroup`  | Optional    | Create a placement group for the instances.                           |


## Deploy with the AWS CLI

If you'd like to deploy through the AWS CLI instead of the quick create link above, the command to deploy the template is shown below. Please edit the parameters values with your own configuration.

```bash
aws cloudformation create-stack --stack-name aws-batch-p5 \
                                --template-body file://0.aws-batch-distributed-training-p5.yaml \
                                --parameters ParameterKey=VPCStackParameter,ParameterValue="aws-batch-vpc" \
                                             ParameterKey=CapacityReservationId,ParameterValue="cr-1234567890" \
                                --capabilities CAPABILITY_NAMED_IAM
```

## P6 Deployment

For P6 instances (p6-b200.48xlarge), use the simplified template that eliminates the need for custom Docker images and bootstrap scripts.

- **Template file**: [`aws-batch-distributed-training-p6.yaml`](./aws-batch-distributed-training-p6.yaml)

### Features

- Inline container setup - no custom Dockerfile needed
- Uses public NCCL tests image directly: `public.ecr.aws/hpc-cloud/nccl-tests:latest`
- Capacity Reservation Resource Group support for easier capacity management
- Manual SSH key generation stored in Secrets Manager
- Single CloudFormation template deployment

### Deployment Steps

```bash
# Step 1: Deploy CloudFormation Stack
aws cloudformation create-stack --stack-name batch-p6 \
  --template-body file://aws-batch-distributed-training-p6.yaml \
  --parameters \
    ParameterKey=VPCStackParameter,ParameterValue="vpc-stack-ml" \
    ParameterKey=CapacityReservationId,ParameterValue="cr-1234567890" \
  --capabilities CAPABILITY_NAMED_IAM

# Step 2: Generate and Upload SSH Key
ssh-keygen -t rsa -b 2048 -N '' -f /tmp/batch_key
aws secretsmanager put-secret-value \
  --secret-id batch-p6-ssh-key \
  --secret-string file:///tmp/batch_key
rm /tmp/batch_key /tmp/batch_key.pub
```

### P6 Template Parameters

| Name                      | Type     | Details                                     |
|---------------------------|----------|---------------------------------------------|
| `VPCStackParameter`       | Required | Name of the VPC stack in CloudFormation     |
| `CapacityReservationId`   | Required | Capacity Reservation ID (e.g., cr-1234567890) |

### Submitting a Test Job

After deployment and SSH key setup, submit a multi-node NCCL test job:

```bash
# Get the job definition and queue from stack outputs
JOB_DEFINITION=$(aws cloudformation describe-stacks --stack-name batch-p6 \
  --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionMultiInstance`].OutputValue' \
  --output text)

JOB_QUEUE=$(aws cloudformation describe-stacks --stack-name batch-p6 \
  --query 'Stacks[0].Outputs[?OutputKey==`DistributedDeepLearningJQ`].OutputValue' \
  --output text)

# Submit a 2-node NCCL test job
aws batch submit-job \
  --job-name nccl-test-2node \
  --job-queue ${JOB_QUEUE} \
  --job-definition ${JOB_DEFINITION} \
  --node-overrides numNodes=2

# Check job status
aws batch describe-jobs --jobs <job-id>

# View job logs in CloudWatch Logs (check the job's logStreamName from describe-jobs)
aws logs tail /aws/batch/job --follow
```

### P6 Architecture Notes

- **8 EFA interfaces** configured for p6-b200.48xlarge instances
- **Inline bash script** in Job Definition handles SSH setup, hostfile generation, and NCCL test execution
- **No custom Docker image required** - uses base NCCL tests image with runtime configuration
- **SSH keys** stored in Secrets Manager and fetched at container startup
- **Default NCCL Test**: all_reduce_perf with 8 GPUs per node, 16 total processes

## Gotchas

There are a few things to know as you evaluate this architecture:
- EFA interfaces need to be declared explicitly in the EC2 Launch Template and you need to provide the security group used for EFA.
- The Compute Environment must retrieve the list of private subnets from the VPC template. This list is exported by the VPC template.

## Architecture Diagram

<img src="../../0.docs/batch-arch.png" width="500">
