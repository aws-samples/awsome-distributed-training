#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

#SBATCH -N 1 # number of nodes we want
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

###########################
###### User Variables #####
###########################

: "${IMAGE:=$APPS_PATH/megatron-preprocess.sqsh}"
: "${FSX_MOUNT:=/fsx/gpt2:/fsx}"

# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${DATA_PATH:=/fsx}"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts $FSX_MOUNT
)

# runs in
srun -l "${ARGS[@]}"  python3 /workspace/Megatron-LM/tools/preprocess_data.py \
        --input ${DATA_PATH}/oscar-1GB.jsonl \
        --output-prefix ${DATA_PATH}/my-gpt2 \
        --vocab-file ${DATA_PATH}/gpt2-vocab.json \
        --tokenizer-type GPT2BPETokenizer \
        --merge-file ${DATA_PATH}/gpt2-merges.txt \
        --append-eod \
        --workers 64
