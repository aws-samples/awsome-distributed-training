#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

#SBATCH -N 2 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --job-name=megatron_gpt # name of your job
#SBATCH --ntasks-per-node 8 # Number of GPU per node
#SBATCH --gres=gpu:8 # number of GPU we reserve
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1
#SBATCH --export=NIL # do not export env vars from the host env

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

###########################
###### User Variables #####
###########################


# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${NCCL_TESTS_PATH:=/opt/nccl-tests/build}"

: "${IMAGE:=$APPS_PATH/nccl.sqsh}"

## Plenty of EFA level variables
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1

# export NCCL_ALGO=Ring
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_ENABLE_SHM_TRANSFER=1

# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
export NCCL_DEBUG_FILE=nccl-debug-%h-%p.txt

declare -a ARGS=(
    --container-image $IMAGE
)


echo "
Hostname: $(hostname)
"

env


echo "
################################################################################
# $NCCL_TEST_PATH/all_reduce_perf
################################################################################
"
srun -l "${ARGS[@]}" --mpi=pmix $NCCL_TEST_PATH/all_reduce_perf -b 8 -e 1G -f 2 -g 1 -c 1 -n 100

sleep 5
echo "
################################################################################
# $NCCL_TEST_PATH/all_gather_perf
################################################################################
"
srun -l "${ARGS[@]}" --mpi=pmix $NCCL_TEST_PATH/all_gather_perf -b 8 -e 1G -f 2 -g 1 -c 1 -n 100

sleep 5
echo "
################################################################################
# $NCCL_TEST_PATH/reduce_scatter_perf
################################################################################
"
srun -l "${ARGS[@]}" --mpi=pmix $NCCL_TEST_PATH/reduce_scatter_perf -b 8 -e 1G -f 2 -g 1 -c 1 -n 100
