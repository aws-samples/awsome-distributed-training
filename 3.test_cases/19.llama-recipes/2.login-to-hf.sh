#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH -N 1 # number of nodes to use
#SBATCH --job-name=llama3-chat # name of your job

: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/llama3.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${DATA_PATH:=$FSX_PATH/$DATASET}"
: "${HF_HOME:=$FSX_PATH/.cache}

declare -a ARGS=(
    --container-image ${IMAGE}
    --container-mounts /fsx
)
export WORLD_SIZE=8
export MASTER_ADDR=127.0.0.1
export MASTER_PORT=$((RANDOM + 10001))
srun -N1 --exclusive "${ARGS[@]}" --pty torchrun ${PWD}/llama/example_chat_completion.py /fsx/models/llama3/7b /fsx/models/llama3/7b/tokenizer.model