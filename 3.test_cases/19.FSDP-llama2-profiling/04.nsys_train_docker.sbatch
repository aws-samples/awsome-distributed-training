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


###########################
######### Enroot  #########
###########################

# default variables for Enroot
: "${IMAGE:=$(pwd)/${ENROOT_IMAGE}}"
: "${DATA_PATH:=/fsx}"
: "${FSX_MOUNT:=$DATA_PATH:$DATA_PATH}"

declare -a ENROOT_ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts $FSX_MOUNT
)

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

export TRAIN_SCRIPT=/workspace/training.py

##################################
# Llama 2 Model Training Params ##
##################################

declare -a MODEL_ARGS=(
    --ckpt_load_path=/fsx/llama2/pretrain/ckpt
    --ckpt_save_path=/fsx/llama2/pretrain/ckpt
    --data_path=/fsx/data/
    --fsdp_activation_checkpointing=False
    --selective_checkpointing=1
    --sharding_strategy=hsdp
    --low_cpu_fsdp=False
    --batch_size=2
    --report_interval=200
    --checkpoint_interval=20000
    --use_torch_compile=False
    --use_profiler=False
)


srun -l "${ENROOT_ARGS[@]}" /usr/local/cuda/bin/nsys profile \
        --sample none --delay 30 --duration 1200 --force-overwrite true \
        --output /fsx/nsys_profiles/report_llama2_job%q{SLURM_JOB_ID}_rank%q{SLURM_PROCID}_on_%q{HOSTNAME}.nsys-rep torchrun \
        "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${MODEL_ARGS[@]}"
