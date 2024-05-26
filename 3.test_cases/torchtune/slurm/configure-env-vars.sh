#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

echo "Setting up environment variables"

### READ INPUTS
WANDB_API_KEY=$(bash -c 'read -p "Please enter your WANDB_API_KEY: " && echo $REPLY')
HF_KEY=$(bash -c 'read -p "Please enter your HF_KEY: " && echo $REPLY')

### SET TEST CASE PATH
echo "export FSX_PATH=/fsx/${USER}" > .env
source .env
echo "export APPS_PATH=${FSX_PATH}/apps" >> .env
source .env
echo "export MODEL_PATH=${FSX_PATH}/models/torchtune" >> .env
source .env
echo "export TEST_CASE_PATH=${FSX_PATH}/awsome-distributed-training/3.test_cases/torchtune/slurm" >> .env
source .env

### Configure HF_HOME
# https://huggingface.co/docs/huggingface_hub/package_reference/environment_variables
export HF_HOME=${FSX_PATH}/.cache/huggingface
if [ ! -d "${HF_HOME}" ]; then
    mkdir -p ${HF_HOME}
fi
echo "export HF_HOME=${HF_HOME}" >> .env
source .env
echo ${HF_KEY} > ${HF_HOME}/token

### Configure WANDB
# https://docs.wandb.ai/ja/guides/track/environment-variables
export WANDB_CACHE_DIR=${FSX_PATH}/.cache/wandb
if [ ! -d "${WANDB_CACHE_DIR}" ]; then
    mkdir -p ${WANDB_CACHE_DIR}
fi
echo "export WANDB_CACHE_DIR=${WANDB_CACHE_DIR}" >> .env
source .env
export WANDB_DIR=${MODEL_PATH}/wandb
if [ ! -d "${WANDB_DIR}" ]; then
    mkdir -p ${WANDB_DIR}
fi
echo "export WANDB_DIR=${WANDB_DIR}" >> .env
source .env
echo "export WANDB_API_KEY=${WANDB_API_KEY}" >> .env
source .env

### Epilogue
echo ".env file created successfully"
echo "Please run the following command to set the environment variables"
echo "source .env"