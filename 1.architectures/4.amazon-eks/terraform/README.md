# EKS Terraform Reference Architecture

This repository contains a comprehensive Terraform configuration for deploying an Amazon EKS cluster with advanced features including GPU support, FSx for Lustre, and Mountpoint for S3.

## Architecture Overview

This reference architecture includes:

- **EKS Cluster**: Managed Kubernetes cluster with both default and GPU node groups
- **GPU Support**: Dedicated GPU node groups with NVIDIA device plugin and node auto-repair
- **Node Auto-Repair**: Automatic detection and replacement of unhealthy nodes
- **Storage Solutions**:
  - FSx for Lustre for high-performance computing workloads
  - Mountpoint for S3 for object storage access
  - EBS and EFS CSI drivers
- **Networking**: VPC with public/private subnets and VPC endpoints
- **Security**: IAM roles with least privilege access
- **Monitoring**: CloudWatch integration and metrics server
- **Auto-scaling**: Karpenter for intelligent and fast node provisioning

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl
- Helm (for add-ons)

## Required AWS Permissions

Your AWS credentials need the following permissions:
- EKS cluster management
- EC2 instance and VPC management
- IAM role and policy management
- FSx file system management
- S3 bucket access
- CloudWatch and logging

## Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd terraform-eks-reference-architecture
   ```

2. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Edit `terraform.tfvars` with your specific values:
   - Update `cluster_endpoint_public_access_cidrs` with your IP ranges
   - Set `s3_mountpoint_bucket_name` to your S3 bucket name
   - Configure FSx S3 import/export paths if needed

4. Initialize Terraform:
   ```bash
   terraform init
   ```

5. Plan the deployment:
   ```bash
   terraform plan
   ```

6. Apply the configuration:
   ```bash
   terraform apply
   ```

7. Configure kubectl:
   ```bash
   aws eks --region <region> update-kubeconfig --name <cluster-name>
   ```

## Module Structure

```
modules/
├── vpc/              # VPC, subnets, and networking
├── eks/              # EKS cluster and managed node groups
├── fsx-lustre/       # FSx for Lustre file system
├── s3-mountpoint/    # Mountpoint for S3 integration
└── addons/           # Kubernetes add-ons and controllers
```

## Configuration Options

### Node Groups

#### Default Node Group
- **Instance Types**: Configurable (default: m5.large, m5.xlarge)
- **Scaling**: Auto-scaling with configurable min/max/desired capacity
- **AMI**: Amazon Linux 2 EKS optimized

#### GPU Node Group
- **Instance Types**: GPU-enabled instances (g4dn.xlarge, g4dn.2xlarge, p3.2xlarge)
- **AMI**: Amazon Linux 2 EKS GPU optimized
- **Taints**: Automatically taints GPU nodes
- **Auto-repair**: Enabled with extended grace period for GPU driver initialization

### Node Auto-Repair

Both node groups are configured with automatic node repair capabilities:

#### Default Node Group Auto-Repair
- **Health Check Type**: EC2 instance health checks
- **Grace Period**: 300 seconds (5 minutes)
- **Monitoring**: Continuously monitors node health via EC2 instance status
- **Action**: Automatically replaces unhealthy nodes

#### GPU Node Group Auto-Repair
- **Health Check Type**: EC2 instance health checks
- **Grace Period**: 600 seconds (10 minutes) - Extended due to GPU driver initialization time
- **Monitoring**: Enhanced monitoring for GPU-specific health issues
- **Action**: Intelligent replacement considering GPU resource constraints

#### Auto-Repair Features
- **Proactive Monitoring**: Detects node issues before they impact workloads
- **Graceful Replacement**: Ensures workloads are safely rescheduled before node termination
- **Cost Optimization**: Prevents resource waste from unhealthy nodes
- **Zero-Touch Operations**: Reduces manual intervention for node maintenance

### Auto-Scaling with Karpenter

The reference architecture uses **Karpenter** instead of Cluster Autoscaler for superior node provisioning:

#### Karpenter Advantages
- **Fast Provisioning**: Sub-minute node startup times
- **Cost Optimization**: Intelligent instance selection and spot instance support
- **Flexible Scheduling**: Pod-driven node selection with diverse instance types
- **Efficient Packing**: Optimal resource utilization and consolidation
- **Zero-Configuration**: Automatic node discovery and management

#### Karpenter NodePools

**Default NodePool** - For standard workloads:
```yaml
# Supports spot and on-demand instances
capacity-types: ["spot", "on-demand"]
instance-types: ["m5.*", "m5a.*", "c5.*"]
consolidation: WhenUnderutilized (30s)
expiration: 30 minutes
```

**GPU NodePool** - For GPU workloads:
```yaml
# GPU-specific instances with taints
capacity-types: ["on-demand"]
instance-types: ["g4dn.*", "g5.*", "p3.*"]
consolidation: WhenEmpty (30s)
expiration: 60 minutes
gpu-taints: nvidia.com/gpu=true:NoSchedule
```

#### Karpenter vs Cluster Autoscaler

| Feature | Karpenter | Cluster Autoscaler |
|---------|-----------|-------------------|
| **Provisioning Speed** | ~45 seconds | 3-5 minutes |
| **Instance Selection** | Pod-driven | Node group limited |
| **Spot Support** | Native & seamless | Limited |
| **Cost Optimization** | Advanced bin-packing | Basic scaling |
| **Configuration** | Declarative NodePools | ASG management |
| **Multi-AZ** | Automatic | Manual setup |

### Storage

#### FSx for Lustre
- **Deployment Types**: SCRATCH_1, SCRATCH_2, PERSISTENT_1, PERSISTENT_2
- **S3 Integration**: Optional import/export paths
- **Performance**: Configurable throughput
- **Kubernetes Integration**: Automatic CSI driver and storage class creation

#### Mountpoint for S3
- **CSI Driver**: Automatically deployed and configured
- **IAM Integration**: IRSA (IAM Roles for Service Accounts)
- **Storage Classes**: Pre-configured for immediate use

### Add-ons

The following add-ons are included:

- **Cluster Autoscaler**: Automatic node scaling
- **AWS Load Balancer Controller**: ALB and NLB integration
- **NVIDIA Device Plugin**: GPU resource management
- **Metrics Server**: Resource metrics collection
- **AWS Node Termination Handler**: Graceful spot instance handling
- **EBS CSI Driver**: EBS volume management
- **EFS CSI Driver**: EFS file system support

## Security Best Practices

- **Network Security**: Private subnets for worker nodes
- **IAM**: Least privilege access with IRSA
- **Encryption**: EBS volumes and secrets encryption
- **VPC Endpoints**: Reduced internet traffic and improved security
- **Security Groups**: Restrictive ingress rules

## Monitoring and Logging

- **CloudWatch**: Container Insights integration
- **VPC Flow Logs**: Network traffic monitoring
- **Node Metrics**: CPU, memory, and disk monitoring
- **Application Logs**: Centralized logging to CloudWatch

## Example Workloads

### GPU Workload Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-workload
  template:
    metadata:
      labels:
        app: gpu-workload
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Equal
        value: "true"
        effect: NoSchedule
      nodeSelector:
        nvidia.com/gpu: "true"
      containers:
      - name: gpu-container
        image: nvidia/cuda:11.0-base
        resources:
          limits:
            nvidia.com/gpu: 1
        command: ["nvidia-smi"]
```

