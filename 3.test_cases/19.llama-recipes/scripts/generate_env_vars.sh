#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

cat > .env << EOF
export APPS_PATH=/fsx/ubuntu
export ENROOT_IMAGE=\$APPS_PATH/llama3.sqsh
export FSX_PATH=/fsx
export MODEL_PATH=$FSX_PATH/llama3
export DATA_PATH=$FSX_PATH/data
export TEST_CASE_PATH=\${FSX_PATH}/awsome-distributed-training/3.test_cases/19.llama-recipes
export HF_HOME=${FSX_PATH}/.cache
export WANDB_CONFIG_DIR=${FSX_PATH}
export WANDB_API_KEY=PUT_YOUR_API_KEY_HERE # You need to place your WANDB_API_KEY here 
EOF