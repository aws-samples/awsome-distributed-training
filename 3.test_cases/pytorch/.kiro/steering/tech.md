---
inclusion: always
---

# Technology Stack

## Training Framework
- **PyTorch FSDP** (Fully Sharded Data Parallel) for distributed training
- **PyTorch 2.7.1** with CUDA 12.x support
- **Transformers 4.53.0** for model architectures (Llama, Mistral, Mixtral)
- **torchrun** for multi-node distributed launch (`/opt/conda/bin/torchrun`)

## Infrastructure
- **Amazon EKS** for Kubernetes orchestration
- **Kubeflow Training Operator** for PyTorchJob management
- **AWS CodeBuild** for Docker image building (no local Docker required)
- **Amazon ECR** for container image registry
- **Amazon S3** for build artifacts and checkpoints

## GPU Instances
- **ml.g5.8xlarge** (1x A10G, 24GB) - tested, working
- **ml.p4d.24xlarge** (8x A100, 40GB) - supported
- **ml.p5.48xlarge** (8x H100, 80GB) - supported

## Networking
- **EFA** (Elastic Fabric Adapter) for high-bandwidth GPU-to-GPU communication
- **NCCL** for collective operations (requires `NCCL_NET=ofi` for EFA)

## Key Environment Variables (PyTorchJob)
- `RANK`, `WORLD_SIZE`, `LOCAL_RANK` - set automatically by torchrun
- `MASTER_ADDR`, `MASTER_PORT` - set automatically by PyTorchJob
- `NCCL_DEBUG=INFO` - for debugging distributed communication
- `FSDP_STATE_DICT_TYPE=SHARDED_STATE_DICT` - for efficient checkpointing

## Tokenizer
- Use `hf-internal-testing/llama-tokenizer` (public, ungated) to avoid HuggingFace auth issues
