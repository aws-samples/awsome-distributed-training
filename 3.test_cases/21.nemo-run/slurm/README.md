# Running NVIDIA NeMo 2.0 on Slurm

This project provides a step-by-step guide to deploying NVIDIA NeMo 2.0 on AWS SageMaker HyperPod. It covers setting up the HyperPod cluster, preparing the environment, and running NeMo jobs for large-scale AI training and inference.

## Table of Contents

- [1. Overview](#1-overview)
- [2. Prerequisites](#2-prerequisites)
- [3. Deploying SageMaker HyperPod Cluster](#3-deploying-sagemaker-hyperpod-cluster)
- [4. SSH into the Cluster Head node](#4-ssh-into-the-cluster-head-node)
- [5. Clone this repo](#5-clone-this-repo)
- [6. Build and Configure the NeMo Job Container](#6-build-and-configure-the-nemo-job-container)
- [7. Install Dependencies and Prepare NeMo 2.0 Environment](#7-install-dependencies-and-prepare-nemo-20-environment)
  - [Install Python 3.10 and NeMo-Run](#install-python-310-and-nemo-run)
  - [Download Tokenizer Files](#download-tokenizer-files)
- [8. Launch Pretraining Job with NeMo-Run](#8-launch-pretraining-job-with-nemo-run)
- [9. References](#9-references)

## 1. Overview

[NVIDIA NeMo](https://developer.nvidia.com/nemo-framework) is a cloud-native framework for training and deploying generative AI models, optimized for architectures ranging from billions to trillions of parameters. It provides:

- **Comprehensive development tools** for data preparation, model training, and deployment.
- **Advanced customization** for fine-tuning models to specific use cases.
- **Optimized infrastructure** with multi-GPU and multi-node support.
- **Enterprise-grade features** such as parallelism techniques, memory optimization, and deployment pipelines.

NeMo 2.0 introduces a Python-based configuration system, providing enhanced flexibility, better IDE integration, and streamlined customization.

## 2. Prerequisites

See [Instructions here](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/00-setup/02-own-account#in-your-own-account) on setting up prerequisite to deploy a SageMaker HyperPod cluster

## 3. Deploying SageMaker HyperPod Cluster

See [Instructions here](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/01-cluster/option-b-manual-cluster-setup) for SageMaker HyperPod Cluster setup.

## 4. SSH into the Cluster Head node

See [Instructions here](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/01-cluster/05-ssh) on how to SSH into the HyperPod cluster

Login to the head node to perform all the steps below

## 5. Clone this repo

```bash
cd /fsx/ubuntu
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/21.nemo-run
```

## 6. Build and Configure the NeMo Job Container

Before running NeMo jobs, build a custom optimized container image for EFA and Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in /fsx/ubuntu.

Ensure you have a registered account with NVIDIA and can access NGC. Retrieve the NGC API key following [instructions from NVIDIA](https://docs.nvidia.com/ngc/gpu-cloud/ngc-user-guide/index.html#generating-api-key). Configure NGC as shown below using the command below, when requested use $oauthtoken for the login username and the API key from NGC for the password.

Login to NGC:

```bash
docker login nvcr.io
```
Build Image:

```bash
$ docker build --progress=plain -t nemo_hyperpod:24.12 -f Dockerfile .
$ sudo enroot import -o /fsx/ubuntu/nemo-hyperpod-24-12.sqsh dockerd://nemo_hyperpod:24.12
```

## 7. Install Dependencies and Prepare NeMo 2.0 Environment

### Install Python 3.10 and NeMo-Run

Update and ensure the correct python version is installed

```bash
$ sudo apt update
$ sudo apt install software-properties-common -y
$ sudo add-apt-repository ppa:deadsnakes/ppa
$ sudo apt update
$ sudo apt install python3.10 python3.10-venv python3.10-dev
$ python3.10 --version
```

Create Virtual environment and install NeMo Run and other dependencies

```bash
$ python3.10 -m venv temp-env
$ source temp-env/bin/activate
$ bash venv.sh
```

### Download Tokenizer Files

We will be running the pre-training of LLaMa8B model in an offline mode, so we will download the vocab and merges files for the tokenizer

```bash
$ mkdir -p /fsx/ubuntu/temp/megatron
$ wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json -O /fsx/ubuntu/temp/megatron/megatron-gpt-345m_vocab
$ wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt -O /fsx/ubuntu/temp/megatron/megatron-gpt-345m_merges
```

## 8. Launch Pretraining Job with NeMo-Run

Run the following script to start the LLaMa 8B pretraining job:

```bash
$ python run.py --nodes 2 --max_steps 1000
```

## 9. References

- [NVIDIA NeMo Documentation](https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/stable/index.html)
- [NVIDIA NeMo Github](https://github.com/NVIDIA/NeMo)
- [AWS SageMaker HyperPod Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod.html)
- [AWS SageMaker HyperPoc Workshop](https://catalog.workshops.aws/sagemaker-hyperpod/en-US)

