# PyTorch FSDP Training on EKS - Complete Usage Guide

This guide covers how to use the Claude Code commands and opencode skills to deploy distributed PyTorch FSDP training jobs on Amazon EKS.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Architecture Overview](#architecture-overview)
4. [Step-by-Step Guide](#step-by-step-guide)
5. [Advanced Configuration](#advanced-configuration)
6. [Troubleshooting](#troubleshooting)
7. [Reference](#reference)

## Quick Start

Deploy a training job in 3 commands:

```bash
# 1. Build Docker image
python claude-commands/build_image.py --auto_fix

# 2. Push to ECR (auto-detected)
# Image will be pushed automatically after successful build

# 3. Deploy training job
python claude-commands/deploy_training_job.py \
  --cluster_name your-cluster-name \
  --num_nodes 4 \
  --job_name my-training
```

Or using Claude Code interactively:

```python
# Build image
build_docker_image(auto_fix=True)

# Deploy job
deploy_training_job(
    cluster_name="your-cluster-name",
    num_nodes=4,
    job_name="my-training",
    monitor=True
)
```

## Prerequisites

### 1. AWS Setup

```bash
# Install AWS CLI
pip install awscli

# Configure credentials
aws configure
# AWS Access Key ID: your-access-key
# AWS Secret Access Key: your-secret-key
# Default region: us-west-2
# Default output format: json

# Verify
aws sts get-caller-identity
```

### 2. Docker Setup

```bash
# Install Docker Desktop (Mac/Windows) or Docker Engine (Linux)
# https://docs.docker.com/get-docker/

# Verify
docker --version

# Login to ECR
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  your-account.dkr.ecr.us-west-2.amazonaws.com
```

### 3. Kubernetes Setup

```bash
# Install kubectl
brew install kubectl  # macOS
# OR
curl -LO "https://dl.k8s/release/$(curl -L -s https://dl.k8s/release/stable.txt)/bin/linux/amd64/kubectl"

# Configure for your EKS cluster
aws eks update-kubeconfig --region us-west-2 --name your-cluster-name

# Verify
kubectl get nodes
```

### 4. Python Dependencies

```bash
pip install boto3 pyyaml
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Laptop                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Claude Code / opencode                  │   │
│  │         ┌──────────┐    ┌──────────────┐           │   │
│  │         │ Commands │    │    Skills    │           │   │
│  │         └────┬─────┘    └──────┬───────┘           │   │
│  └──────────────┼─────────────────┼───────────────────┘   │
└─────────────────┼─────────────────┼───────────────────────┘
                  │                 │
                  ▼                 ▼
         ┌────────────────────────────────────┐
         │            AWS Services            │
         │  ┌──────────┐      ┌──────────┐   │
         │  │    ECR   │      │   EKS    │   │
         │  │ (Images) │      │(Cluster) │   │
         │  └────┬─────┘      └────┬─────┘   │
         └───────┼─────────────────┼─────────┘
                 │                 │
                 ▼                 ▼
        ┌──────────────────────────────────────┐
        │           EKS Cluster                │
        │  ┌──────────────────────────────┐   │
        │  │      PyTorchJob (Kubeflow)   │   │
        │  │  ┌────────┐ ┌────────┐       │   │
        │  │  │Worker 0│ │Worker 1│  ...  │   │
        │  │  │(Master)│ │        │       │   │
        │  │  └────────┘ └────────┘       │   │
        │  └──────────────────────────────┘   │
        └──────────────────────────────────────┘
```

## Step-by-Step Guide

### Step 1: Build Docker Image

The Docker image contains your training code and dependencies.

**Using Claude Code:**
```python
build_docker_image(
    dockerfile="Dockerfile",
    tag="llama32-1b-v1",
    auto_fix=True,
    max_attempts=3
)
```

**Using CLI:**
```bash
python claude-commands/build_image.py \
  --dockerfile Dockerfile \
  --tag llama32-1b-v1 \
  --auto_fix \
  --max_attempts 3
```

**What happens:**
1. Analyzes Dockerfile for PyTorch/CUDA compatibility
2. Automatically fixes version conflicts
3. Builds image with retry logic
4. Tags with semantic version

### Step 2: Push to ECR

Images are automatically pushed after successful build. To push manually:

```bash
# Get ECR login token
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  975049888767.dkr.ecr.us-west-2.amazonaws.com

# Tag image
docker tag fsdp:llama32-1b-v1 \
  975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:llama32-1b-v1

# Push
docker push 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:llama32-1b-v1
```

### Step 3: Validate EKS Cluster

**Using Claude Code:**
```python
manage_eks_cluster(
    cluster_name="sagemaker-test-cluster",
    validate_components=True,
    auto_fix=True
)
```

**Using CLI:**
```bash
python claude-commands/manage_eks_cluster.py \
  --cluster_name sagemaker-test-cluster \
  --validate_components \
  --auto_fix
```

**Validations:**
- ✅ Cluster accessibility
- ✅ NVIDIA GPU operator
- ✅ EFA (Elastic Fabric Adapter)
- ✅ Kubeflow training operator
- ✅ Node GPU availability

### Step 4: Deploy Training Job

**Using Claude Code:**
```python
deploy_training_job(
    job_name="llama32-1b-training",
    image_uri="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:llama32-1b-v1",
    num_nodes=4,
    gpu_per_node=1,
    instance_type="ml.g5.8xlarge",
    cluster_name="sagemaker-test-cluster",
    monitor=True,
    auto_retry=True
)
```

**Using CLI:**
```bash
python claude-commands/deploy_training_job.py \
  --job_name llama32-1b-training \
  --image_uri 975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:llama32-1b-v1 \
  --num_nodes 4 \
  --gpu_per_node 1 \
  --cluster_name sagemaker-test-cluster \
  --monitor
```

**What happens:**
1. Generates PyTorchJob manifest with torchrun configuration
2. Applies manifest to EKS cluster
3. Verifies pods are created
4. Streams logs for real-time monitoring
5. Switches to background monitoring after 5 minutes

### Step 5: Monitor Training

**Check job status:**
```bash
kubectl get pytorchjobs
```

**View logs:**
```bash
# Master node logs
kubectl logs -f llama32-1b-training-worker-0

# All worker logs
kubectl logs -l training.kubeflow.org/job-name=llama32-1b-training --tail=100
```

**Check resource usage:**
```bash
kubectl top pods
kubectl describe pod llama32-1b-training-worker-0
```

### Step 6: Retrieve Results

**Check checkpoints:**
```bash
# SSH to node and check checkpoint directory
kubectl exec -it llama32-1b-training-worker-0 -- ls -la /checkpoints/
```

**Download checkpoints:**
```bash
# Copy from pod to local
kubectl cp llama32-1b-training-worker-0:/checkpoints/llama_v3-100steps ./checkpoints/
```

## Advanced Configuration

### Custom Training Parameters

Edit the job configuration in `claude-commands/deploy_training_job.py`:

```python
config = {
    'job_name': job_name,
    'image_uri': image_uri,
    'instance_type': instance_type,
    'num_nodes': num_nodes,
    'gpu_per_node': gpu_per_node,
    'model_type': 'llama_v3',  # or 'llama_v2', 'gpt2', etc.
    'max_steps': 1000,         # Training steps
    'train_batch_size': 2,     # Per-device batch size
    'sharding_strategy': 'full',  # FSDP sharding: full, shard, no_shard
    'checkpoint_freq': 500,    # Save checkpoint every N steps
    'validation_freq': 100,    # Run validation every N steps
    'dataset': 'allenai/c4',   # HuggingFace dataset
    'dataset_config_name': 'en',
    'tokenizer': 'hf-internal-testing/llama-tokenizer',
    'hf_token': hf_token       # For gated models
}
```

### Multi-GPU Per Node

For instances with multiple GPUs (e.g., ml.g5.12xlarge with 4 GPUs):

```python
deploy_training_job(
    num_nodes=2,
    gpu_per_node=4,  # 4 GPUs per node
    instance_type="ml.g5.12xlarge"
)
# Total: 2 nodes × 4 GPUs = 8 GPUs
```

### Using HuggingFace Gated Models

For models like meta-llama/Llama-3.2-1B that require authentication:

```python
deploy_training_job(
    job_name="llama3-gated",
    hf_token="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",  # Your HF token
    tokenizer="meta-llama/Llama-3.2-1B",  # Gated model tokenizer
    model_type="llama_v3"
)
```

**Get HF token:**
1. Go to https://huggingface.co/settings/tokens
2. Create new token with "read" access
3. Request model access at https://huggingface.co/meta-llama/Llama-3.2-1B

### Custom Torchrun Path

If torchrun is in a different location in your image:

```python
deploy_training_job(
    torchrun_path="/usr/local/bin/torchrun",  # Custom path
    # or
    torchrun_path="/opt/conda/envs/pytorch/bin/torchrun"
)
```

### Checkpoint Persistence

Checkpoints are automatically saved to `/checkpoints/` which is mounted to the host at `/mnt/k8s-disks/0/checkpoints/`.

To customize:

```yaml
# In the PyTorchJob manifest
volumeMounts:
  - name: checkpoints
    mountPath: /custom/checkpoint/path

volumes:
  - name: checkpoints
    hostPath:
      path: /mnt/k8s-disks/0/my-checkpoints
```

## Troubleshooting

### Build Failures

**Issue:** `CUDA version mismatch`
```
# Solution: Auto-fix is enabled by default
build_docker_image(auto_fix=True)

# Or manually specify base image
build_docker_image(base_image="pytorch/pytorch:2.5.1-cuda12.4-runtime")
```

**Issue:** `Out of disk space`
```bash
# Clean up Docker
docker system prune -a

# Or increase Docker Desktop disk limit
```

### Deployment Failures

**Issue:** `ImagePullBackOff`
```bash
# Check if image exists in ECR
aws ecr describe-images --repository-name fsdp

# Re-login to ECR
aws ecr get-login-password --region us-west-2 | docker login...

# Verify image URI matches exactly
```

**Issue:** `Insufficient resources`
```bash
# Check available GPUs
kubectl get nodes -o yaml | grep nvidia.com/gpu

# Check node status
kubectl describe nodes

# Scale cluster if needed
aws eks update-nodegroup-config \
  --cluster-name your-cluster \
  --nodegroup-name your-nodegroup \
  --scaling-config minSize=4,maxSize=10,desiredSize=4
```

**Issue:** `CrashLoopBackOff`
```bash
# Check logs
kubectl logs llama32-1b-training-worker-0 --previous

# Common causes:
# - Missing HF token for gated models
# - CUDA/PyTorch version mismatch
# - Out of memory (reduce batch size)
```

### Training Failures

**Issue:** `NCCL errors`
```bash
# Check EFA is enabled
kubectl get nodes -o yaml | grep vpc.amazonaws.com/efa

# Check security groups allow inter-node communication
# Verify nodes are in same VPC/subnet

# Set debug logging
export NCCL_DEBUG=INFO
```

**Issue:** `Loss is NaN`
```python
# Reduce learning rate
config['learning_rate'] = 1e-5

# Enable gradient clipping
config['max_grad_norm'] = 1.0

# Check for numerical instability in model
```

**Issue:** `Slow training speed`
```bash
# Check GPU utilization
kubectl exec -it llama32-1b-training-worker-0 -- nvidia-smi

# Verify EFA is being used (not fallback to TCP)
kubectl logs llama32-1b-training-worker-0 | grep -i "efa\|socket"

# Increase batch size if memory allows
config['train_batch_size'] = 4
```

### Monitoring Issues

**Issue:** `Can't view logs`
```bash
# Check pod status
kubectl get pods -l training.kubeflow.org/job-name=llama32-1b-training

# Get logs from specific container
kubectl logs llama32-1b-training-worker-0 -c pytorch

# Stream logs from all workers
kubectl logs -f -l training.kubeflow.org/job-name=llama32-1b-training
```

## Reference

### Environment Variables

Set these in your shell or `.env` file:

```bash
export AWS_REGION=us-west-2
export AWS_PROFILE=default
export ECR_REPOSITORY=fsdp
export EKS_CLUSTER_NAME=sagemaker-test-cluster
export HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # Optional
```

### Instance Types

| Instance Type | GPUs | GPU Memory | vCPU | Memory | Best For |
|--------------|------|------------|------|--------|----------|
| ml.g5.xlarge | 1 | 24 GB | 4 | 16 GB | Testing |
| ml.g5.2xlarge | 1 | 24 GB | 8 | 32 GB | Small models |
| ml.g5.4xlarge | 1 | 24 GB | 16 | 64 GB | Medium models |
| ml.g5.8xlarge | 1 | 24 GB | 32 | 128 GB | Large models |
| ml.g5.12xlarge | 4 | 96 GB | 48 | 192 GB | Multi-GPU |
| ml.g5.16xlarge | 1 | 24 GB | 64 | 256 GB | Memory-intensive |
| ml.g5.24xlarge | 4 | 96 GB | 96 | 384 GB | Large-scale |
| ml.g5.48xlarge | 8 | 192 GB | 192 | 768 GB | Massive scale |

### Model Configurations

**Llama 3.2 1B:**
```python
config = {
    'model_type': 'llama_v3',
    'hidden_width': 2048,
    'num_layers': 16,
    'num_heads': 32,
    'intermediate_size': 8192,
    'num_key_value_heads': 8,
    'max_context_width': 2048
}
```

**Llama 3.2 3B:**
```python
config = {
    'model_type': 'llama_v3',
    'hidden_width': 3072,
    'num_layers': 28,
    'num_heads': 24,
    'intermediate_size': 8192,
    'num_key_value_heads': 8,
    'max_context_width': 4096
}
```

**Llama 3.1 8B:**
```python
config = {
    'model_type': 'llama_v3',
    'hidden_width': 4096,
    'num_layers': 32,
    'num_heads': 32,
    'intermediate_size': 14336,
    'num_key_value_heads': 8,
    'max_context_width': 8192
}
```

### Useful Commands

```bash
# List all PyTorchJobs
kubectl get pytorchjobs -o wide

# Describe job details
kubectl describe pytorchjob llama32-1b-training

# Delete job
kubectl delete pytorchjob llama32-1b-training

# Get pod details
kubectl describe pod llama32-1b-training-worker-0

# Execute command in pod
kubectl exec -it llama32-1b-training-worker-0 -- /bin/bash

# Copy files from pod
kubectl cp llama32-1b-training-worker-0:/checkpoints ./local-checkpoints

# Watch resources
kubectl top nodes
kubectl top pods

# Check events
kubectl get events --sort-by='.lastTimestamp'
```

### File Structure

```
.
├── claude-commands/           # Claude Code commands
│   ├── build_image.py        # Build Docker images
│   ├── deploy_training_job.py # Deploy training jobs
│   ├── manage_eks_cluster.py  # Manage EKS clusters
│   └── README.md             # Command documentation
├── opencode/skills/          # opencode skills
│   ├── docker-image-builder/ # Image building skill
│   ├── training-job-deployer/ # Job deployment skill
│   ├── eks-cluster-manager/  # Cluster management skill
│   └── shared/               # Shared utilities
├── src/                      # Training source code
│   ├── train.py             # Main training script
│   └── model_utils/         # Model utilities
├── Dockerfile               # Docker image definition
└── USAGE.md                 # This file
```

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review the [claude-commands/README.md](claude-commands/README.md)
3. Check Kubernetes logs: `kubectl logs <pod-name>`
4. Open an issue in the repository

## License

MIT License - See LICENSE file for details
