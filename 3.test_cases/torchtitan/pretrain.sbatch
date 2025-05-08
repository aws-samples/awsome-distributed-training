#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=pretrain
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --wait-all-nodes=1
#SBATCH --exclusive
set -euxo pipefail

##################################################################
############# Load environment variables #########################
##################################################################
# Load environment variables
if [ ! -f .env ]
then
    echo "Please create a .env file with the required environment variables"
    exit 1
else
    source .env
fi

##################################################################
######### Define EFA/NCCL/Slurm environment variables ############
##################################################################
## EFA settings
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_USE_HUGE_PAGE=0
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_SOCKET_IFNAME=en
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
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

##################################################################
############### Create train config ##############################
##################################################################

if [ ! -d ${FSX_PATH}/tmp ]; then
    mkdir -p ${FSX_PATH}/tmp
fi
cat ${PWD}/train_configs/pretrain_llama3_70b.toml | envsubst > ${FSX_PATH}/tmp/pretrain_llama3_70b.toml

##################################################################
################# Set arguments ##################################
##################################################################

: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
declare -a SRUN_ARGS=(
    --container-image $ENROOT_IMAGE
    --container-mounts $CONTAINER_MOUNT
)
declare -a TORCHRUN_ARGS=(
    # change this to match the number of gpus per node:
    --master_addr $MASTER_ADDR 
    --master_port $RANDOM 
    --nproc_per_node=8 
    --nnodes $NNODES 
    --nnodes=$SLURM_JOB_NUM_NODES 
    --rdzv_backend=c10d 
    --rdzv_endpoint=$(hostname)
)
declare -a TRAIN_ARGS=(
    --job.config_file ${FSX_PATH}/tmp/pretrain_llama3_70b.toml
)

srun -l "${SRUN_ARGS[@]}" \
    torchrun "${TORCHRUN_ARGS[@]}" ${PWD}/../torchtitan/train.py "${TRAIN_ARGS[@]}"