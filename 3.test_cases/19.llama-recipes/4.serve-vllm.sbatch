#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name="serve-vllm"
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
set -euxo pipefail
source .env
# default variables for Enroot, if these variables are defined then use them
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/llama3.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
## EFA settings
#export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_USE_HUGE_PAGE=0
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_SOCKET_IFNAME=en
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
#export NCCL_DEBUG=INFO
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

export PYTHONPATH=${PWD}/llama-recipes/src
export MODEL=meta-llama/Meta-LLama-3-70B


declare -a HELP=(
    "[--help]"
    "[--model]"
    "[--tp]"
)

parse_args() {
    local key
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        --help)
            echo "Deploy Llama model using VLLM API server" 
            echo "Usage: $(basename ${BASH_SOURCE[0]}) ${HELP[@]}"
            exit 0
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --tp)
            TP="$2"
            shift 2
            ;;
        esac
    done
}

parse_args $@


# To avoid ImportError: /usr/local/lib/python3.10/dist-packages/transformer_engine_extensions.cpython-310-x86_64-linux-gnu.so: undefined symbol:
# error we remove transformer_engine on the fly
srun -l "${ARGS[@]}" bash -c "pip uninstall -y transformer_engine && python -m vllm.entrypoints.openai.api_server --model ${MODEL} --tensor-parallel-size 8"