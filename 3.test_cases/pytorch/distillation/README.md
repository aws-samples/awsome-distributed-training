# Model Distillation of Qwen 3B model to 1.5B model using TRL library

This example provides an example of running Distributed Distillation on SageMaker Hyperpod with EKS

## Repository Structure
```
3.test_cases/pytorch/distillation/
├── Dockerfile                 # Container definition for running distillation workloads
├── kubernetes/
│   └── distill.yaml          # Kubernetes configuration for distributed training
└── src/
    ├── distil_logits_cli.py  # Main distillation script with CLI interface
    ├── requirements.txt      # Python package dependencies
    └── setup.sh              # Environment setup script for PyTorch and dependencies
```

## Usage Instructions
### Prerequisites
- NVIDIA GPU with CUDA support
- Docker runtime with NVIDIA container toolkit
- Kubernetes cluster with GPU support (for distributed training)
- Python 3.10+

Required packages:
- PyTorch 2.6.0+
- Transformers 4.51.3
- Accelerate 1.6.0
- Flash Attention 2.7.4
- DeepSpeed

### Installation

Follow the FSDP setup and training setups
