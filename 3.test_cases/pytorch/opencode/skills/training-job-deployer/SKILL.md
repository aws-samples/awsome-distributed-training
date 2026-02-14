---
name: training-job-deployer
description: Deploy distributed training jobs on EKS with support for PyTorchJob (torchrun) and Ray (KubeRay). Includes automatic Ray installation, real-time monitoring, and auto-retry capabilities.
license: MIT
compatibility: opencode
metadata:
  category: deployment
  author: opencode
---

## What I do

Deploy distributed training jobs on EKS with multiple framework support:

1. **PyTorchJob (torchrun)**: Native Kubeflow PyTorchJob for distributed training
2. **Ray (KubeRay)**: Ray-based distributed training with automatic KubeRay installation
3. **Auto-Install Ray**: Automatically install KubeRay operator if not present
4. **Real-Time Monitoring**: Stream logs and track progress
5. **Auto-Retry**: Automatically retry on known failures
6. **Multi-Framework**: Support for both torchrun and Ray backends

## When to use me

Use this skill when you need to:
- Deploy distributed training jobs on EKS
- Run PyTorch FSDP training with torchrun
- Run VERL/Ray-based training (e.g., GRPO, PPO)
- Automatically install KubeRay if not present
- Monitor training progress in real-time
- Handle training failures automatically

## How to use me

### Command Line

#### Deploy with PyTorchJob (torchrun) - Default
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --image_uri 123456789.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest \
  --num_nodes 4 \
  --job_name llama32-1b-training \
  --monitor
```

#### Deploy with Ray (KubeRay)
```bash
# Check if Ray is installed and install if needed
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --image_uri 123456789.dkr.ecr.us-west-2.amazonaws.com/verl:latest \
  --num_nodes 4 \
  --job_name verl-grpo-training \
  --use_ray \
  --install_ray \
  --monitor
```

#### Deploy VERL training (Ray-based)
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name sagemaker-test-cluster-eks-try2-3a6aa148-eks \
  --image_uri 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest \
  --num_nodes 2 \
  --job_name verl-test \
  --use_ray \
  --install_ray \
  --monitor
```

### Python API
```python
from training_job_deployer.src.deploy_job import check_ray_installed, install_kuberay
from training_job_deployer.src.deploy_job import main as deploy_job

# Check and install Ray if needed
if not check_ray_installed('my-cluster'):
    install_kuberay('my-cluster')

# Deploy Ray-based training
deploy_job([
    '--cluster_name', 'my-cluster',
    '--image_uri', '123456789.dkr.ecr.us-west-2.amazonaws.com/verl:latest',
    '--num_nodes', '4',
    '--use_ray',
    '--monitor'
])
```

## Features

### PyTorchJob (torchrun) Features
- **torchrun Integration**: Automatic distributed setup
- **PyTorchJob**: Native Kubeflow support
- **Multi-GPU**: Support for multiple GPUs per node
- **HuggingFace**: Token support for gated models

### Ray (KubeRay) Features
- **Auto-Install**: Automatically install KubeRay operator
- **RayCluster**: Deploy Ray clusters on EKS
- **VERL Support**: Optimized for VERL training (GRPO, PPO)
- **Ray Dashboard**: Access to Ray dashboard for monitoring
- **Memory Optimization**: Shared memory (shm) volumes for Ray

### Common Features
- **Monitoring**: Real-time log streaming
- **Auto-Retry**: Intelligent failure recovery
- **Multi-Node**: Scale from 1 to 100+ nodes
- **Checkpointing**: Automatic checkpoint volume mounting

## Parameters

### Required Parameters
- `--cluster_name`: EKS cluster name (required)
- `--image_uri`: Docker image URI

### Training Configuration
- `--job_name`: Name for the training job (default: "fsdp-training")
- `--num_nodes`: Number of nodes for distributed training (default: 4)
- `--gpu_per_node`: GPUs per node (default: 1)
- `--instance_type`: EC2 instance type (default: "ml.g5.8xlarge")

### Framework Selection
- `--use_ray`: Use Ray (KubeRay) instead of PyTorchJob
- `--install_ray`: Install KubeRay operator if not present
- `--ray_address`: Ray cluster address (default: "auto")

