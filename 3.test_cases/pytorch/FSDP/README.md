# PyTorch FSDP Training on EKS with Automated Deployment

This repository provides a complete solution for distributed PyTorch FSDP training on Amazon EKS (Elastic Kubernetes Service) with automated deployment using Claude Code commands and opencode skills.

## 🚀 Quick Start

Deploy a training job in 3 simple steps:

```bash
# 1. Build Docker image
python claude-commands/build_image.py --auto_fix

# 2. Deploy training job
python claude-commands/deploy_training_job.py \
  --cluster_name your-cluster \
  --num_nodes 4 \
  --job_name llama32-1b-training

# 3. Monitor training
kubectl logs -f llama32-1b-training-worker-0
```

Or using Claude Code interactively:

```python
# Build and deploy
build_docker_image(auto_fix=True)
deploy_training_job(
    cluster_name="your-cluster",
    num_nodes=4,
    job_name="llama32-1b-training",
    monitor=True
)
```

## 📋 What's Included

### 🤖 Automated Tools

- **Claude Code Commands** (`claude-commands/`)
  - `build_docker_image` - Build images with auto-fix for PyTorch/CUDA conflicts
  - `deploy_training_job` - Deploy distributed training with torchrun
  - `manage_eks_cluster` - Validate and manage EKS clusters

- **opencode Skills** (`opencode/skills/`)
  - `docker-image-builder` - Automated Docker image building
  - `training-job-deployer` - PyTorchJob deployment with torchrun
  - `eks-cluster-manager` - EKS cluster validation and management
  - `shared/` - Common utilities (K8s client, logger, etc.)

### 🎯 Key Features

✅ **Automatic torchrun Configuration** - No manual distributed setup  
✅ **PyTorchJob Integration** - Native Kubeflow support  
✅ **Multi-Node Training** - Scale from 1 to 100+ nodes  
✅ **Auto-Retry on Failures** - Intelligent retry with fixes  
✅ **Real-Time Monitoring** - Stream logs and track progress  
✅ **Checkpoint Persistence** - Automatic checkpoint management  
✅ **HuggingFace Integration** - Support for gated models  

## 📚 Documentation

- **[USAGE.md](USAGE.md)** - Complete step-by-step guide with examples
- **[claude-commands/README.md](claude-commands/README.md)** - Command reference
- **[Test Results](TEST_RESULTS.md)** - Example training run results

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Development Environment                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Claude Code Commands / opencode Skills      │   │
│  │                                                     │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────┐   │   │
│  │  │Build Image   │ │Deploy Job    │ │Manage    │   │   │
│  │  │              │ │              │ │Cluster   │   │   │
│  │  └──────────────┘ └──────────────┘ └──────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      AWS Infrastructure                      │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────┐  │
│  │     ECR      │      │     EKS      │      │   FSx    │  │
│  │   (Images)   │      │  (Cluster)   │      │(Storage) │  │
│  └──────────────┘      └──────────────┘      └──────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    EKS Cluster (GPU Nodes)                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              PyTorchJob (Kubeflow)                   │   │
│  │                                                      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │   │
│  │  │Worker 0 │  │Worker 1 │  │Worker 2 │  │Worker 3│ │   │
│  │  │(Master) │  │         │  │         │  │        │ │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 🎓 Supported Models

- **Llama 3.2** (1B, 3B) - Meta's latest small language models
- **Llama 3.1** (8B, 70B, 405B) - State-of-the-art open models
- **Llama 2** (7B, 13B, 70B) - Previous generation
- **Mixtral 8x7B** - Mixture of Experts model
- **Mistral 7B** - Efficient 7B parameter model
- **Custom Models** - Any HuggingFace transformers model

## 📊 Example Training Results

**Llama 3.2 1B on 4x ml.g5.8xlarge:**

```
Configuration:
- Nodes: 4 x ml.g5.8xlarge (NVIDIA A10G GPUs)
- GPUs: 4 total (1 per node)
- Training: 100 steps
- Dataset: allenai/c4
- Duration: ~17 minutes

Results:
- Initial Loss: 12.21
- Final Loss: 6.87 (43% reduction)
- Validation Loss: 7.33
- Speed: 0.67 samples/sec
- Checkpoint: /checkpoints/llama_v3-100steps
```

