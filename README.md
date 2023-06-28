#  ML Training Reference Architectures & Tests

This directory contains reference architectures for distributed model training with [AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html) and [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html) and test cases for different types and sizes of models (Falcon, GPT3, T5) as well as different frameworks and parallel optimizations (Pytorch DDP/FSDP, MegatronLM, MegatronLM-DeepSpeed).

## Reference architectures

The reference architectures shared below

### AWS ParallelCluster

Each reference architecture provides consists of the following components:

#### Compute
- **head-node**: login and controller node that users will use to submit jobs. It is set to an [m5.8xlarge](https://aws.amazon.com/ec2/instance-types/m5/)..
- **compute-gpu**: is the queue (or partition) to run your ML training jobs. The instances are either [p4de.24xlarge](https://aws.amazon.com/ec2/instance-types/p4/) or [trn1.32xlarge](https://aws.amazon.com/ec2/instance-types/trn1/) which are recommended for training, especially for LLMs or large models. The default number of instances in the queue has been set to *4* and can be changed as necessary.
- **inference-gpu**: is an optional queue that can be used to run inference workloads and uses [g5.12xlarge](https://aws.amazon.com/ec2/instance-types/m5/).

#### Storage

Storage comes in 3 flavors:
- **Local**: head and compute nodes have 200GiB of EBS volume mounted on `/`. In addition, the headnode has an EBS volume of `200GiB` mounted on `/apps` The compute nodes have NVMe drives striped in RAID0 and mounted as `/local_scratch`.
- **File network storage**: The head-node shares `/home` and `/apps` to the whole cluster through NFS. These directories are automatically mounted on every instance in the cluster and accessible through the same path. `/home` is a regular home directory, `/apps` is a shared directory where applications or shared files can be stored. Please note that none should be used for data intensive tasks.
- **High performance filesystem**: An [FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html) filesystem can be access from every cluster node on `/fsx`. This is where users would store their datasets. This file system has been sized to 4.8TiB and provides 1.2GB/s of aggregated throughput. You can modify its size and the throughput per TB provisioned in the config file following the service [documentation](https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html).


#### Network

Applications will make use of [Elastic Fabric Adapter (EFA)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html) for distributed training. In addition, instances will be placed to one another through the use of placement groups or assistance from AWS.

Placement groups are only relevant for distributed training, not inference. You may remove the placement groups declaration in the config file if requested. In which case you will need to delete these lines

```yaml
PlacementGroup:
  Enabled: true
```

#### Installing applications & libraries

You can chose to use a custom image or post-install scripts to install your application stack.

- **Custom images**: the image needs to be pre-built before creating a cluster. They are preferred for drivers, kernel modules or libraries regularly used and seeing little to no updates. This option is preferred to ensure repeatability. You can use custom images as follows:
    ```yaml
    Image:
      Os: alinux2 #system type
      CustomAmi: PLACEHOLDER_CUSTOM_AMI_ID #replace by custom imageAMI ID
    ```
    If not using a custom image, remove the `CustomAmi` field.
- **Post-install scripts**: these scripts will be executed at instance boot (head+compute). This option is recommended for quick testing and will increase instance boot time. You can run post-install scripts through `CustomActions` for the head node and the compute nodes.

### Architectures templates

Each reference architectures provides an example of cluster for different use cases. The architectures most commonly used are:

- `distributed-training-gpu`: base template, uses the default AMI with no software installed.
- `distributed-training-p4de_custom_ami`: base cluster with a custom AMI to install custom software.
- `distributed-training-p4de_postinstall_scripts`: same as above but uses post-install scripts to install Docker, Pyxis and Enroot.


Alternatively you can refer to these architectures for more specific use cases:

- `distributed-training-p4de_batch-inference-g5_custom_ami`: multi-queue template with p4de for training and g5 for inference. It assumes a custom AMI.
- `distributed-training-trn1_custom_ami`: uses Trainium instances for distributed training. Assumes a custom AMI.

### Diagram

![AWS ParallelCluster diagram](/docs/parallelcluster-arch-diagram.png)

## Test Cases
