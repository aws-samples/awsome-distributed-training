#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name="convert-checkpoint"
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
export HF_HOME=/fsx/.cache

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

declare -a CKPT_ARGS=(
    --fsdp_checkpoint_path /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B 
    --consolidated_model_path /fsx/models/meta-llama/Meta-Llama-3-8B-tuned/fine-tuned-meta-llama/Meta-Llama-3-8B-hf
)

export PYTHONPATH=${PWD}/llama-recipes/src
srun -l "${ARGS[@]}" python ${PWD}/llama-recipes/src/llama_recipes/inference/checkpoint_converter_fsdp_hf.py \
    "${CKPT_ARGS[@]}"
    
    