# Running NVIDIA NeMo 2.0 on Amazon SageMaker HyperPod

This project provides a step-by-step guide to deploying NVIDIA NeMo 2.0 on AWS SageMaker HyperPod. It covers setting up the HyperPod cluster, preparing the environment, and running NeMo jobs for large-scale AI training and inference.

## Table of Contents

- [1. Overview](#1-overview)
- [2. Prerequisites](#2-prerequisites)
- [3. Deploying SageMaker HyperPod Cluster](#3-deploying-sagemaker-hyperpod-cluster)
- [4. SSH into the Cluster](#4-ssh-into-the-cluster)
- [5. Build and Configure the NeMo Job Container](#5-build-and-configure-the-nemo-job-container)
- [6. Install Dependencies and Prepare Environment](#6-install-dependencies-and-prepare-environment)
- [7. Launch Pretraining Job with NeMo-Run](#7-launch-pretraining-job-with-nemo-run)
- [8. References](#8-references)

## 1. Overview

[NVIDIA NeMo](https://developer.nvidia.com/nemo-framework) is a cloud-native framework for training and deploying generative AI models, optimized for architectures ranging from billions to trillions of parameters. It provides:

- **Comprehensive development tools** for data preparation, model training, and deployment.
- **Advanced customization** for fine-tuning models to specific use cases.
- **Optimized infrastructure** with multi-GPU and multi-node support.
- **Enterprise-grade features** such as parallelism techniques, memory optimization, and deployment pipelines.

NeMo 2.0 introduces a Python-based configuration system, providing enhanced flexibility, better IDE integration, and streamlined customization.

## 2. Prerequisites

Before deploying the HyperPod cluster, ensure that the following AWS resources are created:

- Virtual Private Cloud (VPC) and subnets
- FSx Lustre volume
- Amazon S3 bucket
- IAM role with required permissions

To deploy these resources using AWS CloudFormation:

1. Click [this CloudFormation template](#) to launch the setup.
2. Update the **availability zone** to match your region (e.g., `us-east-1` → `use1-az4`).
3. Accept the default parameters or modify as needed.
4. Acknowledge capabilities and create the stack.

The setup takes approximately **10 minutes** to complete.

## 3. Deploying SageMaker HyperPod Cluster

### Step 1: Setup AWS CLI

Ensure you have AWS CLI installed and configured:
```bash
$ aws --version
```

### Step 2: Configure Environment Variables

Use the CloudFormation stack output to configure environment variables:
```bash
$ curl 'https://static.us-east-1.prod.workshops.aws/public/c9dccefd-8d5d-4e65-87bf-1e4623f52de8/static/scripts/create_config.sh' --output create_config.sh
$ AWS_REGION=us-east-1 bash create_config.sh
$ source env_vars
$ cat env_vars
```

### Step 3: Upload Lifecycle Scripts to S3

```bash
$ git clone --depth=1 https://github.com/aws-samples/awsome-distributed-training/
$ aws s3 cp --recursive awsome-distributed-training/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config/ s3://${BUCKET}/src
```

### Step 4: Create Cluster Configuration

Create `cluster-config.json`:
```bash
$ source env_vars
$ cat > cluster-config.json << EOL
{
    "ClusterName": "ml-cluster",
    "InstanceGroups": [...],
    "VpcConfig": { "SecurityGroupIds": ["$SECURITY_GROUP"], "Subnets": ["$SUBNET_ID"] }
}
EOL
```

Create `provisioning_parameters.json`:
```bash
$ aws s3 cp provisioning_parameters.json s3://${BUCKET}/src/
```

### Step 5: Launch HyperPod Cluster

```bash
$ aws sagemaker create-cluster --cli-input-json file://cluster-config.json --region $AWS_REGION
```

Check cluster status:
```bash
$ aws sagemaker list-clusters --output table
```

## 4. SSH into the Cluster

Once the cluster is in **InService** state, connect using AWS Systems Manager:

```bash
$ ssh-keygen -t rsa -q -f "$HOME/.ssh/id_rsa" -N ""
$ curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/easy-ssh.sh
$ chmod +x easy-ssh.sh
$ ./easy-ssh.sh -c controller-machine ml-cluster
```

## 5. Build and Configure the NeMo Job Container

Before running NeMo jobs, build a custom container image:

```bash
$ docker build --progress=plain -t nemo_hyperpod:24.12 -f Dockerfile .
$ sudo enroot import -o /fsx/ubuntu/nemo-hyperpod-24-12.sqsh dockerd://nemo_hyperpod:24.12
```

If space issues arise, use:
```bash
$ sudo enroot import -o /fsx/ubuntu/nemo-hyperpod-24-12.sqsh dockerd://nemo_hyperpod:24.12
```

## 6. Install Dependencies and Prepare Environment

### Install Python 3.10 and NeMo-Run

```bash
$ sudo apt update
$ sudo apt install python3.10 python3.10-venv python3.10-dev
$ python3.10 --version
$ python3.10 -m venv temp-env
$ source temp-env/bin/activate
$ pip install git+https://github.com/NVIDIA/NeMo-Run.git
$ pip install torch nemo_toolkit['nlp'] opencc==1.1.6
```

### Download Tokenizer Files

```bash
$ mkdir -p /fsx/ubuntu/temp/megatron
$ cd /fsx/ubuntu/temp/megatron
$ wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json -O megatron-gpt-345m_vocab
$ wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt -O megatron-gpt-345m_merges
```

## 7. Launch Pretraining Job with NeMo-Run

Run the following script to start the LLaMa 8B pretraining job:

```bash
$ python run.py --nodes 2 --max_steps 1000
```

### Monitor Job Status

```bash
$ sinfo  # View partitions and nodes
$ squeue # View job queue
```

### Sample Output

After training completes, check the output logs:
```bash
$ tail -5 /fsx/ubuntu/results/llama8b/log-nemo-llama8b.err
```

## 8. References

- [NVIDIA NeMo Documentation](https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/stable/index.html)
- [AWS SageMaker HyperPod](https://docs.aws.amazon.com/sagemaker/latest/dg/hyperpod.html)

This guide provides a structured approach to deploying NeMo 2.0 on SageMaker HyperPod for large-scale AI training and inference.

