---
name: training-job-deployer
description: Deploy distributed PyTorch training jobs on Amazon EKS using torchrun. Supports PyTorchJob, multi-node training, automatic torchrun configuration, real-time monitoring, and auto-retry on failures.
license: MIT
compatibility: opencode
metadata:
  category: training
  author: opencode
---

## What I do

Deploys distributed training jobs on EKS:

1. **Automatic torchrun Configuration**: Sets up distributed training automatically
2. **PyTorchJob Integration**: Uses Kubeflow PyTorchJob for orchestration
3. **Multi-Node Support**: Scale from 1 to 100+ nodes
4. **Real-Time Monitoring**: Stream logs and track progress
5. **Auto-Retry**: Automatically retry on known failures
6. **Checkpoint Persistence**: Automatic checkpoint volume mounting

## When to use me

Use this skill when you need to:
- Deploy a distributed training job on EKS
- Run PyTorch FSDP training across multiple nodes
- Monitor training progress in real-time
- Automatically handle training failures
- Deploy Llama, GPT, or other LLM training

## How to use me

### Command Line
```bash
# Deploy training job
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4 \
  --job_name llama32-1b-training \
  --monitor
```

### Python API
```python
from training_job_deployer.src.deploy_job import deploy_training_job

result = deploy_training_job(
    cluster_name="my-cluster",
    num_nodes=4,
    job_name="llama32-1b-training",
    monitor=True
)
```

## Features

- **torchrun Integration**: Automatic distributed setup
- **PyTorchJob**: Native Kubeflow support
- **Multi-GPU**: Support for multiple GPUs per node
- **HuggingFace**: Token support for gated models
- **Monitoring**: Real-time log streaming
- **Auto-Retry**: Intelligent failure recovery

## Parameters

- `job_name`: Name for the training job (default: "fsdp-training")
- `image_uri`: Docker image (auto-detect from ECR if not provided)
- `instance_type`: EC2 instance type (default: "ml.g5.8xlarge")
- `num_nodes`: Number of nodes for distributed training (default: 4)
- `gpu_per_node`: GPUs per node (default: 1)
- `cluster_name`: EKS cluster name (required)
- `torchrun_path`: Path to torchrun (default: "/opt/conda/bin/torchrun")
- `monitor`: Monitor job after deployment (default: true)
- `auto_retry`: Auto-retry on failures (default: true)
- `hf_token`: HuggingFace token for gated models (optional)

## Output

Returns deployment status:
- Job status
- Master pod name
- Fixes applied
- Monitoring information

## Examples

### Basic deployment
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4
```

### Deploy with monitoring
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4 \
  --job_name llama32-1b \
  --monitor
```

### Deploy gated model
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 8 \
  --hf_token "hf_..."
```

## Monitoring

After deployment, monitor with:
```bash
# Check job status
kubectl get pytorchjobs

# View logs
kubectl logs -f <job-name>-worker-0

# Check all workers
kubectl logs -l training.kubeflow.org/job-name=<job-name>
```
