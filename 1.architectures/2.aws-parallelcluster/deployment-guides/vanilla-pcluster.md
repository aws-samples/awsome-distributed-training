# Vanilla PCluster Deployment

This runbook is to provide step-by-step guide on vanilla [AWS ParallelCluster (PCluster)](https://github.com/aws/aws-parallelcluster) deployment which supports following features:

|Feature	|Enabled	|
|---	|---	|
|Multi-user support	|FALSE	|
|Accounting	|FALSE	|
|Observability	|FALSE	|

## Introduction

This setup involves two main infrastructure components, `parallelcluster-prerequisites`  (the base infrastructure stack including VPC, FSx for Lustre, FSx for Open ZFS) and a PCluster itself.  

![core-infra-architecture](../../../0.docs/core-infra-architecture.png)

## Cluster Deployment 

This section goes through all the steps necessary to deploy the architecture discussed in the previous section. Moreover, this section covers how to set up a [Data Repository Association (DRA)](https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html) between the S3 bucket and FSx Lustre Filesystem. With DRA, user can access to the objects in Amazon S3 bucket through Lustre filesystem. **Make sure to check [prerequisites](https://github.com/aws-samples/awsome-distributed-training/tree/geniac/1.architectures/2.aws-parallelcluster#2-pre-requisites) before proceed.**


In this example, are going to deploy PCluster with P5 instances.


```bash
source env_vars
export KEY_PAIR_NAME=<your keypair name without .pem>
export CAPACITY_RESERVATION_ID=cr-<YOUR CRID>
export INSTANCE=p5.48xlarge
export NUM_INSTANCES=4
bash create_config.sh
```

Then create cluster with the following command:

```bash
source env_vars
cat templates/cluster-vanilla.yaml | envsubst > configs/cluster-vanilla.yaml
```


```bash
pcluster create-cluster -n ml-cluster -c configs/cluster-vanilla.yaml -r ${AWS_REGION}
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