### PyTorchJob Specific
- `--torchrun_path`: Path to torchrun (default: "/opt/conda/bin/torchrun")
- `--use_hyperpod_cli`: Use HyperPod CLI: auto, true, or false (default: "auto")

### Monitoring & Retry
- `--monitor`: Monitor job after deployment (default: true)
- `--auto_retry`: Auto-retry on failures (default: true)
- `--save_config`: Save config to ConfigMap (default: true)

### Authentication
- `--hf_token`: HuggingFace token for gated models
- `--sns_topic`: SNS topic ARN for notifications

## Tested Images

### PyTorch FSDP
- Image: `975049888767.dkr.ecr.us-west-2.amazonaws.com/fsdp:latest`
- Framework: PyTorchJob with torchrun
- Use case: LLM training with FSDP

### VERL RLVR
- Image: `975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest`
- Framework: Ray (KubeRay)
- Use case: RLVR training (GRPO, PPO)
- Entry point: `python3 -m verl.trainer.main_ppo`

## Monitoring

### PyTorchJob
```bash
# Check job status
kubectl get pytorchjob <job-name>

# View master logs
kubectl logs -f <job-name>-worker-0

# Check all workers
kubectl logs -l training.kubeflow.org/job-name=<job-name>
```

### Ray Cluster
```bash
# Check Ray cluster status
kubectl get raycluster <job-name>

# View head node logs
kubectl logs -f <job-name>-head-xxxxx

# Access Ray Dashboard
kubectl port-forward svc/<job-name>-head-svc 8265:8265
# Then open http://localhost:8265 in browser

# Check all Ray pods
kubectl get pods -l ray.io/cluster=<job-name>
```

## Examples

### Basic PyTorchJob Deployment
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4
```

### Ray-based VERL Training
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --image_uri 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest \
  --num_nodes 4 \
  --job_name verl-grpo \
  --use_ray \
  --install_ray \
  --monitor
```

### Deploy with HuggingFace Token
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 8 \
  --hf_token "hf_..." \
  --use_ray
```

### Deploy without monitoring
```bash
python3 ~/.opencode/skills/training-job-deployer/src/deploy_job.py \
  --cluster_name my-cluster \
  --num_nodes 4 \
  --no-monitor
```

## Ray Installation

The skill can automatically install KubeRay operator:

```bash
# Check if Ray is installed
python3 -c "
from training_job_deployer.src.deploy_job import check_ray_installed
print('Ray installed:', check_ray_installed('my-cluster'))
"

# Install Ray manually
python3 -c "
from training_job_deployer.src.deploy_job import install_kuberay
install_kuberay('my-cluster')
"
```

### KubeRay Installation Details
- **Helm Chart**: `kuberay/kuberay-operator`
- **Version**: 1.1.0
- **Namespace**: kuberay
- **Resources**: Creates RayCluster CRD and operator deployment

## Output

Returns deployment status:
- Job/cluster status
- Master/head pod name
- Worker pod names
- Fixes applied
- Monitoring information
- Ray dashboard URL (if applicable)

## Requirements

### For PyTorchJob
- EKS cluster with Kubeflow installed
- PyTorchJob CRD available
- GPU operator (NVIDIA) installed

### For Ray
- EKS cluster
- Helm installed locally
- KubeRay operator (auto-installed with `--install_ray`)
- GPU operator (NVIDIA) installed

## Troubleshooting

### Ray cluster not starting
```bash
# Check KubeRay operator logs
kubectl logs -n kuberay -l app.kubernetes.io/name=kuberay-operator

# Check Ray head pod events
kubectl describe pod <job-name>-head-xxxxx
```

### Image pull errors
```bash
# Verify ECR login
aws ecr get-login-password | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com

# Check image exists
aws ecr describe-images --repository-name <repo-name>
```

### GPU not available
```bash
# Check NVIDIA device plugin
kubectl get pods -n kube-system | grep nvidia

# Check node GPU capacity
kubectl describe node <node-name> | grep nvidia.com/gpu
```
