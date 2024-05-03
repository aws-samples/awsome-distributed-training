#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=nccl-all_reduce_perf # name of your job
#SBATCH -N 2
#SBATCH --nodes=2                       # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --ntasks-per-node 8             # Number of tasks that Slurm will spawn on each node
###SBATCH --gpus-per-node=8             # number of GPU we reserve. Uncomment for AWS ParallelCluster
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

##############################################################
###### ATTENTION: Review and change these user variables #####
##############################################################

# default variables for Enroot
: "${IMAGE:=$(pwd)/nccl.sqsh}"
: "${NCCL_TESTS_PATH:=/opt/nccl-tests/build}"

export NCCL_DEBUG=INFO

# https://github.com/open-mpi/ompi/issues/11557#issuecomment-1496245026
export PMIX_MCA_psec=^munge

# https://github.com/open-mpi/ompi/issues/7516#issuecomment-599305327
export PMIX_MCA_gds=^ds12

### Increase the send queue depth and can turn NCCL communications into non-blocking.
### https://www.usenix.org/system/files/atc23-choi.pdf
export NCCL_BUFFSIZE=8388608
### Improve performance by increasing buffer size for Send/Recv, Gather, Scatter and Alltoall communications
### https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/p2p.html
export NCCL_P2P_NET_CHUNKSIZE=524288

declare -a ARGS=(
    --container-image $IMAGE
)

#Get Hostname and Instance IDs
srun -l --ntasks-per-node 1 bash -c 'echo $(hostname): $(cat /sys/devices/virtual/dmi/id/board_asset_tag | tr -d " ")'

# Run NCCL test
srun -l "${ARGS[@]}" --mpi=pmix $NCCL_TESTS_PATH/all_reduce_perf -b 8 -e 16G -f 2 -g 1 -c 1 -n 100
