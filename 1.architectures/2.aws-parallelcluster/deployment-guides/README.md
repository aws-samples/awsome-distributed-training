Here, we provide detailed instruction for the cluster deployment in various different setup scenario

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