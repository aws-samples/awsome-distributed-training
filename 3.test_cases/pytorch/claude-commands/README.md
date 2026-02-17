# Claude Code Commands for PyTorch FSDP

This directory contains Claude Code compatible commands for managing Docker images, EKS clusters, and training jobs for PyTorch FSDP workloads with automatic torchrun configuration for distributed training.

## Available Commands

### Command Overview

| Command | Purpose | Key Features |
|---------|---------|--------------|
| `build_docker_image` | Build Docker images | Auto-conflict detection, multi-attempt builds |
| `test_docker_image` | Test Docker images | CodeBuild/local testing, multiple test levels |
| `manage_eks_cluster` | Manage EKS clusters | Auto-discovery, validation, auto-fix |
| `deploy_training_job` | Deploy training jobs | PyTorchJob/Ray support, auto-monitoring |
| `manage_pytorchjob` | Manage PyTorchJobs | CRUD operations, status monitoring |
| `monitor_training` | Monitor training jobs | Real-time logs, metrics collection |

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

### 2. test_docker_image
Test Docker images using CodeBuild (default - no local Docker required) or local Docker.

```python
test_docker_image(
    image="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest",
    level="standard",              # quick, standard, or full
    codebuild_project="pytorch-fsdp",
    region="us-west-2",
    use_codebuild=True,            # Use CodeBuild (default)
    wait=True,                     # Wait for completion
    timeout=600                    # Timeout in seconds
)
```

**Test Levels:**
- **quick** (~2-3 min): Basic imports only
- **standard** (~5-7 min): Imports + CUDA + model config
- **full** (~10-15 min): All tests including model loading

**Example:**
```python
# Quick test
 test_docker_image(
    image="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest",
    level="quick"
)

# Standard test with monitoring
test_docker_image(
    image="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest",
    level="standard",
    wait=True
)

# Full test
 test_docker_image(
    image="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest",
    level="full"
)
```

### 3. manage_eks_cluster
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

### 4. deploy_training_job
Deploy distributed training jobs to EKS using PyTorchJob (torchrun) or Ray (KubeRay).

```python
deploy_training_job(
    job_name="fsdp-training",
    image_uri=None,              # Auto-detect from ECR
    instance_type="ml.g5.8xlarge",
    num_nodes=4,                 # Number of nodes for distributed training
    gpu_per_node=1,              # GPUs per node
    cluster_name="my-cluster",   # Required
    torchrun_path="/opt/conda/bin/torchrun",  # Path to torchrun
    use_ray=False,               # Use Ray (KubeRay) instead of PyTorchJob
    install_ray=False,           # Install KubeRay operator if not present
    monitor=True,                # Real-time monitoring
    auto_retry=True,             # Auto-retry on failures
    hf_token=None                # HuggingFace token for gated models
)
```

**Deployment Options:**

**Option 1: PyTorchJob (Default)**
- Uses torchrun for distributed training
- Kubeflow PyTorchJob for orchestration
- Best for standard PyTorch FSDP workloads

**Option 2: Ray (KubeRay)**
- Uses Ray for distributed training
- Alternative to PyTorchJob
- Best for Ray-based workloads and hyperparameter tuning

**Key Features:**
- ✅ **PyTorchJob or Ray** - Choose your distributed framework
- ✅ **Automatic torchrun configuration** - No manual distributed setup needed
- ✅ **KubeRay integration** - Ray support with auto-installation
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

# Deploy using Ray (KubeRay)
deploy_training_job(
    job_name="ray-training",
    num_nodes=4,
    cluster_name="my-cluster",
    use_ray=True,
    install_ray=True  # Install KubeRay if not present
)
```

### 5. manage_pytorchjob
Manage PyTorchJobs with operations for create, delete, list, and status monitoring.

```python
manage_pytorchjob(
    action="list",                 # create, delete, list, status
    job_name=None,                 # Required for create/delete/status
    namespace="default",
    image_uri=None,                # Required for create
    instance_type="ml.g5.8xlarge", # Required for create
    num_nodes=4,                   # Required for create
    gpu_per_node=1,                # Required for create
    cluster_name=None,             # Required for create
    torchrun_path="/opt/conda/bin/torchrun",
    hf_token=None,
    wait=False,                    # Wait for job completion
    timeout=3600                   # Timeout in seconds
)
```

**Actions:**
- **create** - Create a new PyTorchJob
- **delete** - Delete an existing PyTorchJob
- **list** - List all PyTorchJobs in namespace
- **status** - Get detailed status of a specific job

**Key Features:**
- ✅ **CRUD operations** - Full lifecycle management of PyTorchJobs
- ✅ **Auto-discovery** - Auto-detect cluster and image if not specified
- ✅ **Status monitoring** - Real-time status with pod conditions
- ✅ **Namespace support** - Work across different Kubernetes namespaces
- ✅ **Resource validation** - Validate resources before job creation

**Examples:**
```python
# List all PyTorchJobs
manage_pytorchjob(action="list")

# Create a new PyTorchJob
manage_pytorchjob(
    action="create",
    job_name="my-training-job",
    image_uri="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest",
    instance_type="ml.g5.8xlarge",
    num_nodes=4,
    cluster_name="my-cluster",
    wait=True
)

# Get job status
manage_pytorchjob(
    action="status",
    job_name="my-training-job"
)

# Delete a job
manage_pytorchjob(
    action="delete",
    job_name="my-training-job"
)

