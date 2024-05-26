#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
set -euo pipefail

if [ ! -f .env ]
then
    echo "Please create a .env file with the required environment variables"
    exit 1
else
    source .env
fi

declare -a HELP=(
    "Download a Hugging Face model to ${MODEL_PATH} using torchtune"
    "Usage: download_hf_model.sh [options]"
    ""
    "Options:"
    "  -h, --help"
    "      Print this help message"
    "  -m, --model"
    "      Hugging Face model name"
)
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                for line in "${HELP[@]}"; do
                    echo "$line"
                done
                exit 0
                ;;
            -m|--model)
                shift
                HF_MODEL=$1
                ;;
            *)
                echo "Unknown argument: $1"
                exit 1
                ;;
        esac
        shift
    done
}
parse_args "$@"

if [ ! -d ${MODEL_PATH} ]
then
    mkdir -p ${MODEL_PATH}
fi

: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
declare -a SRUN_ARGS=(
    --container-image $ENROOT_IMAGE
    --container-mounts $CONTAINER_MOUNT
)
declare -a TORCHTUNE_ARGS=(
    --output-dir ${MODEL_PATH}/${HF_MODEL}
    ${HF_MODEL}
)
if [ ${HF_MODEL} = "meta-llama/Meta-Llama-3-70B" ]
then
    # https://github.com/pytorch/torchtune#multi-gpu
    TORCHTUNE_ARGS+=("--ignore-patterns" "original/consolidated*")
fi
echo "Executing following command:"
echo "torchtune download ${TORCHTUNE_ARGS[@]}"


export TORCHTUNE=${PWD}/torchtune/torchtune/_cli/tune.py
enroot start --env NVIDIA_VISIBLE_DEVICES=void --env PYTHONPATH=${PWD}/torchtune --env HF_HOME=${HF_HOME} \
    --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
    python ${TORCHTUNE} download \
    ${TORCHTUNE_ARGS[@]}

