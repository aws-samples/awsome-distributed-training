# Infrastructure Destruction Process

This document outlines the safe destruction process implemented in `destroy.sh`.

## Overview

The `destroy.sh` script ensures safe cleanup of the EKS infrastructure by following a specific order to prevent orphaned AWS resources and failed Terraform destruction.

## Destruction Process Flow

### 1. Pre-Flight Checks
- ✅ Verify Terraform is installed
- ✅ Check kubectl connectivity to cluster
- ✅ Identify cluster name from Terraform state or kubectl context
- ✅ Confirm user intention with safety prompts

### 2. Kubernetes Resource Cleanup

#### Example Workloads
```bash
kubectl delete -f examples/gpu-workload.yaml
kubectl delete -f examples/fsx-lustre-example.yaml  
kubectl delete -f examples/s3-mountpoint-example.yaml
kubectl delete -f examples/node-auto-repair-test.yaml
```

#### LoadBalancer Services
- Identifies all `LoadBalancer` type services across all namespaces
- Deletes each service individually with timeout protection
- Waits for AWS Load Balancers to be fully terminated

#### Ingress Resources
- Finds all Ingress resources that may create ALBs/NLBs
- Deletes Ingress resources to trigger ALB cleanup
- Includes AWS Load Balancer Controller managed resources

#### PersistentVolumeClaims
- Locates all PVCs that may create EBS volumes
- Deletes PVCs to release underlying EBS volumes
- Covers FSx, S3 Mountpoint, and standard EBS storage

#### AWS Load Balancer Controller Resources
- Deletes TargetGroupBinding resources
- Ensures ALB/NLB target groups are cleaned up
- Prevents orphaned target groups

### 3. Resource Cleanup Verification

#### Wait Loop (10 minutes maximum)
```bash
# Continuously checks for:
- LoadBalancer services: 0 remaining
- PersistentVolumeClaims: 0 remaining  
- Ingress resources: 0 remaining
```

#### AWS Resource Verification
```bash
# If AWS CLI available, checks for:
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')]"
aws ec2 describe-security-groups --filters "Name=group-name,Values=*$CLUSTER_NAME*"
aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName, '$CLUSTER_NAME')]"
```

### 4. Terraform Destruction

#### Safety Confirmation
- Final confirmation prompt before destruction
- Clear warning about data loss
- Option to cancel at any point

#### Terraform Commands
```bash
# Initialize if needed
terraform init

# Destroy with auto-approve
terraform destroy -auto-approve
```

### 5. Local Cleanup

#### File Cleanup
```bash
rm -f terraform.tfstate.backup*
rm -f tfplan*
rm -f kubeconfig*
```

## Why This Order Matters

### 1. **Prevent Orphaned Resources**
- Kubernetes-created AWS resources must be deleted first
- Terraform doesn't track LoadBalancers created by services
- PVCs create EBS volumes outside Terraform state

### 2. **Avoid Terraform Errors**
- Security groups can't be deleted if still attached to resources
- Load balancers must be deleted before their target groups
- VPC can't be deleted with remaining ENIs

### 3. **Cost Management**
- Prevents billing for orphaned load balancers
- Ensures EBS volumes are properly deleted
- Cleanup of target groups and security groups

## Error Recovery

### If Script Fails
```bash
# Manual cleanup commands provided in output
kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer
kubectl get pvc --all-namespaces
kubectl get ingress --all-namespaces

# AWS CLI cleanup
aws elbv2 describe-load-balancers
aws ec2 describe-security-groups --filters "Name=group-name,Values=*eks*"
```

### Force Destruction
```bash
# Skip Kubernetes cleanup if cluster inaccessible
./destroy.sh --skip-k8s-cleanup

# Bypass confirmations for automation
./destroy.sh --force
```

## Script Features

### ✅ **Safety First**
- Multiple confirmation prompts
- Comprehensive resource detection
- Graceful error handling

### ✅ **Comprehensive Cleanup**
- All AWS resource types covered
- Multiple cleanup strategies
- Verification steps

### ✅ **User-Friendly**
- Colored output for clarity
- Progress indicators
- Detailed error messages

### ✅ **Flexible Options**
- Skip Kubernetes cleanup
- Force mode for automation
- Help documentation

## Expected Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Kubernetes Cleanup | 2-5 minutes | Delete services, PVCs, ingresses |
| AWS Resource Deletion | 5-10 minutes | Load balancers, target groups |
| Terraform Destroy | 5-15 minutes | VPC, EKS, FSx, etc. |
| **Total** | **12-30 minutes** | Complete infrastructure removal |

## Best Practices

1. **Always use the script** instead of direct `terraform destroy`
2. **Verify cleanup** before proceeding with Terraform destruction
3. **Check AWS console** for any remaining resources after completion
4. **Backup important data** before running destruction
5. **Test in non-production** environments first

## Script Exit Codes

- `0`: Successful completion
- `1`: Critical error (missing tools, failed destruction)
- `130`: User cancellation (Ctrl+C)

This comprehensive approach ensures safe, complete, and cost-effective infrastructure destruction.