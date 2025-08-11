#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=15
#SBATCH --job-name=lora_ft
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

MODEL_NAME=$1
MODEL_PATH=/workdir/$MODEL_NAME-bf16
DATASET=$2
DATASET_SPLIT=$3
LOG_DIR=/workdir/$MODEL_NAME-bf16-logs
LORA_DIR=/workdir/$MODEL_NAME-bf16-lora

export PYTHONFAULTHANDLER=1
export OMP_NUM_THREADS=8

srun -l \
    --mpi=pmix --cpu-bind=none \
    --container-image ../colossalai.sqsh \
    --container-mounts ./:/workdir,$HF_HOME:$HF_HOME \
    torchrun \
    --nproc_per_node=$GPUS_PER_NODE \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_id=$SLURM_JOB_ID \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname) \
    /workdir/lora_finetune.py \
        --pretrained $MODEL_PATH \
        --dataset $DATASET \
        --dataset_split $DATASET_SPLIT \
        --plugin moe \
        --lr 1e-4 \
        --max_length 2048 \
        -g \
        --ep 8 \
        --pp 3 \
        --batch_size 8 \
        --lora_rank 8 \
        --lora_alpha 16 \
        --num_epochs 1 \
        --warmup_steps 8 \
        --tensorboard_dir $LOG_DIR \
        --save_dir $LORA_DIR
