#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=nccl-all_reduce_perf # name of your job
#SBATCH -N 2
#SBATCH --nodes=2                       # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --ntasks-per-node 1             # Number of tasks that Slurm will spawn on each node
###SBATCH --gpus-per-node=8             # number of GPU we reserve. Uncomment for AWS ParallelCluster
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

set -e
#env

##############################################################
###### ATTENTION: Review and change these user variables #####
##############################################################

# default variables for Enroot
: "${IMAGE:=$(pwd)/nccl.sqsh}"
: "${FSX_MOUNT:=/fsx/ubuntu/:/fsx}"


###########################
## Environment Variables ##
###########################

# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_SOCKET_IFNAME=en
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
export NCCL_BUFFSIZE=16777216
export NCCL_P2P_NET_CHUNKSIZE=1048576
export TORCH_DIST_INIT_BARRIER=1

# async runtime error ...
#export CUDA_DEVICE_MAX_CONNECTIONS=1

echo "START TIME: $(date)"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $FSX_MOUNT
)

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=8
    --nnodes=$SLURM_JOB_NUM_NODES
    --rdzv_id=$SLURM_JOB_ID
    --rdzv_backend=c10d
    --rdzv_endpoint=$(hostname)
    #--max_restarts 0
    #--role `hostname -s`:
    #--tee 3
)

## Pre-requisite: ${FSX_MOUNT} (this is a path inside the container) must contains the .py script
## from https://github.com/stas00/ml-engineering/blob/master/network/benchmarks/all_reduce_bench.py
##
## Sample command to download:
##
##     curl -LO https://raw.githubusercontent.com/stas00/ml-engineering/master/network/benchmarks/all_reduce_bench.py
srun -l --wait 300 "${ARGS[@]}" torchrun "${TORCHRUN_ARGS[@]}" ${FSX_MOUNT}/all_reduce_bench.py

echo "END TIME: $(date)"
