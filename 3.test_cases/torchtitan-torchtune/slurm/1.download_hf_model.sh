#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# set -ex;

# Default value for HF_MODEL
DEFAULT_HF_MODEL="meta-llama/Llama-2-7b"
read -p "Please enter Hugging Face model ($DEFAULT_HF_MODEL): " HF_MODEL
if [ -z "$HF_MODEL" ]; then
    HF_MODEL="$DEFAULT_HF_MODEL"
fi

read -p "Please enter Hugging Face Access Tokens: " HF_TOKEN

mkdir -p models/${HF_MODEL}

tune download \
    ${HF_MODEL} \
    --output-dir models/${HF_MODEL} \
    --hf-token ${HF_TOKEN}
