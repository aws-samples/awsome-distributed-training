#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -exuo pipefail

: "${WORKSPACE_CONT:=/scratch/ubuntu/nemo-megatron-23.03}"
CONT_DATA_DIR=${WORKSPACE_CONT}/data/the_pile_gpt3
CONT_TOKENIZER_DIR=${WORKSPACE_CONT}/data/bpe

# data_preparation.file_numbers='0-29' \
mkdir -p $CONT_DATA_DIR
HYDRA_FULL_ERROR=1 python3 /admin/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/launcher_scripts/main.py \
    stages=[data_preparation] \
    data_dir=$CONT_DATA_DIR \
    data_preparation.file_numbers='0-0' \
    data_preparation.vocab_save_dir=$CONT_TOKENIZER_DIR \
    data_preparation.merges_save_dir=$CONT_TOKENIZER_DIR \
    data_preparation.run.node_array_size=1