### FSx Lustre Usage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fsx-lustre-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fsx-lustre-sc
  resources:
    requests:
      storage: 100Gi
```

### S3 Mountpoint Usage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: s3-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: s3-mountpoint-sc
  resources:
    requests:
      storage: 1000Gi
```

## Karpenter Workload Examples

### Standard Workload with Spot Preference
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 5
  template:
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
      # Prefer spot instances for cost optimization
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: karpenter.sh/capacity-type
                operator: In
                values: ["spot"]
```

### GPU Workload Example
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-training
spec:
  template:
    spec:
      containers:
      - name: ml-training
        image: nvidia/cuda:11.8-base
        resources:
          requests:
            nvidia.com/gpu: 1
            cpu: 2000m
            memory: 8Gi
      nodeSelector:
        node-type: gpu
      tolerations:
      - key: nvidia.com/gpu
        effect: NoSchedule
```

### Testing Karpenter
```bash
# Deploy test workloads
kubectl apply -f examples/karpenter-workloads.yaml

# Run comprehensive Karpenter tests
./examples/test-karpenter.sh test

# Monitor Karpenter scaling
kubectl get nodes -w
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

## Cost Optimization

- **Spot Instances**: Can be enabled for cost savings
- **Single NAT Gateway**: Reduces NAT gateway costs (configurable)
- **VPC Endpoints**: Reduces data transfer costs
- **Auto-scaling**: Right-sizing based on demand

## Troubleshooting

### Common Issues

1. **GPU Nodes Not Ready**: Check NVIDIA driver installation in user data
2. **FSx Mount Issues**: Verify security group rules and Lustre client installation
3. **S3 Mountpoint Errors**: Check IAM permissions and bucket policies
4. **Karpenter Issues**: Check NodePools, EC2NodeClasses, and IAM permissions
5. **Node Auto-Repair Issues**: 
   - Check EC2 instance health in AWS console
   - Verify health check grace periods are appropriate
   - Monitor CloudWatch metrics for node health events

### Debugging Commands

```bash
# Check node status
kubectl get nodes -o wide

