# Running NVIDIA NeMo 2.0 on Slurm

This project provides a step-by-step guide to deploying NVIDIA NeMo 2.0 on a Slurm cluster. It covers preparing the environment, and running NeMo jobs for large-scale AI training.

## Table of Contents

- [1. Overview](#1-overview)
- [2. Prerequisites](#2-prerequisites)
- [3. Clone this repo](#3-clone-this-repo)
- [4. Build and Configure the NeMo Job Container](#4-build-and-configure-the-nemo-job-container)
- [5. Install Dependencies and Prepare NeMo 2.0 Environment](#5-install-dependencies-and-prepare-nemo-20-environment)
  - [Install Python 3.10 and NeMo-Run](#install-python-310-and-nemo-run)
  - [Download Tokenizer Files](#download-tokenizer-files)
- [6. Launch Pretraining Job with NeMo-Run](#6-launch-pretraining-job-with-nemo-run)
- [7. References](#7-references)

## 1. Overview

[NVIDIA NeMo](https://developer.nvidia.com/nemo-framework) is a cloud-native framework for training and deploying generative AI models, optimized for architectures ranging from billions to trillions of parameters. It provides:

- **Comprehensive development tools** for data preparation, model training, and deployment.
- **Advanced customization** for fine-tuning models to specific use cases.
- **Optimized infrastructure** with multi-GPU and multi-node support.
- **Enterprise-grade features** such as parallelism techniques, memory optimization, and deployment pipelines.

NeMo 2.0 introduces a Python-based configuration system, providing enhanced flexibility, better IDE integration, and streamlined customization.

## 2. Prerequisites

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, for Slurm [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) need to be installed as well.
- An FSx for Lustre filesystem mounted on `/fsx` in all Slurm nodes.

It is recommended that you use the templates in the architectures [directory](../../1.architectures) for setting up Amazon SageMaker HyperPod or AWS Parallel Cluster.

Make sure that your current directory is under a shared filesystem such as `/fsx`.


## 3. Clone this repo

  ```bash
  cd /fsx/ubuntu
  git clone https://github.com/aws-samples/awsome-distributed-training/
  cd awsome-distributed-training/3.test_cases/21.nemo-run
  ```

## 4. Build and Configure the NeMo Job Container

Before running NeMo jobs, build a custom optimized container image for EFA and Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in /fsx/ubuntu.

Build Image:

  ```bash
  docker build --progress=plain -t nemo_hyperpod:24.12 -f Dockerfile .
  sudo enroot import -o /fsx/ubuntu/nemo-hyperpod-24-12.sqsh dockerd://nemo_hyperpod:24.12
  ```

## 5. Install Dependencies and Prepare NeMo 2.0 Environment

### Install Python 3.10 and NeMo-Run

Update and ensure the correct python version is installed

  ```bash
  sudo apt update
  sudo apt install software-properties-common -y
  sudo add-apt-repository ppa:deadsnakes/ppa
  sudo apt update
  sudo apt install python3.10 python3.10-venv python3.10-dev
  python3.10 --version
  ```

Create Virtual environment and install NeMo Run and other dependencies

  ```bash
  python3.10 -m venv temp-env
  source temp-env/bin/activate
  bash venv.sh
  ```

### Download Tokenizer Files

We will be running the pre-training of LLaMa8B model in an offline mode, so we will download the vocab and merges files for the tokenizer

  ```bash
  mkdir -p /fsx/ubuntu/temp/megatron
  wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json -O /fsx/ubuntu/temp/megatron/megatron-gpt-345m_vocab
  wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt -O /fsx/ubuntu/temp/megatron/megatron-gpt-345m_merges
  ```

## 6. Launch Pretraining Job with NeMo-Run

Run the following script to start the LLaMa 8B pretraining job:

  ```bash
  python run.py --nodes 2 --max_steps 1000
  ```

## 7. References

- [NVIDIA NeMo Documentation](https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/stable/index.html)
- [NVIDIA NeMo Github](https://github.com/NVIDIA/NeMo)
- [AWS SageMaker HyperPod Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod.html)
- [AWS SageMaker HyperPoc Workshop](https://catalog.workshops.aws/sagemaker-hyperpod/en-US)