## 🛠️ Prerequisites

### Required Tools

```bash
# AWS CLI
pip install awscli
aws configure

# Docker
# https://docs.docker.com/get-docker/

# kubectl
brew install kubectl  # macOS
# OR download from https://kubernetes.io/docs/tasks/tools/

# Python dependencies
pip install boto3 pyyaml
```

### AWS Resources

- **ECR Repository** - For Docker images
- **EKS Cluster** - With GPU nodes (ml.g5 family)
- **IAM Permissions** - ECR push/pull, EKS access

See [USAGE.md](USAGE.md) for detailed setup instructions.

## 🚦 Usage Examples

### Basic Training

```python
deploy_training_job(
    cluster_name="my-cluster",
    num_nodes=4,
    job_name="basic-training"
)
```

### Custom Configuration

```python
deploy_training_job(
    job_name="llama3-8b-training",
    image_uri="123456789.dkr.ecr.us-west-2.amazonaws.com/fsdp:custom",
    num_nodes=8,
    gpu_per_node=2,
    instance_type="ml.g5.12xlarge",
    cluster_name="my-cluster",
    max_steps=1000,
    monitor=True
)
```

### Gated Model (Requires HF Token)

```python
deploy_training_job(
    job_name="llama3-gated",
    num_nodes=4,
    cluster_name="my-cluster",
    hf_token="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    tokenizer="meta-llama/Llama-3.2-1B"
)
```

## 🔧 Advanced Features

### Automatic torchrun Configuration

The deployment automatically configures torchrun for distributed training:

```bash
torchrun \
  --nproc_per_node=1 \
  --nnodes=4 \
  --node_rank=$(RANK) \
  --master_addr=$(MASTER_ADDR) \
  --master_port=$(MASTER_PORT) \
  --rdzv_backend=c10d \
  /fsdp/train.py \
  --model_type=llama_v3 \
  --max_steps=100
```

### Checkpoint Management

Checkpoints are automatically saved to `/checkpoints/` and persisted to the host:

```bash
# List checkpoints
kubectl exec -it training-worker-0 -- ls -la /checkpoints/

# Download checkpoints
kubectl cp training-worker-0:/checkpoints/ ./local-checkpoints/
```

### Monitoring & Debugging

```bash
# Check job status
kubectl get pytorchjobs

# View logs
kubectl logs -f training-worker-0

# Check GPU utilization
kubectl exec -it training-worker-0 -- nvidia-smi

# Describe pod
kubectl describe pod training-worker-0
```

## 📁 Repository Structure

```
.
├── claude-commands/          # Claude Code compatible commands
│   ├── build_image.py       # Build Docker images
│   ├── deploy_training_job.py # Deploy training jobs
│   ├── manage_eks_cluster.py # Manage EKS clusters
│   └── README.md            # Command documentation
│
├── opencode/skills/         # opencode skills
│   ├── docker-image-builder/
│   ├── training-job-deployer/
│   ├── eks-cluster-manager/
│   └── shared/              # Shared utilities
│
├── src/                     # Training source code
│   ├── train.py            # Main training script
│   └── model_utils/        # Model utilities
│
├── kubernetes/              # Kubernetes manifests
├── slurm/                   # Slurm configurations
├── models/                  # Model definitions
├── Dockerfile              # Docker image definition
├── README.md               # This file
└── USAGE.md               # Complete usage guide
```

## 🐛 Troubleshooting

See [USAGE.md#troubleshooting](USAGE.md#troubleshooting) for detailed troubleshooting guide.

Common issues:
- **ImagePullBackOff** - ECR login or image URI mismatch
- **CrashLoopBackOff** - Missing HF token or CUDA mismatch
- **NCCL errors** - EFA/network configuration issues
- **Slow training** - Check GPU utilization and EFA usage

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

- PyTorch FSDP team for the distributed training framework
- Kubeflow team for PyTorchJob
- AWS for EKS and SageMaker HyperPod
- HuggingFace for transformers library

---

**Ready to start training?** Check out [USAGE.md](USAGE.md) for the complete guide!
