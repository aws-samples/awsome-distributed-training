#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH -N 1 # number of nodes we want
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

set -exuo pipefail

###########################
###### User Variables #####
###########################

: "${IMAGE:=$(pwd)/megatron-training.sqsh}"
: "${FSX_MOUNT:=/fsx:/fsx}"

# default variables for Enroot
: "${DATA_PATH:=/fsx}"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts $FSX_MOUNT
)

[[ -f ${IMAGE} ]] || { echo "Could not find enroot image: $IMAGE" ; exit -1 ; }
# runs in
srun -l "${ARGS[@]}"  python3 /workspace/Megatron-LM/tools/preprocess_data.py \
        --input ${DATA_PATH}/llama2/oscar-1GB.jsonl \
        --output-prefix ${DATA_PATH}/llama2/my-llama2 \
        --tokenizer-type Llama2Tokenizer \
        --tokenizer-model ${DATA_PATH}/llama2/tokenizer.model \
        --append-eod \
        --workers 64
