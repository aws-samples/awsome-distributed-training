#!/bin/bash

#SBATCH -N 1 # number of nodes we want
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

###########################
###### User Variables #####
###########################

: "${IMAGE:=$APPS_PATH/megatron-preprocess.sqsh}"
: "${FSX_MOUNT:=/fsx:/fsx}"

# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${DATA_PATH:=/fsx/gpt2}"

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
        --dataset-impl mmap \
        --tokenizer-type GPT2BPETokenizer \
        --merge-file ${DATA_PATH}/gpt2-merges.txt \
        --append-eod \
        --workers 64
