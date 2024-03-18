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

## 1. Create Environment

On your cluster head node, 
1. Navigate to your shared FSx for Lustre file system.
* If you followed the tutorial linked above, it will be location at `/fsx`.   
2. Clone this repo. 

```
cd /fsx
git clone https://github.com/aws-samples/awsome-distributed-training/
cd awsome-distributed-training/3.test_cases/16.mamba-fsdp
```

3. Run the `0.create_conda_env.sh` script. 
* This script will first download and install [Miniconda](https://docs.conda.io/projects/miniconda/en/latest/), then create a Conda env called `mambapretrain`.

```
bash 0.create_conda_env.sh
```

* By creating this environment on the shared FSx for Lustre volume, all compute nodes in our cluster will have access to it.

## 2. Launch Training

The script to launch a Mamba Slurm batch training job can be found in `1.dist-training.sbatch`. You can adjust the number of training nodes by modifying `#SBATCH --nodes=4`. 

If you are using a non-RDMA enable instance, such as G5.12x, comment out lines 21-22. These instances have EFA between nodes, but do not have the GPU direct RDMA access of P4d and P5 instances.

```
## Plenty of EFA level variables
## Comment out for non-efa instances (G5, G4d, P3)
# export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
# export FI_EFA_FORK_SAFE=1
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO
```

If you are using non-EFA enabled instances, such as G4dn, or single GPU G5 nodes, comment out all EFA environment variables on lines 21-25.

Also, under `User Variables` make sure to adjust `GPUS_PER_NODE` to match the number of GPUs on your instance type (8 for P4d/P5, 4 for G5.12xlarge, 1 for G5.xlarge).

To launch your training, run

```
sbatch 1.distributed_training.sbatch
```

You'll find a new file in the Mamba-fsdp directory of the form `slurm-[job-number].out`. This will be continuously updated with your training logs. Don't be worried if you see a long stream of NCCL logs (we prefer to use `NCCL_DEBUG=INFO` for verbose logging). After about a minute, you should see your model training, with an output similar to below.