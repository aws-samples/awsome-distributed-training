#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

#SBATCH -N 2 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --job-name=megatron_gpt # name of your job
#SBATCH --ntasks-per-node 8 # Number of GPU per node
#SBATCH --gres=gpu:8 # number of GPU we reserve
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

set -ex

# Validate that mpirun does not need -x to propagate env vars defined in .sbatch script

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
#export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO

declare -a ARGS=(
    --container-image $IMAGE
)

echo "
Hostname: $(hostname)
"

env

echo "
########################################
# srun
########################################"
srun -l "${ARGS[@]}" --mpi=pmix bash -c 'hostname ; env | egrep "^NCCL|^FI|^HELLO" | sed "s/^/`hostname`: /g"'

echo "
########################################
# mpirun (WITHOUT -x)
########################################"
mpirun --tag-output bash -c 'hostname ; env | egrep "^NCCL|^FI|^HELLO" | sed "s/^/`hostname`: /g"'