# Create with HuggingFace token
manage_pytorchjob(
    action="create",
    job_name="llama-training",
    num_nodes=8,
    hf_token="hf_...",
    wait=True
)
```

### 6. monitor_training
Monitor training jobs with real-time logs, metrics tracking, and status updates.

```python
monitor_training(
    job_name,                      # Required: Job to monitor
    namespace="default",
    follow_logs=True,              # Stream logs in real-time
    metrics_interval=10,           # Metrics collection interval (seconds)
    timeout=None,                  # Monitoring timeout (None = indefinite)
    save_metrics=True,             # Save metrics to file
    metrics_file=None,             # Custom metrics file path
    alert_on_failure=True          # Alert when job fails
)
```

**Key Features:**
- ✅ **Real-time log streaming** - Live logs from all worker pods
- ✅ **Metrics collection** - Track loss, throughput, GPU utilization
- ✅ **Multi-pod monitoring** - Monitor all workers simultaneously
- ✅ **Persistent metrics** - Save training metrics to JSON/CSV
- ✅ **Failure detection** - Automatic alerts on job failures
- ✅ **Resource tracking** - Monitor CPU, memory, GPU usage

**Metrics Tracked:**
- Training loss (per batch and epoch)
- Samples per second (throughput)
- GPU utilization (if nvidia-smi available)
- Memory usage
- Job phase transitions
- Pod status and conditions

**Examples:**
```python
# Basic monitoring with log streaming
monitor_training(job_name="my-training-job")

# Monitor with custom timeout and metrics saving
monitor_training(
    job_name="my-training-job",
    timeout=3600,
    save_metrics=True,
    metrics_file="./training_metrics.json"
)

# Monitor without log streaming (metrics only)
monitor_training(
    job_name="my-training-job",
    follow_logs=False,
    metrics_interval=30
)

# Monitor with alerts disabled
monitor_training(
    job_name="my-training-job",
    alert_on_failure=False
)
```

## Sub-Skills Integration

The `deploy_training_job` command now integrates with sub-skills for enhanced functionality:

### Integration with manage_pytorchjob
When deploying a training job, `deploy_training_job` can leverage `manage_pytorchjob` for:
- **Pre-deployment validation** - Verify cluster resources and image availability
- **Job lifecycle management** - Create, monitor, and cleanup jobs
- **Status checking** - Validate job status before and after deployment

### Integration with monitor_training
After deployment, `deploy_training_job` automatically invokes `monitor_training` when `monitor=True`:
- **Seamless monitoring** - No separate monitoring command needed
- **Automatic metrics collection** - Training metrics captured from start
- **Failure detection** - Immediate alerts if deployment fails

### Usage with Sub-Skills
```python
# Deploy with automatic monitoring (uses monitor_training sub-skill)
deploy_training_job(
    job_name="llama32-1b-training",
    num_nodes=4,
    cluster_name="my-cluster",
    monitor=True  # Automatically invokes monitor_training
)

# Deploy then manually manage with manage_pytorchjob
deploy_training_job(
    job_name="llama32-1b-training",
    num_nodes=4,
    cluster_name="my-cluster",
    monitor=False  # Skip auto-monitoring
)

# Later: Check status using manage_pytorchjob
manage_pytorchjob(action="status", job_name="llama32-1b-training")

# Later: Monitor manually using monitor_training
monitor_training(
    job_name="llama32-1b-training",
    follow_logs=True,
    save_metrics=True
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

### Basic Workflow
```python
# 1. Build Docker image
build_docker_image(auto_fix=True)

# 2. Validate EKS cluster
manage_eks_cluster(
    cluster_name="sagemaker-test-cluster",
    auto_fix=True
)

# 3. Deploy training job with monitoring
deploy_training_job(
    job_name="llama32-1b-training",
    num_nodes=4,
    instance_type="ml.g5.8xlarge",
    cluster_name="sagemaker-test-cluster",
    monitor=True,
    auto_retry=True
)
```

### Advanced Workflow with Sub-Skills
```python
# 1. Build and test Docker image
build_docker_image(auto_fix=True)
test_docker_image(level="standard", wait=True)

# 2. Validate EKS cluster
manage_eks_cluster(
    cluster_name="sagemaker-test-cluster",
    auto_fix=True
)

# 3. Create PyTorchJob using manage_pytorchjob
manage_pytorchjob(
    action="create",
    job_name="llama32-1b-training",
    image_uri="975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest",
    instance_type="ml.g5.8xlarge",
    num_nodes=4,
    cluster_name="sagemaker-test-cluster",
    hf_token="hf_...",
    wait=False  # Don't wait, we'll monitor separately
)

# 4. Monitor training with metrics collection
monitor_training(
    job_name="llama32-1b-training",
    follow_logs=True,
    save_metrics=True,
    metrics_file="./llama32_1b_metrics.json",
    timeout=7200  # 2 hour timeout
)

# 5. Check job status anytime
manage_pytorchjob(action="status", job_name="llama32-1b-training")

# 6. List all jobs
manage_pytorchjob(action="list")

# 7. Cleanup when done
manage_pytorchjob(action="delete", job_name="llama32-1b-training")
```

### Monitoring an Existing Job
```python
# Check status of running job
manage_pytorchjob(action="status", job_name="llama32-1b-training")

# Stream logs from running job
monitor_training(
    job_name="llama32-1b-training",
    follow_logs=True,
    metrics_interval=5
)
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
