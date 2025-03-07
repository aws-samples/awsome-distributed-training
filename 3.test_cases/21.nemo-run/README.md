# NVIDIA NeMo 2.0 Distributed Training

This repository contains examples and configurations for running distributed training with NVIDIA NeMo 2.0 using NeMo Run

## Overview

[NVIDIA NeMo](https://developer.nvidia.com/nemo-framework) is a cloud-native framework for training and deploying generative AI models, optimized for architectures ranging from billions to trillions of parameters. NeMo 2.0 introduces a Python-based configuration system, providing enhanced flexibility, better IDE integration, and streamlined customization for large language model training.

## Slurm-based Deployment

The [slurm](./slurm/) directory provides implementation examples for running NeMo 2.0 on AWS SageMaker HyperPod using Slurm as the workload manager. This approach leverages AWS's purpose-built infrastructure for large-scale AI training. See the [README in the slurm directory](./slurm/README.md) for detailed setup and usage instructions.

## Getting Started

For detailed instructions on using NeMo 2.0 with SageMaker HyperPod, proceed to the [slurm](./slurm/) subdirectory. 