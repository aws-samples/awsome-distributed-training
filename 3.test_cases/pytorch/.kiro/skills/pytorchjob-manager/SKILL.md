---
name: pytorchjob-manager
description: Manage PyTorchJob resources on Amazon EKS for distributed training. Deploy, monitor, get logs, and delete PyTorchJobs using the Kubeflow Training Operator.
license: MIT
compatibility: kiro
metadata:
  category: deployment
  author: opencode
---

# PyTorchJob Manager Skill

Manage PyTorchJob resources on Amazon EKS for distributed training workloads.

## Overview

This skill provides utilities to deploy, monitor, and manage PyTorchJob custom resources using the Kubeflow Training Operator on EKS clusters.

## Functions

### `check_pytorchjob_crd()`
Verify PyTorchJob CRD is installed on the cluster.

### `generate_pytorchjob_yaml(config)`
Generate complete PyTorchJob YAML with FSDP support.

**Config options:**
- `name`: Job name
- `namespace`: Kubernetes namespace
- `image`: Training container image
- `num_workers`: Number of worker nodes
- `num_gpus_per_worker`: GPUs per worker
- `command`: Training command
- `env`: Environment variables dict
- `fsdp_config`: FSDP configuration dict
- `resources`: Resource requests/limits
- `volumes`: Additional volume mounts

### `deploy_pytorchjob(yaml_content)`
Deploy PyTorchJob to the cluster.

### `get_pytorchjob_status(name)`
Get status of a PyTorchJob.

### `delete_pytorchjob(name)`
Delete a PyTorchJob from the cluster.

## Example: FSDP Training

```python
from pytorchjob_manager import generate_pytorchjob_yaml, deploy_pytorchjob, get_pytorchjob_status

config = {
    "name": "fsdp-llama-training",
    "namespace": "default",
    "image": "123456789012.dkr.ecr.us-west-2.amazonaws.com/pytorch-training:latest",
    "num_workers": 4,
    "num_gpus_per_worker": 8,
    "command": [
        "python", "-m", "torch.distributed.run",
        "--nnodes", "4",
        "--nproc_per_node", "8",
        "train_fsdp.py"
    ],
    "env": {
        "NCCL_DEBUG": "INFO",
        "TORCH_DISTRIBUTED_DEBUG": "DETAIL",
        "FSDP_STATE_DICT_TYPE": "SHARDED_STATE_DICT"
    },
    "fsdp_config": {
        "sharding_strategy": "FULL_SHARD",
        "backward_prefetch": "BACKWARD_PRE",
        "cpu_offload": False,
        "limit_all_gathers": True
    },
    "resources": {
        "memory": "512Gi",
        "cpu": "96"
    }
}

# Generate and deploy
yaml_content = generate_pytorchjob_yaml(config)
deploy_pytorchjob(yaml_content)

# Monitor status
status = get_pytorchjob_status("fsdp-llama-training")
print(f"Job status: {status")
```

## Requirements

- kubectl configured with EKS cluster access
- Kubeflow Training Operator installed
- PyTorchJob CRD available

## Installation

```bash
# Install Kubeflow Training Operator
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone?ref=v1.7.0"
```
