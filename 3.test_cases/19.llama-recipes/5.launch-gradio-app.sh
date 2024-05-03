#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name="serve-gradio"
#SBATCH --nodes=1
set -euxo pipefail
source .env
: "${FSX_PATH:=/fsx}"
: "${APPS_PATH:=${FSX_PATH}/apps}"
: "${IMAGE:=$APPS_PATH/llama3.sqsh}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
export HF_HOME=/fsx/.cache

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

declare -a HELP=(
    "[--help]"
    "[--host]"
    "[--port]"
    "[--model-url]"
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
        --host)
            HOST="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        esac
    done
}

parse_args $@

MODEL_URL="http://${HOST}:8000/v1/models/llama3:predict"
enroot start --env NVIDIA_VISIBLE_DEVICES=void \
    --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
    python ${PWD}/src/gradio_chat.py --host ${HOST} --port ${PORT} --model ${MODEL}
