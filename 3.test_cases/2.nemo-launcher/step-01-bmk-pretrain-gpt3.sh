#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -exuo pipefail

: "${MODEL:=gpt3}"
: "${MODEL_SIZE:=5b}"
: "${NUM_NODES:=8}"
: "${RUNTIME:=4h}"
: "${MAX_STEPS:=5}"
: "${WORKSPACE_CONT:=/fsx/ubuntu/nemo-megatron-23.07}"
CONT_RESULT_DIR=${WORKSPACE_CONT}/results

: "${UNIQUE_OUTPUT_DIR:=0}"

if [[ ${UNIQUE_OUTPUT_DIR} -eq 1 ]]; then
    # For debugging: each run has its own output dir.
    TIMESTAMP=$(date +'%Y%m%d-%H%M%Sutc-%N')-$((RANDOM))
    CONT_RESULT_DIR=${CONT_RESULT_DIR}-${TIMESTAMP}
fi

echo "
####################
This run will write to directory ${CONT_RESULT_DIR}
####################
"

declare -a BMK_ARGS=(
    # Disable validation, as we're only interested to measure the training time.
    training.trainer.limit_val_batches=0.0

    # Ignore checkpoints
    training.exp_manager.create_checkpoint_callback=False
    training.exp_manager.resume_if_exists=False

    # https://github.com/NVIDIA/NeMo/pull/6181/files
    training.model.data.data_impl=mock
    training.model.data.data_prefix=[]
)

#    base_results_dir=${CONT_RESULT_DIR} \
HYDRA_FULL_ERROR=1 python3 /fsx/ubuntu/nemo-launcher-23.07/launcher_scripts/main.py \
    stages=[training] \
    training=${MODEL}/${MODEL_SIZE} \
    training.trainer.num_nodes=$NUM_NODES \
    training.trainer.max_steps=$MAX_STEPS \
    training.trainer.val_check_interval=$MAX_STEPS \
    "${BMK_ARGS[@]}" \
    "$@"
