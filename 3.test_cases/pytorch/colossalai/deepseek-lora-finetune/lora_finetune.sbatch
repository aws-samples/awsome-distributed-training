#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=3
#SBATCH --job-name=ds_lora
##SBATCH --output=logs/%x_%j.out
##SBATCH --error=logs/%x_%j.err
#SBATCH --exclusive

set -ex;

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=8

###########################
## Environment Variables ##
###########################

## Plenty of EFA level variables
## For G4dn and other G5, comment out all
#export FI_LOG_LEVEL=warn
# export NCCL_DEBUG=INFO
export FI_PROVIDER=efa
export FI_EFA_USE_HUGE_PAGE=0    # Set to 0 when you see os.fork() causes OSError: Cannot allocate memory.  Disabling huge page causes minor performance hit.
## Switching SYNC_MEMOPS to zero can boost throughput with FSDP
## Disables CU_POINTER_ATTRIBUTE_SYNC_MEMOPS
## Reduces memory synchronizations
## https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__UNIFIED.html
export FI_EFA_SET_CUDA_SYNC_MEMOPS=0

srun -l \
    --container-image ../colossalai.sqsh \
    --container-mounts ./:/workdir \
    torchrun \
    --nproc_per_node=$GPUS_PER_NODE \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_id=$SLURM_JOB_ID \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname) \
    /workdir/lora_finetune.py \
        --pretrained /workdir/ds-prover-v2-bf16 \
        --dataset AI-MO/NuminaMath-TIR \
        --dataset_split train \
        --plugin moe \
        --lr 1e-4 \
        --max_length 8192 -g \
        --ep 8 \
        --pp 3 \
        --batch_size 4 \
        --lora_rank 8 \
        --lora_alpha 16 \
        --num_epochs 2 \
        --warmup_steps 8 \
        --tensorboard_dir /workdir/logs \
        --save_dir /workdir/ds-prover-v2-bf16-lora
