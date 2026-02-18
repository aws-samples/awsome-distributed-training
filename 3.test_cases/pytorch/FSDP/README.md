# Get Started Training Llama 2, Mixtral 8x7B, and Mistral Mathstral with PyTorch FSDP in 5 Minutes

This content provides a quickstart with multinode PyTorch [FSDP](https://pytorch.org/tutorials/intermediate/FSDP_tutorial.html) training on Slurm and Kubernetes.
It is designed to be simple with no data preparation or tokenizer to download, and uses Python virtual environment.

## Prerequisites

To run FSDP training, you will need to create a training cluster based on Slurm or Kubermetes with an [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/what-is.html)
You can find instruction how to create a Amazon SageMaker Hyperpod cluster with [Slurm](https://catalog.workshops.aws/sagemaker-hyperpod/en-US), [Kubernetes](https://catalog.workshops.aws/sagemaker-hyperpod-eks/en-US) or with in [Amazon EKS](../../1.architectures).

## FSDP Training

This fold provides examples on how to train with PyTorch FSDP with Slurm or Kubernetes.
You will find instructions for [Slurm](slurm) or [Kubernetes](kubernetes) in the subdirectories.

---

## Automated EKS Deployment (OpenCode / Claude Code)

In addition to the manual Slurm and Kubernetes workflows above, this directory includes automated tooling for deploying FSDP training on Amazon EKS using OpenCode skills and Claude Code commands. These live one level up at `pytorch/opencode/skills/` and `pytorch/claude-commands/`.

See [USAGE.md](USAGE.md) for the complete step-by-step guide.

### Quick Start

```bash
# Build Docker image (auto-detects local Docker or falls back to CodeBuild)
python3 ../opencode/skills/docker-image-builder/src/build_image.py --context .

# Deploy training job to EKS
python3 ../claude-commands/deploy_training_job.py \
  --cluster_name your-cluster \
  --image_uri your-account.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --num_nodes 4
```

### What's Available

| Tool | Location | Description |
|------|----------|-------------|
| Docker Image Builder | `../opencode/skills/docker-image-builder/` | Build images with auto-fix (local Docker or CodeBuild) |
| Docker Image Tester | `../opencode/skills/docker-image-tester/` | Test images (import validation, CUDA checks) |
| ECR Image Pusher | `../opencode/skills/ecr-image-pusher/` | Push images to Amazon ECR |
| EKS Cluster Manager | `../opencode/skills/eks-cluster-manager/` | Discover, validate, manage EKS clusters |
| Training Job Deployer | `../opencode/skills/training-job-deployer/` | Deploy PyTorchJob with torchrun |
| PyTorchJob Manager | `../opencode/skills/pytorchjob-manager/` | CRUD for PyTorchJob resources |
| Training Monitor | `../opencode/skills/training-monitor/` | Monitor jobs with auto-restart |

### Example Training Results

Llama 3.2 1B on 4x ml.g5.8xlarge (EKS):
- 100 steps, loss reduced from 12.21 to 6.87 (43% reduction)
- Validation loss: 7.33
- Duration: ~17 minutes
- Checkpoint saved to `/checkpoints/llama_v3-100steps`
