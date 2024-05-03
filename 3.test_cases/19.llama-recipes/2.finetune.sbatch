#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name="llama3-finetune"
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --wait-all-nodes=1
#SBATCH --exclusive
set -euxo pipefail
source .env
# default variables for Enroot, if these variables are defined then use them
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/llama3.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
## EFA settings
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_USE_HUGE_PAGE=0
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_SOCKET_IFNAME=en
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
# Some potentially useful distributed environment variables
export HOSTNAMES=`scontrol show hostnames "$SLURM_JOB_NODELIST"`
export MASTER_ADDR=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)
export COUNT_NODE=`scontrol show hostnames "$SLURM_JOB_NODELIST" | wc -l`
export NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
export NODES_ARRAY=($NODES)
export HEAD_NODE=${NODES_ARRAY[0]}
export MASTER_ADDR=$(hostname --ip-address)
export MASTER_PORT=$RANDOM
export NNODES=$SLURM_JOB_NUM_NODES
export NPROC=$SLURM_GPUS_PER_NODE
export WORLD_SIZE=$(( $NNODES * $NPROC ))
export HF_HOME=/fsx/.cache

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

declare -a TORCHRUN_ARGS=(
    # change this to match the number of gpus per node:
    --master_addr $MASTER_ADDR \
    --master_port $RANDOM \
    --nproc_per_node=8 \
    --nnodes $NNODES \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname)
)

declare -a TRAIN_ARGS=(
    --model_name "meta-llama/Meta-Llama-3-70B" \
    --dist_checkpoint_root_folder "/fsx/models/Meta-Llama-3-70B-tuned" \
    --dist_checkpoint_folder fine-tuned \
    --dataset alpaca_dataset --data_path /fsx/data/alpaca_data.json \
    --enable_fsdp True \
    --low_cpu_fsdp \
    --fsdp_activation_checkpointing True \
    --pure_bf16 \
    --use_wandb \
    --num_epochs 1 \
    --batching_strategy padding \
    --run_validation True
)
#     --use_wandb \
export PYTHONPATH=${PWD}/llama-recipes/src
srun -l "${ARGS[@]}" torchrun  "${TORCHRUN_ARGS[@]}" \
    /fsx/awsome-distributed-training/3.test_cases/19.llama-recipes/llama-recipes/recipes/finetuning/finetuning.py \
    "${TRAIN_ARGS[@]}"