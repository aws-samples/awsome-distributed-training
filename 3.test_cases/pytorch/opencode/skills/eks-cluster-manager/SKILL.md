---
name: eks-cluster-manager
description: Manage and validate Amazon EKS clusters for training workloads. Discovers clusters, validates GPU operators, EFA, Kubeflow, and provides auto-fix capabilities.
license: MIT
compatibility: opencode
metadata:
  category: infrastructure
  author: opencode
---

## What I do

Manages EKS clusters for ML training:

1. **Cluster Discovery**: Automatically discovers available EKS clusters
2. **Validation**: Checks all required components:
   - NVIDIA GPU operator
   - EFA (Elastic Fabric Adapter)
   - Kubeflow training operator
   - Node GPU availability
3. **Auto-Fix**: Attempts to fix common issues
4. **Status Monitoring**: Reports cluster health and capacity

## When to use me

Use this skill when you need to:
- Validate an EKS cluster before training
- Check GPU and EFA availability
- Discover available clusters
- Fix common cluster configuration issues
- Monitor cluster health

## How to use me

### Command Line
```bash
# Discover and validate
python3 ~/.opencode/skills/eks-cluster-manager/src/manage_cluster.py

# Validate specific cluster
python3 ~/.opencode/skills/eks-cluster-manager/src/manage_cluster.py \
  --cluster_name my-cluster \
  --validate_components \
  --auto_fix
```

### Python API
```python
from eks_cluster_manager.src.manage_cluster import ClusterManager

manager = ClusterManager(cluster_name="my-cluster", region="us-west-2")
status = manager.validate_cluster()
```

## Validations

- ✅ Cluster accessibility
- ✅ NVIDIA GPU operator running
- ✅ EFA (Elastic Fabric Adapter) enabled
- ✅ Kubeflow training operator installed
- ✅ Node GPU availability
- ✅ Sufficient node capacity

## Parameters

- `cluster_name`: EKS cluster name (optional, auto-detect if not provided)
- `region`: AWS region (default: "us-west-2")
- `validate_components`: Run component validation (default: true)
- `auto_fix`: Attempt to fix issues automatically (default: false)
- `create_if_missing`: Create cluster if not found (default: false)

## Output

Returns cluster status including:
- Cluster health
- GPU availability
- EFA status
- Node capacity
- Validation results
- Fix recommendations

## Examples

### Interactive cluster selection
```bash
python3 ~/.opencode/skills/eks-cluster-manager/src/manage_cluster.py
```

### Validate with auto-fix
```bash
python3 ~/.opencode/skills/eks-cluster-manager/src/manage_cluster.py \
  --cluster_name sagemaker-test-cluster \
  --auto_fix
```
