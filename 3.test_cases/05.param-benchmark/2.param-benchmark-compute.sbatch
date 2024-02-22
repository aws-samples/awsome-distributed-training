#!/bin/bash

#SBATCH --exclusive # the job has exclusive use of the instances it uses
#SBATCH --gres=gpu:8 # reserve 8 GPU resources / instance / node
#SBATCH --gpus-per-node=8 #
#SBATCH --nodes=1 # how many nodes, you can override on the CLI
#SBATCH --wait-all-nodes=1 # wait for all nodes before running the job
#SBATCH --job-name=param_benchmark # name of your job
#SBATCH --output=%x_%j.out # declare output, merge both stdout and stderr

set -ex;

###########################
###### User Variables #####
###########################

# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${NCCL_TESTS_PATH:=/home/ec2-user/}"
: "${IMAGE:=/apps/param-benchmark.sqsh}"

## Plenty of EFA level variables
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
# export NCCL_ALGO=Ring
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_ENABLE_SHM_TRANSFER=1
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
#export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO


# Matrix multiplication test
srun --container-image=$IMAGE -l python3 /param/train/compute/pt/driver.py \
     --steps=100 --device='cpu' gemm --dataset='A'
srun --container-image=$IMAGE -l python3 /param/train/compute/pt/driver.py \
     --steps=100 --device='gpu' gemm --dataset='A'

# EmbeddingBag
srun --container-image=$IMAGE -l python3 /param/train/compute/pt/driver.py \
     --steps=100 --device='cpu' emb --dataset='A'
srun --container-image=$IMAGE -l python3 /param/train/compute/pt/driver.py \
     --steps=100 --device='gpu' emb --dataset='A'

# MLP Linear
srun --container-image=$IMAGE -l python3 /param/train/compute/pt/driver.py \
     --steps=100 --device='cpu' linear --dataset='A'
srun --container-image=$IMAGE -l python3 /param/train/compute/pt/driver.py \
     --steps=100 --device='gpu' linear --dataset='A'
