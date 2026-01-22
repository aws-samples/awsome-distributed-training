# MTC GRPO Training with RayCluster

This directory contains configurations for running GRPO training with VERL with [HyperPod Managed Tiered Checkpointing](https://docs.aws.amazon.com/sagemaker/latest/dg/managed-tier-checkpointing.html).

## Files

- `mtc-grpo-cluster.yaml` - RayCluster configuration
- `submit-mtc-grpo.sh` - Script to submit the GRPO training job to the Ray cluster

## Setup

1. Source environment variables:
```bash
# 1. Load environment variables
source setup/env_vars
```

2. Create Service Account for your pods to have S3 access. To do this, please read the [IRSA-README.md](../setup/IRSA-README.md). 

## Deploy the RayCluster
```
envsubst < managed-tiered-checkpointing/mtc-grpo-cluster.yaml | kubectl apply -f -
```

## Clone MTC-enabled VERL Code
Delete existing verl repo if you already cloned:
```
rm -rf verl
```

Clone MTC-enabled VERL code. This is a fork from the main VERL repo that has modified checkpointing code to enabled managed tiered checkpointing:
```
git clone https://github.com/aruncs2005/verl.git
```

## Submit the training job
```
./managed-tiered-checkpointing/submit-mtc-grpo.sh
```

## Monitoring

- **Ray Dashboard**: http://localhost:8265 (after port forwarding)
- **View logs**: `kubectl logs -f <head-pod-name>`
- **Check job status**: `ray job status <job-id>`
- **Follow job logs**: `ray job logs <job-id> --follow`

## Configuration

Edit `submit-mtc-grpo.sh` to modify training parameters:

- `train_prompt_bsz` - Training batch size
- `train_prompt_mini_bsz` - Mini batch size for PPO
- `train_prompt_micro_bsz_per_gpu` - Micro batch size per GPU
- `n_resp_per_prompt` - Number of responses per prompt
- `gen_tp` - Tensor parallelism for generation
- Model path, data paths, S3 checkpoint location, etc.

## Cleanup

```bash
# Delete the RayCluster
kubectl delete raycluster mtc-grpo-cluster
```