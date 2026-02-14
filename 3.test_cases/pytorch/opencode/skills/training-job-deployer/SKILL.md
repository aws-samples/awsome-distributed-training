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

## Checkpointing and Persistent Storage

### Important: Use Persistent Volumes for Checkpoints

**Critical:** By default, RayCluster pods use ephemeral storage. If the RayCluster is deleted or recreated, all checkpoint data will be lost. To enable proper checkpoint resume functionality, you must use persistent storage.

### Setting Up Persistent Storage

#### Option 1: EBS Persistent Volume (Recommended for testing)

Create a PersistentVolumeClaim:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: training-checkpoints
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 100Gi
```

Mount in RayCluster:
```yaml
# In your RayCluster spec
spec:
  headGroupSpec:
    template:
      spec:
        containers:
        - name: ray-head
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: training-checkpoints
```

#### Option 2: FSx for Lustre (Production)

For production workloads, use FSx for Lustre as shown in the verl/rlvr example:
```yaml
volumes:
- name: fsx-storage
  persistentVolumeClaim:
    claimName: fsx-claim
```

### Resume from Checkpoint

When using persistent storage, resume training with:
```bash
python3 -m verl.trainer.main_ppo \
  ... \
  trainer.resume_mode=auto \
  trainer.resume_from_path=/checkpoints/GRPO/global_step_43
```

### Checkpoint Best Practices

1. **Always use persistent storage** for checkpoints
2. **Set appropriate save frequency**: `trainer.save_freq=10` (every 10 steps)
3. **Monitor checkpoint disk usage**: Large models can create multi-GB checkpoints
4. **Backup important checkpoints** to S3 periodically
5. **Test resume functionality** before long training runs

### Example with Persistent Storage

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: verl-training
spec:
  headGroupSpec:
    template:
      spec:
        containers:
        - name: ray-head
          image: your-verl-image:latest
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: training-checkpoints
  workerGroupSpecs:
  - replicas: 3
    template:
      spec:
        containers:
        - name: ray-worker
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: training-checkpoints
```

## EFA (Elastic Fabric Adapter) Configuration

### Enabling EFA for High-Performance Networking

EFA provides high-performance networking for distributed training. To enable EFA:

#### 1. Add EFA Resources to RayCluster

```yaml
spec:
  headGroupSpec:
    template:
      spec:
        containers:
        - name: ray-head
          resources:
            limits:
              vpc.amazonaws.com/efa: "1"
            requests:
              vpc.amazonaws.com/efa: "1"
          securityContext:
            capabilities:
              add:
              - IPC_LOCK
              - SYS_RESOURCE
```

#### 2. Configure EFA Environment Variables

```yaml
env:
- name: FI_PROVIDER
  value: "efa"
- name: FI_EFA_USE_DEVICE_RDMA
  value: "0"  # Set to 0 for g5 instances (no RDMA-read support)
- name: FI_EFA_FORK_SAFE
  value: "1"
- name: NCCL_PROTO
  value: "simple"
```

### EFA Troubleshooting

#### Verify EFA is Working
```bash
# Check EFA device
kubectl exec <pod-name> -- ls -la /sys/class/infiniband/

# Test EFA provider
kubectl exec <pod-name> -- fi_info -p efa

# Check NCCL is using EFA (should show "NET/Libfabric" not "NET/Socket")
kubectl logs <pod-name> | grep "Using network"
```

#### Common EFA Issues

**Issue:** `FI_EFA_USE_DEVICE_RDMA=1 was set, but EFA device has no rdma-read capability`
**Solution:** Set `FI_EFA_USE_DEVICE_RDMA=0` for g5 instances

**Issue:** `No eligible providers were found`
**Solution:** 
- Ensure EFA device plugin is installed
- Check node has EFA-enabled instance type (g5, p4d, p5)
- Verify security groups allow EFA traffic

**Issue:** NCCL falling back to TCP Socket
**Solution:**
- Add `vpc.amazonaws.com/efa: "1"` resource request
- Add security capabilities `IPC_LOCK` and `SYS_RESOURCE`
- Verify EFA kernel module is loaded on nodes

## NCCL Safeguards for Stability

### Recommended NCCL Settings

For stable distributed training with EFA:

```yaml
env:
# Increase timeout to prevent premature failures (default: 600s)
- name: NCCL_TIMEOUT
  value: "1800"  # 30 minutes

# Enable NCCL debug tracing for troubleshooting
- name: TORCH_NCCL_TRACE_BUFFER_SIZE
  value: "4096"

# Debug level (use INFO for troubleshooting)
- name: NCCL_DEBUG
  value: "INFO"

# Use simple protocol for better compatibility
- name: NCCL_PROTO
  value: "simple"
```

### Reducing Network Pressure

If experiencing NCCL timeouts or worker crashes:

1. **Reduce batch size**: Lower `train_batch_size` from 16 to 8
2. **Increase NCCL timeout**: Set `NCCL_TIMEOUT=1800` (30 min)
3. **Enable gradient checkpointing**: Reduces memory pressure
4. **Use smaller model**: Test with Qwen2.5-0.5B before larger models

## Complete Production Example

### RayCluster with EFA, Persistent Storage, and Safeguards

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: verl-grpo-training
  namespace: default
