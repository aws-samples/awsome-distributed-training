#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=4 # number of nodes to use
#SBATCH --job-name=FSDP # name of your job
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

set -ex;

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=4 # 4 for G5.12x, 8 for P4/P5

###########################
## Environment Variables ##
###########################

## Plenty of EFA level variables
## Comment out for non-efa instances (G4d, P3)
## For G5.12x, Comment out RDMA and Fork safe
## For G4dn and other G5, comment out all
## export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO
## Switching SYNC_MEMOPS to zero can boost throughput with FSDP
## Disables CU_POINTER_ATTRIBUTE_SYNC_MEMOPS
## Reduces memory synchronizations
## https://docs.nvidia.com/cuda/cuda-driver-api/group__CUDA__UNIFIED.html
## export FI_EFA_SET_CUDA_SYNC_MEMOPS=0

###########################
####### Torch Dist  #######
###########################

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE
    --nnodes=$SLURM_JOB_NUM_NODES
    --rdzv_id=$SLURM_JOB_ID
    --rdzv_backend=c10d
    --rdzv_endpoint=$(hostname)
)

source /fsx/ubuntu/miniconda3/bin/activate
conda activate esm2

export TRAIN_SCRIPT=/fsx/ubuntu/train.py

############################
# Llama 2 Training Params ##
############################

declare -a TRAINING_ARGS=(
    --config_name "facebook/esm2_t30_150M_UR50D" \
    --dataloader_num_workers 8 \
    --bf16 True \
    --do_eval True \
    --do_preprocess False \
    --do_train True \
    --gradient_accumulation_steps 16 \
    --logging_steps 16 \
    --num_train_epochs 1 \
    --output_dir "/fsx//ubuntu/output" \
    --per_device_train_batch_size 8 \
    --max_train_samples 100000 \
    --tokenizer_name "facebook/esm2_t30_150M_UR50D" \
    --dataset_dir "/fsx/ubuntu/processed/arrow/" \
    --torch_compile False \
    --pad_to_max_length True \
    --max_seq_length 512
)

AUTO_RESUME=""
if [ -d "/opt/sagemaker_cluster" ]; then
    echo "Detected Hyperpod cluster.. enabling --auto-resume=1"
    AUTO_RESUME="--auto-resume=1"
fi

srun ${AUTO_RESUME} -l torchrun "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${TRAINING_ARGS[@]}"