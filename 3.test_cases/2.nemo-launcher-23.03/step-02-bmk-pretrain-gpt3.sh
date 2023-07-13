#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -exuo pipefail

: "${MODEL:=gpt3}"
: "${MODEL_SIZE:=5b}"
: "${NUM_NODES:=8}"
: "${RUNTIME:=4h}"
: "${MAX_STEPS:=5}"
: "${WORKSPACE_CONT:=/scratch/ubuntu/nemo-megatron-23.03}"
CONT_DATA_DIR=${WORKSPACE_CONT}/data/the_pile_gpt3
CONT_TOKENIZER_DIR=${WORKSPACE_CONT}/data/bpe
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
)

HYDRA_FULL_ERROR=1 python3 /admin/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/launcher_scripts/main.py \
    stages=[training] \
    training=${MODEL}/${MODEL_SIZE} \
    data_dir=${CONT_DATA_DIR} \
    base_results_dir=${CONT_RESULT_DIR} \
    training.trainer.num_nodes=$NUM_NODES \
    training.trainer.max_steps=$MAX_STEPS \
    training.trainer.val_check_interval=$MAX_STEPS \
    training.model.tokenizer.vocab_file=${CONT_TOKENIZER_DIR}/vocab.json \
    training.model.tokenizer.merge_file=${CONT_TOKENIZER_DIR}/merges.txt \
    "${BMK_ARGS[@]}" \
    "$@"