spec:
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
      num-gpus: "1"
      block: "true"
    template:
      spec:
        containers:
        - name: ray-head
          image: 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest
          resources:
            limits:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
              vpc.amazonaws.com/efa: "1"
            requests:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
              vpc.amazonaws.com/efa: "1"
          env:
          - name: NCCL_DEBUG
            value: "INFO"
          - name: NCCL_TIMEOUT
            value: "1800"
          - name: TORCH_NCCL_TRACE_BUFFER_SIZE
            value: "4096"
          - name: PYTHONUNBUFFERED
            value: "1"
          - name: FI_PROVIDER
            value: "efa"
          - name: FI_EFA_USE_DEVICE_RDMA
            value: "0"
          - name: FI_EFA_FORK_SAFE
            value: "1"
          - name: NCCL_PROTO
            value: "simple"
          securityContext:
            capabilities:
              add:
              - IPC_LOCK
              - SYS_RESOURCE
          ports:
          - containerPort: 6379
            name: gcs-server
          - containerPort: 8265
            name: dashboard
          - containerPort: 10001
            name: client
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
          - name: shm
            mountPath: /dev/shm
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: fsx-claim  # Use existing FSx or create new PVC
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 16Gi
  workerGroupSpecs:
  - replicas: 3
    minReplicas: 3
    maxReplicas: 3
    groupName: worker-group
    rayStartParams:
      num-gpus: "1"
      block: "true"
    template:
      spec:
        containers:
        - name: ray-worker
          image: 975049888767.dkr.ecr.us-west-2.amazonaws.com/verl-rlvr:latest
          resources:
            limits:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
              vpc.amazonaws.com/efa: "1"
            requests:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
              vpc.amazonaws.com/efa: "1"
          env:
          - name: NCCL_DEBUG
            value: "INFO"
          - name: NCCL_TIMEOUT
            value: "1800"
          - name: TORCH_NCCL_TRACE_BUFFER_SIZE
            value: "4096"
          - name: PYTHONUNBUFFERED
            value: "1"
          - name: FI_PROVIDER
            value: "efa"
          - name: FI_EFA_USE_DEVICE_RDMA
            value: "0"
          - name: FI_EFA_FORK_SAFE
            value: "1"
          - name: NCCL_PROTO
            value: "simple"
          securityContext:
            capabilities:
              add:
              - IPC_LOCK
              - SYS_RESOURCE
          volumeMounts:
          - name: checkpoints
            mountPath: /checkpoints
          - name: shm
            mountPath: /dev/shm
        volumes:
        - name: checkpoints
          persistentVolumeClaim:
            claimName: fsx-claim
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 16Gi
```

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

### NCCL Timeout Errors

**Symptoms:**
- `Watchdog caught collective operation timeout`
- `WorkNCCL ran for 600013 milliseconds before timing out`

**Solutions:**
1. Increase NCCL timeout: `NCCL_TIMEOUT=1800`
2. Reduce batch size: `train_batch_size=8`
3. Check EFA connectivity: `fi_info -p efa`
4. Verify network: Check if using `NET/Libfabric` not `NET/Socket`

### Training Crashes with SIGABRT

**Symptoms:**
- Worker dies unexpectedly
- `Fatal Python error: Aborted`

**Solutions:**
1. Reduce memory pressure: Enable gradient checkpointing
2. Lower batch size
3. Check GPU memory: `nvidia-smi` inside pods
4. Verify EFA configuration (see EFA section)

### Checkpoints Not Persisting

**Symptoms:**
- Checkpoints lost after cluster restart
- `resume_from_path` not working

**Solutions:**
1. Use persistent volume (PVC) for checkpoints
2. Mount PVC at same path in all containers
3. Verify checkpoint directory exists: `ls -la /checkpoints/`
4. Check PVC is bound: `kubectl get pvc`

### EFA Not Working (Falling back to TCP)

**Symptoms:**
- NCCL logs show `Using network Socket` instead of `Using network Libfabric`
- Slow training performance

**Solutions:**
1. Add EFA resource request: `vpc.amazonaws.com/efa: "1"`
2. Add security capabilities: `IPC_LOCK`, `SYS_RESOURCE`
3. Set FI_PROVIDER: `FI_PROVIDER=efa`
4. Verify EFA device exists: `ls /sys/class/infiniband/`

## Monitoring Training

### Check Training Progress
```bash
# Get job status
kubectl exec <head-pod> -- ray job status <job-id>

# View logs
kubectl exec <head-pod> -- ray job logs <job-id>

# Check checkpoints
kubectl exec <head-pod> -- ls -la /checkpoints/GRPO/<job-name>/

# Monitor EFA traffic
kubectl logs <pod-name> | grep "NET/Libfabric"
```

### Performance Metrics

Expected performance with EFA on g5.8xlarge:
- **Step time:** 28-40 seconds
- **Throughput:** 50-90 tokens/sec
- **Network:** NET/Libfabric (EFA)
- **Checkpoints:** Every 10 steps (configurable)

If performance is significantly slower, check:
1. EFA is enabled (should see `Using network Libfabric`)
2. Not falling back to TCP Socket
3. Batch size is appropriate for your setup

