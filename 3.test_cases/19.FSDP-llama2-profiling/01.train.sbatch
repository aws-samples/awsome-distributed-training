#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=2 # number of nodes to use
#SBATCH --job-name=LLAMA2_FSDP # name of your job
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

set -ex;

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=8 # 4 for G5.12x, 8 for P4/P5

###########################
## Environment Variables ##
###########################

## Plenty of EFA level variables
## Comment out for non-efa instances (G4d, P3)
## For G5.12x, Comment out RDMA and Fork safe
## For G4dn and other G5, comment out all
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1

#export NCCL_SOCKET_IFNAME=ens
#export OMP_NUM_THREADS=4
#export FI_EFA_SET_CUDA_SYNC_MEMOPS=0
#export NCCL_CUMEM_ENABLE=0 
#export CUDA_DEVICE_MAX_CONNECTIONS=1

###########################
####### Torch Dist  #######
###########################

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_id=$SLURM_JOB_ID \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname) \
)

export TRAIN_SCRIPT=training.py

##################################
# Llama 2 Model Training Params ##
##################################

declare -a MODEL_ARGS=(
    --model_name=llama2_7b
    --load_ckpt_path=/fsx/llama2/pretrain/ckpt
    --save_ckpt_path=/fsx/llama2/pretrain/ckpt
    --data_path=/fsx/data/
    --fsdp_activation_checkpointing=True
    --selective_checkpointing=1
    --sharding_strategy=fsdp
    --batch_size=2
    --learning_rate=3e-4
    --grad_clip_thresh=4.0
    --num_steps=1200
    --report_interval=200
    --checkpoint_interval=20000
    --use_profiler=True
)

#export TORCH_DIST_INIT_BARRIER=1

srun -l torchrun "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${MODEL_ARGS[@]}"
