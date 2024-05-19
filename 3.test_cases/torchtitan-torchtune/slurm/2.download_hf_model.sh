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

enroot start --env NVIDIA_VISIBLE_DEVICES=void \
    --mount ${FSX_PATH}:${FSX_PATH} ${ENROOT_IMAGE} \
    tune
    download \
    ${HF_MODEL} \
    --hf-token ${HF_HOME}/token \
    --output-dir ${MODEL_PATH}/${HF_MODEL} 
