#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=internode
#SBATCH --nodes=6
#SBATCH --ntasks-per-node 1
##SBATCH --output %x_%j.out
##SBATCH --error %x_%j.err
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

set -ex;

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

export OMP_NUM_THREADS=8
export PYTHONFAULTHANDLER=1

MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
MASTER_PORT=12355
SLURM_GPUS_PER_NODE=8

srun -l \
    --container-image ./uccl-ep.sqsh \
        torchrun \
            --nnodes=$SLURM_JOB_NUM_NODES \
            --nproc_per_node=$SLURM_GPUS_PER_NODE \
            --rdzv_id=$SLURM_JOB_ID \
            --rdzv_backend=c10d \
            --rdzv_endpoint=$(hostname) \
            bench/test_internode.py \
                --num-tokens=4096 \
                --hidden=7168 \
                --num-topk=8 \
                --num-experts=288 \
                --test-ll-compatibility
