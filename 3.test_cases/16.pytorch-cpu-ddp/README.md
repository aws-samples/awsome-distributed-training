# PyTorch DDP on CPU <!-- omit in toc -->

Isolated environments are crucial for reproducible machine learning because they encapsulate specific software versions and dependencies, ensuring models are consistently retrainable, shareable, and deployable without compatibility issues.

[Anaconda](https://www.anaconda.com/) leverages conda environments to create distinct spaces for projects, allowing different Python versions and libraries to coexist without conflicts by isolating updates to their respective environments. [Docker](https://www.docker.com/), a containerization platform, packages applications and their dependencies into containers, ensuring they run seamlessly across any Linux server by providing OS-level virtualization and encapsulating the entire runtime environment.

This example showcases CPU [PyTorch DDP](https://pytorch.org/tutorials/beginner/ddp_series_theory.html) environment setup utilizing these approaches for efficient environment management.


## 1. Preparation

This guide is compatible with both Slurm and EKS clusters. Please follow 
the sections corresponding to the type of cluster you use.
The guide assumes that you have the following:

**Slurm:**
* A functional Slurm cluster on AWS, whose compute instances are based on DeepLearning AMI.
* An FSx for Lustre filesystem mounted on `/fsx`.
* `enroot` if you want to run the container example.

**EKS:**
* An EKS cluster on AWS with x86-based CPU nodes, accessible via `kubectl`.
* An FSx for Lustre persistent volume claim named `fsx-pv`, you can use an example from [here](https://github.com/aws-samples/aws-do-eks/tree/main/Container-Root/eks/deployment/csi/fsx), if you need to create one.
* Docker 

We recommend that you setup a Slurm or EKS cluster using the templates in the architectures [directory](../../1.architectures). 

## 2. Submit training job using conda environment on Slurm

In this step, you will create PyTorch virtual environment using conda.
This method is only available on Slurm because it runs the training job without
using a container.

```bash
bash 0.create-conda-env.sh
```

It will prepare `miniconda3` and `pt_cpu` `pt_cpu` includes `torchrun` 


Submit DDP training job with:

```bash
sbatch 1.conda-train.sbatch
```

Output of the training job can be found in `logs` directory:

```bash
# cat logs/cpu-ddp-conda_xxx.out
Node IP: 10.1.96.108
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] master_addr is only used for static rdzv_backend and when rdzv_endpoint is not specified.
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] 
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] *****************************************
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] Setting OMP_NUM_THREADS environment variable for each process to be 1 in default, to avoid your system being overloaded, please further tune the variable for optimal performance in your application as needed. 
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] *****************************************
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO] Starting elastic_operator with launch configs:
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   entrypoint       : ddp.py
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   min_nodes        : 2
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   max_nodes        : 2
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   nproc_per_node   : 4
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   run_id           : 5982
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_backend     : c10d
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_endpoint    : 10.1.96.108:29500
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_configs     : {'timeout': 900}
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   max_restarts     : 0
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   monitor_interval : 5
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   log_dir          : None
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   metrics_cfg      : {}
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO] 
[2024-03-12 08:22:45,552] torch.distributed.elastic.agent.server.local_elastic_agent: [INFO] log directory set to: /tmp/torchelastic_9g50nxjq/5982_tflt1tcd
[2024-03-12 08:22:45,552] torch.distributed.elastic.agent.server.api: [INFO] [default] starting workers for entrypoint: python
...
[RANK 3] Epoch 49 | Batchsize: 32 | Steps: 8
[RANK 5] Epoch 49 | Batchsize: 32 | Steps: 8
[RANK 4] Epoch 49 | Batchsize: 32 | Steps: 8
[2024-03-12 08:22:56,574] torch.distributed.elastic.agent.server.api: [INFO] [default] worker group successfully finished. Waiting 300 seconds for other agents to finish.
[2024-03-12 08:22:56,574] torch.distributed.elastic.agent.server.api: [INFO] Local worker group finished (WorkerState.SUCCEEDED). Waiting 300 seconds for other agents to finish
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] [default] worker group successfully finished. Waiting 300 seconds for other agents to finish.
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Local worker group finished (WorkerState.SUCCEEDED). Waiting 300 seconds for other agents to finish
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Done waiting for other agents. Elapsed: 0.0010929107666015625 seconds
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Done waiting for other agents. Elapsed: 0.0005395412445068359 seconds
```

## 3. Submit training job using Docker container

In this example, you'll learn how to use the official PyTorch Docker image 
and execute the container within the Slurm scheduler using Enroot or EKS using
kubeflow training operator. 


**Slurm:**

[Enroot](https://github.com/NVIDIA/enroot) uses the same underlying technologies 
as containers but removes much of the isolation they inherently provide 
while preserving filesystem separation. This approach is generally preferred 
in high-performance environments or virtualized environments where portability 
and reproducibility is important, but extra isolation is not warranted.

Create Enroot container images:

```bash
bash 2.create-enroot-image.sh
```

It will pull `pytorch/pytorch` container, then create [squashfs](https://www.kernel.org/doc/Documentation/filesystems/squashfs.txt) image named `pytorch.sqsh`.

Submit DDP training job using the image with:

```bash
sbatch 4.container-train.sbatch
```

Output of the training job can be found in `logs` directory:

```bash
# cat logs/cpu-ddp-container.out
Node IP: 10.1.96.108
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] master_addr is only used for static rdzv_backend and when rdzv_endpoint is not specified.
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] 
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] *****************************************
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] Setting OMP_NUM_THREADS environment variable for each process to be 1 in default, to avoid your system being overloaded, please further tune the variable for optimal performance in your application as needed. 
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] *****************************************
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO] Starting elastic_operator with launch configs:
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   entrypoint       : ddp.py
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   min_nodes        : 2
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   max_nodes        : 2
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   nproc_per_node   : 4
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   run_id           : 5982
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_backend     : c10d
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_endpoint    : 10.1.96.108:29500
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_configs     : {'timeout': 900}
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   max_restarts     : 0
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   monitor_interval : 5
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   log_dir          : None
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   metrics_cfg      : {}
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO] 
[2024-03-12 08:22:45,552] torch.distributed.elastic.agent.server.local_elastic_agent: [INFO] log directory set to: /tmp/torchelastic_9g50nxjq/5982_tflt1tcd
[2024-03-12 08:22:45,552] torch.distributed.elastic.agent.server.api: [INFO] [default] starting workers for entrypoint: python
...
[RANK 3] Epoch 49 | Batchsize: 32 | Steps: 8
[RANK 5] Epoch 49 | Batchsize: 32 | Steps: 8
[RANK 4] Epoch 49 | Batchsize: 32 | Steps: 8
[2024-03-12 08:22:56,574] torch.distributed.elastic.agent.server.api: [INFO] [default] worker group successfully finished. Waiting 300 seconds for other agents to finish.
[2024-03-12 08:22:56,574] torch.distributed.elastic.agent.server.api: [INFO] Local worker group finished (WorkerState.SUCCEEDED). Waiting 300 seconds for other agents to finish
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] [default] worker group successfully finished. Waiting 300 seconds for other agents to finish.
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Local worker group finished (WorkerState.SUCCEEDED). Waiting 300 seconds for other agents to finish
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Done waiting for other agents. Elapsed: 0.0010929107666015625 seconds
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Done waiting for other agents. Elapsed: 0.0005395412445068359 seconds
```


**EKS:**

Make sure kubeflow training operator is deployed to your cluster:
```bash
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"
```

Build the container image:

```bash
export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
docker build -t ${REGISTRY}fsdp:pytorch2.2-cpu .
```

Push the container image to the Elastic Container Registry in your account:
```bash
# Create registry if needed
REGISTRY_COUNT=$(aws ecr describe-repositories | grep \"fsdp\" | wc -l)
if [ "$REGISTRY_COUNT" == "0" ]; then
        aws ecr create-repository --repository-name fsdp
fi

# Login to registry
echo "Logging in to $REGISTRY ..."
aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY

# Push image to registry
docker image push ${REGISTRY}fsdp:pytorch2.2-cpu
```

Create manifest and launch PyTorchJob:
```bash
export IMAGE_URI=${REGISTRY}fsdp:pytorch2.2-cpu
export INSTANCE_TYPE=
export NUM_NODES=2
export CPU_PER_NODE=4
cat fsdp.yaml-template | envsubst > fsdp.yaml

kubectl apply -f ./fsdp.yaml
```

Check the status of your training job:
```bash
kubectl get pytorchjob 
kubectl get pods 
```

```text
NAME   STATE     AGE
fsdp   Running   16s

NAME                    READY   STATUS    RESTARTS   AGE
etcd-7787559c74-w9gwx   1/1     Running   0          18s
fsdp-worker-0           1/1     Running   0          18s
fsdp-worker-1           1/1     Running   0          18s
```

Each of the pods produces job logs. 
```bash
kubectl logs fsdp-worker-0
```

```text
2024-07-19 04:39:07,890] torch.distributed.run: [WARNING] *****************************************
INFO 2024-07-19 04:39:07,958 Etcd machines: ['http://0.0.0.0:2379']
INFO 2024-07-19 04:39:07,964 Attempting to join next rendezvous
INFO 2024-07-19 04:39:07,965 Observed existing rendezvous state: {'status': 'joinable', 'version': '1', 'participants': [0]}
INFO 2024-07-19 04:39:08,062 Joined rendezvous version 1 as rank 1. Full state: {'status': 'frozen', 'version': '1', 'participants': [0, 1], 'keep_alives': []}
INFO 2024-07-19 04:39:08,062 Waiting for remaining peers.
INFO 2024-07-19 04:39:08,063 All peers arrived. Confirming membership.
INFO 2024-07-19 04:39:08,149 Waiting for confirmations from all peers.
INFO 2024-07-19 04:39:08,161 Rendezvous version 1 is complete. Final state: {'status': 'final', 'version': '1', 'participants': [0, 1], 'keep_alives': ['/torchelastic/p2p/run_none/rdzv/v_1/rank_1', '/torchelastic/p2p/run_none/rdzv/v_1/rank_0'], 'num_workers_waiting': 0}
INFO 2024-07-19 04:39:08,161 Creating EtcdStore as the c10d::Store implementation
...
[RANK 1] Epoch 4991 | Batchsize: 32 | Steps: 8
Epoch 4990 | Training snapshot saved at /fsx/snapshot.pt
[RANK 0] Epoch 4991 | Batchsize: 32 | Steps: 8
[RANK 1] Epoch 4992 | Batchsize: 32 | Steps: 8
[RANK 0] Epoch 4992 | Batchsize: 32 | Steps: 8
[RANK 3] Epoch 4992 | Batchsize: 32 | Steps: 8
[RANK 2] Epoch 4992 | Batchsize: 32 | Steps: 8
[RANK 1] Epoch 4993 | Batchsize: 32 | Steps: 8
[RANK 2] Epoch 4993 | Batchsize: 32 | Steps: 8
...
```


Stop the training job:
```bash
kubectl delete -f ./fsdp.yaml
```

Note: Prior to running a new job, please stop any currently running or completed fsdp job.
