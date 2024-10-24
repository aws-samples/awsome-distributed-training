# PCluster + Observability Deployment

This runbook is to provide step-by-step guide on PCluster + Grafana observability deployment.

|Feature	|Enabled	|
|---	|---	|
|Multi-user support	|FALSE	|
|Accounting	|FALSE	|
|Observability	|TRUE	|



## Managed Observability stack deployment

[<kbd> <br> 1-Click Deploy 🚀 <br> </kbd>](https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://awsome-distributed-training.s3.amazonaws.com/templates/cluster-observability.yaml&stackName=Slurm-Observability)

![observability](../../../0.docs//observability_architecture.png)

## Cluster Deployment 

This section goes through all the steps necessary to deploy the architecture discussed in the previous section. Moreover, this section covers how to set up a [Data Repository Association (DRA)](https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html) between the S3 bucket and FSx Lustre Filesystem. With DRA, user can access to the objects in Amazon S3 bucket through Lustre filesystem. **Make sure to check [prerequisites](https://github.com/aws-samples/awsome-distributed-training/tree/geniac/1.architectures/2.aws-parallelcluster#2-pre-requisites) before proceed.**


```bash
export KEY_PAIR_NAME=<your keypair name without .pem>
export CAPACITY_RESERVATION_ID=cr-<YOUR CRID>
export INSTANCE=p5.48xlarge
export NUM_INSTANCES=4
export AMPREMOTEWRITEURL=https://aps-workspaces.ap-northeast-1.amazonaws.com/workspaces/ws-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/api/v1/remote_write
bash create_config.sh
source env_vars
```


