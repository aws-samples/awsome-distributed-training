# Pretrain Mamba with SageMaker HyperPod


|Num|                                    Mamba State Space Models                                  |
|:-:|:--------------------------------------------------------------------------------------------:|
| 1 |      [Mamba-2.8B](https://huggingface.co/state-spaces/mamba-2.8b-hf)                         |
| 2 |      [Mamba-1.4B](https://huggingface.co/state-spaces/mamba-1.4b-hf)                         |
| 3 |      [Mamba-790m](https://huggingface.co/state-spaces/mamba-790m-hf)                         |
| 4 |      [Mamba-370m](https://huggingface.co/state-spaces/mamba-370m-hf)                         |


This project provides a guide to run [Mamba State Space Models](https://huggingface.co/state-spaces) on AWS SageMaker Hyperpod.


## 0. Prerequisites

0. Have a SageMaker Hyperpod (SMHP) cluster created with a FSx for Lustre filesystem mounted. You can find instructions on setting up SMHP cluster in [5.sagemaker-hyperpod](https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod).

curl 'https://static.us-east-1.prod.workshops.aws/public/a9eec875-ea65-4695-b4dc-edbe50b98670/static/scripts/create_config.sh' --output create_config.sh
bash create_config.sh
source env_vars

1. Install git-lfs

If you are using Amazon Linux, make sure that amazon-linux-extras package is installed:

```bash
$ which amazon-linux-extras
```

If the package is not installed, you can use yum to install it:

```bash
$ sudo yum install -y amazon-linux-extras
```

git-lfs is part of the epel release, which needs to be installed first:

```bash
$ sudo amazon linux-extras install epel -y
```

Next, enable the epel repo:

```bash
$ sudo yum-config-manager --enable epel
```

Then install git-lfs:
```bash
$ sudo yum install git-lfs
```

2. Download the dataset to fsx directory

```bash
$ cd fsx
$ mkdir data
$ cd data
$ git lfs clone https://huggingface.co/datasets/malaysia-ai/mosaic-combine-all
