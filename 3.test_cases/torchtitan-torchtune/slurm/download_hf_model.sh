#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
set -exuo pipefail

if [ ! -f .env ]
then
    echo "Please create a .env file with the required environment variables"
    exit 1
else
    source .env
fi

if [ ! -d ${MODEL_PATH} ]
then
    mkdir -p ${MODEL_PATH}
fi

: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
declare -a SRUN_ARGS=(
    --container-image $ENROOT_IMAGE
    --container-mounts $CONTAINER_MOUNT
)
export TORCHTUNE=${PWD}/torchtune/torchtune/_cli/tune.py

enroot start --env NVIDIA_VISIBLE_DEVICES=void --env PYTHONPATH=${PWD}/torchtune --env HF_HOME=${HF_HOME} \
    --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
    python ${TORCHTUNE} download \
    --output-dir ${MODEL_PATH}/${HF_MODEL} ${HF_MODEL} \
     --ignore-patterns "original/consolidated*"

