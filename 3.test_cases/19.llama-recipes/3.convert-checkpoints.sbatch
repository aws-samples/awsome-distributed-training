#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name="convert-checkpoint"
#SBATCH --nodes=1
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
export HF_HOME=/fsx/.cache

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

declare -a HELP=(
    "[--help]"
    "[--fsdp_checkpoint_path]"
    "[--port]"
    "[--consolidated_model_path]"
)

parse_args() {
    local key
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        --help)
            echo "Launch Gradio App locally, querying endpoint hosted on a compute node" 
            echo "It requires endpoint pre-deployed. Use 4.serve-vllm.sbatch for deployment" 
            echo "Usage: $(basename ${BASH_SOURCE[0]}) ${HELP[@]}"
            exit 0
            ;;
        --fsdp_checkpoint_path)
            FSDP_CHECKPOINT_PATH="$2"
            shift 2
            ;;
        --consolidated_model_path)
            CONSOLIDATED_MODEL_PATH="$2"
            shift 2
            ;;
        esac
    done
}

parse_args $@

declare -a CKPT_ARGS=(
    --fsdp_checkpoint_path ${FSDP_CHECKPOINT_PATH}
    --consolidated_model_path ${CONSOLIDATED_MODEL_PATH}
)

export PYTHONPATH=${PWD}/llama-recipes/src
srun -l "${ARGS[@]}" python ${PWD}/llama-recipes/src/llama_recipes/inference/checkpoint_converter_fsdp_hf.py \
    "${CKPT_ARGS[@]}"
    
    