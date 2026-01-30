#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=pplx-garden
#SBATCH --nodes=2
#SBATCH --ntasks-per-node 1
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

#Get Hostname and Instance IDs
mpirun -N 1 bash -c 'echo $(hostname): $(cat /sys/devices/virtual/dmi/id/board_asset_tag | tr -d " ")'

export MASTER_PORT=29500
export MASTER_ADDR=$(scontrol show hostname ${SLURM_NODELIST} | head -n 1)
export NUM_NODES=${SLURM_NNODES}
export NUM_GPUS=8

export PYTHONPATH=/opt/uccl/ep/bench:$PYTHONPATH

srun -l \
    --container-image ./pplx-garden_uccl-ep.sqsh \
    --container-mounts ./uccl_bench_all_to_all.py:/app/benchmarks/uccl_bench_all_to_all.py \
    --mpi=pmix --cpu-bind=none \
    bash -c 'python3 -X faulthandler -m benchmarks.uccl_bench_all_to_all \
        --world-size $((NUM_NODES * NUM_GPUS)) \
        --nets-per-gpu 2 \
        --init-method=tcp://${MASTER_ADDR}:${MASTER_PORT} \
        --node-rank=${SLURM_NODEID} \
        --nvlink=8 \
        --max-num-tokens 128 \
        --use-uccl'
