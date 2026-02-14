# Claude Code Commands for PyTorch FSDP

This directory contains Claude Code compatible commands for managing Docker images, EKS clusters, and training jobs for PyTorch FSDP workloads with automatic torchrun configuration for distributed training.

## Available Commands

### 1. build_docker_image
Build Docker images with automatic conflict detection and resolution.

```python
build_docker_image(
    dockerfile="Dockerfile",
    context=".",
    tag="auto",
    auto_fix=True,
    max_attempts=3
)
```

**Example:**
```python
# Build with defaults
build_docker_image()

# Build specific Dockerfile
build_docker_image(dockerfile="Dockerfile.gpu", tag="v1.0")

# Build without auto-fix
build_docker_image(auto_fix=False)
```

### 2. manage_eks_cluster
Discover, validate, and manage EKS clusters for training.

```python
manage_eks_cluster(
    cluster_name=None,  # Auto-discover if None
    region="us-west-2",
    validate_components=True,
    auto_fix=False,
    create_if_missing=False
)
```

**Example:**
```python
# Interactive cluster selection
manage_eks_cluster()

# Validate specific cluster
manage_eks_cluster(cluster_name="my-cluster", auto_fix=True)

# Create cluster if none exists
manage_eks_cluster(create_if_missing=True)
```

### 3. deploy_training_job
Deploy distributed training jobs to EKS with automatic torchrun configuration.

```python
deploy_training_job(
    job_name="fsdp-training",
    image_uri=None,              # Auto-detect from ECR
    instance_type="ml.g5.8xlarge",
    num_nodes=4,                 # Number of nodes for distributed training
    gpu_per_node=1,              # GPUs per node
    cluster_name="my-cluster",   # Required
    torchrun_path="/opt/conda/bin/torchrun",  # Path to torchrun
    monitor=True,                # Real-time monitoring
    auto_retry=True,             # Auto-retry on failures
    hf_token=None                # HuggingFace token for gated models
)
```

**Key Features:**
- ✅ **Automatic torchrun configuration** - No manual distributed setup needed
- ✅ **PyTorchJob integration** - Uses Kubeflow PyTorchJob for orchestration
- ✅ **Multi-node support** - Scale from 1 to 100+ nodes
- ✅ **Checkpoint persistence** - Automatic checkpoint volume mounting
- ✅ **HuggingFace integration** - Support for gated models with tokens
- ✅ **Real-time monitoring** - Stream logs and track progress
- ✅ **Auto-retry** - Automatically retry on known failures

**Examples:**
```python
# Deploy with defaults (4 nodes, 1 GPU each)
deploy_training_job(cluster_name="my-cluster")

# Deploy Llama 3.2 1B on 4 nodes
deploy_training_job(
    job_name="llama32-1b-training",
    num_nodes=4,
    instance_type="ml.g5.8xlarge",
    cluster_name="my-cluster",
    monitor=True
)

# Deploy with HuggingFace token for gated model
deploy_training_job(
    job_name="llama3-8b-training",
    num_nodes=8,
    gpu_per_node=2,
    cluster_name="my-cluster",
    hf_token="hf_...",
    monitor=True
)

# Deploy with custom torchrun path
deploy_training_job(
    job_name="custom-training",
    num_nodes=2,
    torchrun_path="/usr/local/bin/torchrun",
    cluster_name="my-cluster"
)
```

## Torchrun Configuration

The training job deployer automatically configures torchrun for distributed training:

### Environment Variables (Auto-set by PyTorchJob)
- `RANK` - Global rank of the worker
- `WORLD_SIZE` - Total number of workers
- `MASTER_ADDR` - Address of the master node
- `MASTER_PORT` - Port for communication

### Torchrun Arguments (Auto-generated)
```bash
torchrun \
  --nproc_per_node=1 \
  --nnodes=4 \
  --node_rank=$(RANK) \
  --master_addr=$(MASTER_ADDR) \
  --master_port=$(MASTER_PORT) \
  --rdzv_id=job-fsdp-training \
  --rdzv_backend=c10d \
  --rdzv_endpoint=$(MASTER_ADDR):$(MASTER_PORT) \
  /fsdp/train.py \
  --model_type=llama_v3 \
  --max_steps=100 \
  ...
```

### Training Script Requirements
Your training script should use environment variables for distributed initialization:

