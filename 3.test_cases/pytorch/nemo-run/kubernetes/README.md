# Run nemo-run on Kubernetes

> [!IMPORTANT]
> **Note**: nemo-run does not support Kubernetes as an Executor. This guide provides an alternative approach using PyTorchJob for distributed training on Kubernetes clusters. The setup is optimized for distributed training workloads but is not officially supported by nemo-run.

## Prerequisites

1. A Kubernetes cluster with:
   - NVIDIA GPUs (tested with H100)
   - EFA plugin that supports high-speed networking
   - Shared filesystem (e.g., NFS, Lustre)

2. Required tools:
   - kubectl
   - helm
   - docker
   - NVIDIA Container Toolkit

## 1. Install NVIDIA Device Plugin

First, ensure the NVIDIA device plugin is installed on your cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.3/nvidia-device-plugin.yml
```

Verify the installation:
```bash
kubectl get pods -n kube-system | grep nvidia-device-plugin
```

## 2. Install AWS EFA Device Plugin

Install the AWS EFA Kubernetes Device Plugin to enable EFA support:

```bash
# Add the EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts

# Install the EFA device plugin
helm install efa eks/aws-efa-k8s-device-plugin -n kube-system
```

Verify the installation:
```bash
kubectl get pods -n kube-system | grep aws-efa-k8s-device-plugin
```

Verify EFA resources are available on nodes:
```bash
# Get node name
NODE_NAME=$(kubectl get nodes -l node.kubernetes.io/instance-type=p4de.24xlarge -o jsonpath='{.items[0].metadata.name}')

# Check EFA resources
kubectl describe node $NODE_NAME | grep efa
```

You should see `vpc.amazonaws.com/efa: 4` in the output for P4de nodes or `vpc.amazonaws.com/efa: 32` for P5.48xlarge nodes.

## 3. Set Up Amazon FSx for Lustre Storage

For distributed training, we'll use Amazon FSx for Lustre as the shared filesystem. Follow these steps:

1. Install the Amazon FSx for Lustre CSI driver:
```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-fsx-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
```

2. Create a storage class for FSx:
```bash
kubectl apply -f storage/fsx-storage-class.yaml
```

3. Create the PersistentVolume and PersistentVolumeClaim:
```bash
kubectl apply -f storage/pv.yaml
kubectl apply -f storage/pvc.yaml
```

4. Verify the storage setup:
```bash
kubectl get pv
kubectl get pvc
```

The storage should be in "Bound" state before proceeding with the training job.

## 4. Build and Push Docker Image

### 4.1 Set up AWS ECR Repository

First, set up your AWS environment variables and create an ECR repository:

```bash
# Set AWS region and get account ID
export AWS_REGION=us-west-2  # Replace with your region
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Set image details
export REGISTRY=${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/
export IMAGE=nemo-run
export TAG=":latest"

# Create ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names ${IMAGE} || \
    aws ecr create-repository --repository-name ${IMAGE}

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${REGISTRY}
```

### 4.2 Build and Push the Image

Build the nemo-run Docker image and push it to ECR:

```bash
# Build the image
docker build -t ${REGISTRY}${IMAGE}${TAG} -f ../Dockerfile ..

# Push to ECR
docker push ${REGISTRY}${IMAGE}${TAG}
```

### 4.3 Verify the Image

Verify that the image was pushed successfully:

```bash
# List images in the repository
aws ecr list-images --repository-name ${IMAGE}

# Get image details
aws ecr describe-images --repository-name ${IMAGE}
```

## 5. Deploy Training Job

### 5.1 Install Kubeflow Training Operator

First, install the Kubeflow Training Operator to enable PyTorchJob support:

```bash
# Install the training operator
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"

# Verify the installation
kubectl get pods -n kubeflow
```

### 5.2 Prepare Training Job Configuration

1. Update the image name in the training job configuration:
```bash
# Replace placeholders in the training job configuration
sed -i "s|\${REGISTRY}|\${REGISTRY}|g" training/nemo-training-job.yaml
sed -i "s|\${IMAGE}|\${IMAGE}|g" training/nemo-training-job.yaml
sed -i "s|\${TAG}|\${TAG}|g" training/nemo-training-job.yaml
```

2. Review and adjust the following parameters in `training/nemo-training-job.yaml`:
   - `WORLD_SIZE`: Total number of GPUs across all nodes
   - `replicas`: Number of worker nodes
   - GPU and EFA resource requests/limits
   - NCCL configuration parameters

### 5.3 Deploy the Training Job

```bash
# Create namespace
kubectl create namespace nemo-training

# Deploy the training job
kubectl apply -f training/nemo-training-job.yaml
```

### 5.4 Monitor the Training Job

```bash
# Check job status
kubectl get pytorchjobs -n nemo-training

# View master pod logs
kubectl logs -f nemo-training-master-0 -n nemo-training

# View worker pod logs
kubectl logs -f nemo-training-worker-0 -n nemo-training

# Check GPU utilization
kubectl exec -it nemo-training-master-0 -n nemo-training -- nvidia-smi
```

### 5.5 Training Job Configuration Details

The PyTorchJob configuration includes:

1. **Resource Allocation**:
   - 8 GPUs per node
   - 4 EFA devices per node
   - Shared FSx storage mounted at `/workspace/data` and `/workspace/results`

2. **Distributed Training Setup**:
   - Master node (rank 0) and worker nodes
   - NCCL configuration for optimal EFA performance
   - Automatic master-worker communication setup

3. **Environment Variables**:
   - `MASTER_ADDR`: Set to the master pod's hostname
   - `MASTER_PORT`: Default PyTorch distributed port
   - `WORLD_SIZE`: Total number of GPUs
   - `RANK`: Unique rank for each node
   - NCCL configuration for EFA optimization

4. **Volume Mounts**:
   - Training data mounted from FSx
   - Results directory for model checkpoints and logs

## 6. Monitor Training

Monitor your training job:

```bash
# Check job status
kubectl get jobs -n nemo-training

# View logs
kubectl logs -f job/nemo-training -n nemo-training

# Check GPU utilization
kubectl exec -it <pod-name> -n nemo-training -- nvidia-smi
```

## 7. Configuration

The training configuration can be modified in `training/nemo-training-job.yaml`. Key parameters include:

- Number of GPUs
- Batch size
- Learning rate
- Model configuration
- Dataset location

## 8. Troubleshooting

Common issues and solutions:

1. GPU not visible to pods:
   - Verify NVIDIA device plugin is running
   - Check node labels for GPU resources

2. Pod scheduling issues:
   - Verify resource requests match available resources
   - Check node affinity rules

3. Training performance issues:
   - Verify network plugin configuration
   - Check shared storage performance
   - Monitor GPU utilization

## Directory Structure

```
kubernetes/
├── README.md
├── storage/
│   ├── pv.yaml
│   └── pvc.yaml
├── training/
│   ├── nemo-training-job.yaml
│   └── config/
│       └── training-config.yaml
└── monitoring/
    └── prometheus-rules.yaml
```

## Additional Resources

- [NVIDIA Container Toolkit Documentation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/overview.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html) 