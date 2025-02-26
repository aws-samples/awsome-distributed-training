# Running NVIDIA NeMo 2.0 on Amazon SageMaker HyperPod

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

Before deploying the HyperPod cluster, ensure that the following AWS resources are created:

- Virtual Private Cloud (VPC) and subnets
- FSx Lustre volume
- Amazon S3 bucket
- IAM role with required permissions

For a more detailed deployment walkthrough, refer to the [AWS SageMaker HyperPod Workshop](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/00-setup/02-own-account).

To deploy these resources using AWS CloudFormation:

1. Click [this CloudFormation template](https://console.aws.amazon.com/cloudformation/home?#/stacks/quickcreate?templateURL=https://awsome-distributed-training.s3.amazonaws.com/templates/sagemaker-hyperpod.yaml\&stackName=sagemaker-hyperpod) to launch the setup.
2. Update the **availability zone** to match your region (e.g., `us-east-1` → `use1-az4`).
3. Accept the default parameters or modify as needed.
4. Acknowledge capabilities and create the stack.

The setup takes approximately **10 minutes** to complete.

## 3. Deploying SageMaker HyperPod Cluster

For a more detailed deployment walkthrough, refer to the [AWS SageMaker HyperPod Workshop](https://catalog.workshops.aws/sagemaker-hyperpod/en-US/00-setup/02-own-account).

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

Create a cluster configuration file `cluster-config.json`. Below is an example of cluster config for a 2 node cluster of g6e.48xlarge compute nodes

```bash
$ source env_vars
$ cat > cluster-config.json << EOL
{
    "ClusterName": "ml-cluster",
    "InstanceGroups": [
      {
        "InstanceGroupName": "login-group",
        "InstanceType": "ml.m5.4xlarge",
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": 500
            }
          }
        ],
        "InstanceCount": 1,
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET}/src",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${ROLE}",
        "ThreadsPerCore": 2
      },
      {
        "InstanceGroupName": "controller-machine",
        "InstanceType": "ml.m5.12xlarge",
        "InstanceCount": 1,
        "InstanceStorageConfigs": [
          {
            "EbsVolumeConfig": {
              "VolumeSizeInGB": 500
            }
          }
        ],
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET}/src",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${ROLE}",
        "ThreadsPerCore": 2
      },
      {
        "InstanceGroupName": "worker-group-1",
        "InstanceType": "ml.g6e.48xlarge",
        "InstanceCount": 2,
        "LifeCycleConfig": {
          "SourceS3Uri": "s3://${BUCKET}/src",
          "OnCreate": "on_create.sh"
        },
        "ExecutionRole": "${ROLE}",
        "ThreadsPerCore": 1
      }
    ],
    "VpcConfig": {
      "SecurityGroupIds": ["$SECURITY_GROUP"],
      "Subnets": ["$SUBNET_ID"]
    }
}
EOL
```

Create cluster provisioning parameters `provisioning_parameters.json` and upload to S3 to reference during cluster setup:

```bash
$ instance_type=$(jq '.InstanceGroups[] | select(.InstanceGroupName == "worker-group-1").InstanceType' cluster-config.json
$ cat > provisioning_parameters.json << EOL
{
  "version": "1.0.0",
  "workload_manager": "slurm",
  "controller_group": "controller-machine",
  "login_group": "login-group",
  "worker_groups": [
    {
      "instance_group_name": "worker-group-1",
      "partition_name": ${instance_type}
    }
  ],
  "fsx_dns_name": "${FSX_ID}.fsx.${AWS_REGION}.amazonaws.com",
  "fsx_mountname": "${FSX_MOUNTNAME}"
}
EOL
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


## 4. SSH into the Cluster Head node

Once the cluster is in **InService** state, connect using AWS Systems Manager. Install the [AWS SSM Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

```bash
$ ssh-keygen -t rsa -q -f "$HOME/.ssh/id_rsa" -N ""
$ curl -O https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/easy-ssh.sh
$ chmod +x easy-ssh.sh
$ ./easy-ssh.sh -c controller-machine ml-cluster
```

## 5. Clone this repo
```bash
cd /fsx/ubuntu
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/21.nemo-run
```

## 6. Build and Configure the NeMo Job Container

Before running NeMo jobs, build a custom container image and Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in /fsx/ubuntu.

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
$ pip install git+https://github.com/NVIDIA/NeMo-Run.git
$ pip install torch
$ pip install --no-deps git+https://github.com/NVIDIA/Megatron-LM.git
$ wget https://github.com/state-spaces/mamba/releases/download/v2.2.2/mamba_ssm-2.2.2+cu118torch2.1cxx11abiFALSE-cp310-cp310-linux_x86_64.whl
$ pip install mamba_ssm-2.2.2+cu118torch2.1cxx11abiFALSE-cp310-cp310-linux_x86_64.whl
$ pip install nemo_toolkit['nlp'] opencc==1.1.6
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
- [AWS SageMaker HyperPod](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod.html)