```python
import torch.distributed as dist
import os

# PyTorchJob sets these automatically
dist.init_process_group(
    backend='nccl',
    rank=int(os.environ['RANK']),
    world_size=int(os.environ['WORLD_SIZE'])
)
```

## Complete Workflow Example

```python
# 1. Build Docker image
build_docker_image(auto_fix=True)

# 2. Validate EKS cluster
manage_eks_cluster(
    cluster_name="sagemaker-test-cluster",
    auto_fix=True
)

# 3. Deploy training job
deploy_training_job(
    job_name="llama32-1b-training",
    num_nodes=4,
    instance_type="ml.g5.8xlarge",
    cluster_name="sagemaker-test-cluster",
    monitor=True,
    auto_retry=True
)

# 4. Check job status (in another session)
# kubectl get pytorchjobs
# kubectl logs -f llama32-1b-training-worker-0
```

## Training Results

Example output from a successful training run:

```
✅ Job deployed: llama32-1b-training
   Image: 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:llama32-1b-final
   Nodes: 4 x ml.g5.8xlarge
   GPUs: 4 nodes x 1 GPUs = 4 total GPUs
   Torchrun: /opt/conda/bin/torchrun

📊 Monitoring started...
Batch 0 Loss: 12.21, Speed: 0.67 samples/sec
Batch 50 Loss: 7.84, Speed: 0.67 samples/sec
Batch 99 Loss: 6.87, Speed: 0.66 samples/sec
Validation loss: 7.33
Checkpoint saved to /checkpoints/llama_v3-100steps
```

## Installation

These commands are automatically available when using Claude Code in a project that includes this directory.

### Prerequisites

```bash
# Install AWS CLI
pip install awscli

# Install kubectl
brew install kubectl  # macOS
# or
curl -LO "https://dl.k8s/release/$(curl -L -s https://dl.k8s/release/stable.txt)/bin/linux/amd64/kubectl"

# Configure AWS
aws configure

# Update kubeconfig for your cluster
aws eks update-kubeconfig --region us-west-2 --name your-cluster-name
```

### Verify Setup

```bash
# Test AWS access
aws sts get-caller-identity

# Test kubectl access
kubectl get nodes

# Test ECR access
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin your-account.dkr.ecr.us-west-2.amazonaws.com
```

## Configuration

Set environment variables:

```bash
export AWS_REGION=us-west-2
export AWS_PROFILE=default
export ECR_REPOSITORY=fsdp
export EKS_CLUSTER_NAME=your-cluster-name
```

## Troubleshooting

### Command not found
Make sure the `claude-commands` directory is in your project root and Claude Code has indexed it.

### AWS credentials error
Run `aws configure` to set up your AWS credentials.

### Docker not found
Ensure Docker is installed and running: `docker --version`

### kubectl not found
Install kubectl: https://kubernetes.io/docs/tasks/tools/

### ImagePullBackOff error
- Verify image exists in ECR: `aws ecr describe-images --repository-name fsdp`
- Check ECR login: `aws ecr get-login-password | docker login...`
- Verify image URI is correct

### CrashLoopBackOff error
- Check logs: `kubectl logs <pod-name>`
- Common issues:
  - Missing HuggingFace token for gated models
  - CUDA/PyTorch version mismatch
  - Insufficient GPU resources

### NCCL errors
- Verify EFA is enabled on nodes: `kubectl get nodes -o yaml | grep efa`
- Check NCCL_DEBUG logs: Set `NCCL_DEBUG=INFO` in env vars
- Ensure all nodes can communicate: Check security groups

### Training not starting
- Verify PyTorchJob CRD is installed: `kubectl get crd | grep pytorchjob`
- Check training-operator is running: `kubectl get pods -n kubeflow`
- Verify resource quotas: `kubectl describe resourcequota`

## Dependencies

- Python 3.8+
- AWS CLI
- Docker
- kubectl
- boto3
- pyyaml

## Architecture

```
┌─────────────────┐
│  Claude Code    │
│   Commands      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│  Job Deployer   │────▶│  K8s Client     │
│   (torchrun)    │     │  (kubectl)      │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  Manifest Gen   │     │  EKS Cluster    │
│  (PyTorchJob)   │     │                 │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
               ┌────────┐  ┌────────┐  ┌────────┐
               │Worker 0│  │Worker 1│  │Worker N│
               │(Master)│  │        │  │        │
               └────────┘  └────────┘  └────────┘
```

## License

MIT
