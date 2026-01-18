#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=pplx-ker
#SBATCH --nodes=2
#SBATCH --ntasks-per-node 8
##SBATCH --output %x_%j.out
##SBATCH --error %x_%j.err
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

set -ex;

### Disable hyperthreading by setting the tasks per core to 1
##SBATCH --ntasks-per-core=1

###########################
###### User Variables #####
###########################

## Set libfabric flags to use EFA
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1

## Set this flag for debugging EFA
# export FI_LOG_LEVEL=warn

## NCCL Environment variables
# export NCCL_DEBUG=INFO
# export NCCL_DEBUG_SUBSYS=ALL

### Increase the send queue depth and can turn NCCL communications into non-blocking.
### https://www.usenix.org/system/files/atc23-choi.pdf
export NCCL_BUFFSIZE=8388608
### Improve performance by increasing buffer size for Send/Recv, Gather, Scatter and Alltoall communications
### https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/p2p.html
export NCCL_P2P_NET_CHUNKSIZE=1048576

### Improve performance for AllReduce by selecting specific protocol and algorithm for specific
### message size and number of ranks.
### More information https://github.com/aws/aws-ofi-nccl/wiki/Algorithm-and-Protocol-Tuner-for-AWS.
export NCCL_TUNER_PLUGIN=/opt/amazon/ofi-nccl/lib/x86_64-linux-gnu/libnccl-ofi-tuner.so

export NVSHMEM_DIR=/opt/nvshmem

export LD_LIBRARY_PATH=/opt/nvshmem/lib:$LD_LIBRARY_PATH

export NVSHMEM_BOOTSTRAP_PMI=PMIX

# export NVSHMEM_DEBUG=TRACE
# export NVSHMEM_DEBUG_SUBSYS=ALL

export NVSHMEM_REMOTE_TRANSPORT=libfabric
export NVSHMEM_LIBFABRIC_PROVIDER=efa

#Get Hostname and Instance IDs
mpirun -N 1 bash -c 'echo $(hostname): $(cat /sys/devices/virtual/dmi/id/board_asset_tag | tr -d " ")'

export MASTER_PORT=29500
export MASTER_ADDR=$(scontrol show hostname ${SLURM_NODELIST} | head -n 1)
export WORLD_SIZE=${SLURM_NPROCS}

export PYTHONFAULTHANDLER=1

srun --container-image ./pplx-kernels.sqsh \
    --mpi=pmix --cpu-bind=none \
    --container-mounts=$(pwd)/coredump:/tmp/coredump,$(pwd)/data:/pplx-kernels/data \
    bash -c "RANK=\${SLURM_PROCID} python3 -X faulthandler launch_bench_all_to_all.py"