# Check GPU resources
kubectl describe nodes -l nvidia.com/gpu=true

# Check storage classes
kubectl get storageclass

# Check persistent volumes
kubectl get pv,pvc

# Check add-on status
kubectl get pods -n kube-system

# Monitor node health and auto-repair
kubectl get nodes --show-labels
kubectl describe node <node-name>

# Check node group health in AWS CLI
aws eks describe-nodegroup --cluster-name <cluster-name> --nodegroup-name <nodegroup-name>

# Monitor auto-repair events
kubectl get events --field-selector involvedObject.kind=Node --sort-by='.lastTimestamp'

# Check Karpenter status and logs
kubectl get nodepool,ec2nodeclass
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50

# Test Karpenter provisioning
./examples/test-karpenter.sh monitor
```

## Cleanup

### Safe Infrastructure Destruction

Use the provided destroy script for safe cleanup:

```bash
./destroy.sh
```

The destroy script will:
1. **Clean up Kubernetes resources** that create AWS resources (LoadBalancers, PVCs, Ingresses)
2. **Wait for AWS resources** to be fully deleted
3. **Run terraform destroy** to remove all infrastructure
4. **Clean up local files** (state backups, plans, etc.)

### Script Options

```bash
# Interactive cleanup (default)
./destroy.sh

# Skip Kubernetes cleanup (if cluster is not accessible)
./destroy.sh --skip-k8s-cleanup

# Force mode (skip confirmations)
./destroy.sh --force

# Get help
./destroy.sh --help
```

### Manual Cleanup (if script fails)

If the destroy script fails, you can manually clean up:

```bash
# Delete example workloads
kubectl delete -f examples/ --ignore-not-found=true

# Delete LoadBalancer services
kubectl get svc --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | while read ns svc; do kubectl delete svc $svc -n $ns; done

# Delete PersistentVolumeClaims
kubectl delete pvc --all --all-namespaces

# Delete Ingress resources
kubectl delete ingress --all --all-namespaces

# Wait for AWS resources to be cleaned up (5-10 minutes)
# Then run terraform destroy
terraform destroy
```

**Important**: Always ensure Kubernetes resources are deleted before running `terraform destroy` to prevent orphaned AWS resources.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section
- Review AWS EKS documentation
- Open an issue in this repository