# ML Training Reference Architectures & Tests <!-- omit from toc -->

This directory contains reference architectures and test cases for distributed model training with [AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html), [AWS Batch](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html), and [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html). The test cases cover different types and sizes of models (Falcon, GPT3, T5) as well as different frameworks and parallel optimizations (Pytorch DDP/FSDP, MegatronLM, MegatronLM-DeepSpeed).

The major components of this directory are:

```bash
reference-architectures/
|-- 1.architectures                # CloudFormation templates for various ref arch
|   |-- 0.s3                       # Create S3 bucket
|   |-- 1.vpc_network              # Create VPC
|   |-- 2.aws-parallelcluster      # Parallel Cluster
|   `-- 3.aws-batch                # AWS Batch
|-- 2.amazon_machine_images/       # Scripts to create AMIs
|-- 3.test_cases/                  # Reference test cases and/or benchmark scripts
`-- ...
```

**NOTE**: the architectures are designed to work with the S3 bucket and VPC created using reference templates `1.architectures/0.s3/` and `1.architectures/1.vpc_network/`. _You're strongly recommended to deploy these two templates **before** deploying any of the reference architectures._

## 1. AWS ParallelCluster

![AWS ParallelCluster diagram](0.docs/parallelcluster-arch-diagram.png)

This reference architecture consists of the following components:

1. **Compute** is represented through the following:
   - **head-node**: login and controller node that users will use to submit jobs. It is set to an [m5.8xlarge](https://aws.amazon.com/ec2/instance-types/m5/).
   - **compute-gpu**: is the queue (or partition) to run your ML training jobs. The instances are either [p4de.24xlarge](https://aws.amazon.com/ec2/instance-types/p4/) or [trn1.32xlarge](https://aws.amazon.com/ec2/instance-types/trn1/) which are recommended for training, especially for LLMs or large models. The default number of instances in the queue has been set to _4_ and can be changed as necessary.
   - **inference-gpu**: is an optional queue that can be used to run inference workloads and uses [g5.12xlarge](https://aws.amazon.com/ec2/instance-types/m5/).

2. **Storage** comes in 3 flavors:
   - **Local**: head and compute nodes have 200GiB of EBS volume mounted on `/`. In addition, the headnode has an EBS volume of `200GiB` mounted on `/apps` The compute nodes have NVMe drives striped in RAID0 and mounted as `/local_scratch`.
   - **File network storage**: The head-node shares `/home` and `/apps` to the whole cluster through NFS. These directories are automatically mounted on every instance in the cluster and accessible through the same path. `/home` is a regular home directory, `/apps` is a shared directory where applications or shared files can be stored. Please note that none should be used for data intensive tasks.
   - **High performance filesystem**: An [FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html) filesystem can be access from every cluster node on `/fsx`. This is where users would store their datasets. This file system has been sized to 4.8TiB and provides 1.2GB/s of aggregated throughput. You can modify its size and the throughput per TB provisioned in the config file following the service [documentation](https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html).

3. **Network**: Applications will make use of [Elastic Fabric Adapter (EFA)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html) for distributed training. In addition, instances will be placed to one another through the use of placement groups or assistance from AWS.

   Placement groups are only relevant for distributed training, not inference. You may remove the placement groups declaration in the config file if requested. In which case you will need to delete these lines

   ```yaml
   PlacementGroup:
     Enabled: true
   ```

### 1.1. Pre-Deployment decision: AMI vs post-install scripts

Parallel Cluster offers you two options to install applications & libraries into the nodes via _custom AMI_ or _post-install scripts_.

- **Custom AMI**: the image needs to be pre-built **before** creating a cluster. They are preferred for drivers, kernel modules or libraries regularly used and seeing little to no updates. This option is preferred to ensure repeatability. To create an AMI, refer to `2.amazon_machine_images/`. Once AMI is created, you can tell Parallel Cluster to use custom images as follows:

    ```yaml
    Image:
      Os: alinux2 #system type
      CustomAmi: PLACEHOLDER_CUSTOM_AMI_ID #replace by custom imageAMI ID
    ```

    If not using a custom image, remove the `CustomAmi` field.
- **Post-install scripts**: these scripts will be executed **during** deployment which is at instance boot (head+compute). This option is recommended for quick testing and will increase instance boot time. You can run post-install scripts through `CustomActions` for the head node and the compute nodes.

### 1.2. Select cluster template

Choose one of the available Parallel Cluster templates. Each template provides an example of cluster for different use cases. The architectures most commonly used are:

- `distributed-training-gpu`: base template, uses the default AMI with no software installed.
- `distributed-training-p4de_custom_ami`: base cluster with a custom AMI to install custom software.
- `distributed-training-p4de_postinstall_scripts`: same as above but uses post-install scripts to install Docker, Pyxis and Enroot.

Alternatively you can refer to these architectures for more specific use cases:

- `distributed-training-p4de_batch-inference-g5_custom_ami`: multi-queue template with p4de for training and g5 for inference. It assumes a custom AMI.
- `distributed-training-trn1_custom_ami`: uses Trainium instances for distributed training. Assumes a custom AMI.

### 1.3. Deploy a cluster

The templates contain placeholder variables that you **must** to replace before use.

- `PLACEHOLDER_CUSTOM_AMI_ID`: if using a custom AMI then replace with the custom AMI ID (`ami-12356790abcd`).
- `PLACEHOLDER_PUBLIC_SUBNET`: change to the id of a public subnet to host the head-node (`subnet-12356790abcd`).
- `PLACEHOLDER_PRIVATE_SUBNET`: change to the id of a public subnet to host the compute nodes (`subnet-12356790abcd`).
- `PLACEHOLDER_SSH_KEY`: ID of the SSH key you'd like to use to connect to the head-node. You can also use AWS Systems Manager Session Manager (SSM).
- `PLACEHOLDER_CAPACITY_RESERVATION_ID`: if using a capacity reservation put the ID here (`cr-12356790abcd`).

By this point, if you haven't done so, please install Parallel Cluster CLI on your workstation by following this [guide](https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html).

To create the cluster, use the command below:

```bash
pcluster create-cluster --cluster-configuration cluster.yaml --cluster-name cluster-g4v7 --region us-east-1
```

You can follow the [documentation](https://docs.aws.amazon.com/parallelcluster/latest/ug/commands-v3.html) to review the list of all AWS ParallelCluster commands.

## 2. Test Cases: Support Matrix

All test cases are under `3.test_cases/`.

| Test case               | PC  | EKS | AWS Batch |
| ----------------------- | --- | --- | --------- |
| `0.nccl-tests`          | ✅   | ❓   | ❓         |
| `1.megatron-lm`         | ✅   | ❓   | ❓         |
| `2.nemo-launcher-23.03` | ✅   | ❌   | ❌         |
| `3.MPT`                 | ❓   | ❓   | ❓         |
| `4.DDP`                 | ❓   | ❓   | ❓         |
