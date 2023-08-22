#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -exuo pipefail

CONT_DATA_DIR=${TARGET_PATH}/data/the_pile_gpt3
CONT_TOKENIZER_DIR=${TARGET_PATH}/data/bpe

# data_preparation.file_numbers='0-29' \
mkdir -p $CONT_DATA_DIR
HYDRA_FULL_ERROR=1 python3 $TARGET_PATH/launcher_scripts/main.py \
    stages=[data_preparation] \
    data_dir=$CONT_DATA_DIR \
    data_preparation.file_numbers='0-0' \
    data_preparation.vocab_save_dir=$CONT_TOKENIZER_DIR \
    data_preparation.merges_save_dir=$CONT_TOKENIZER_DIR \
    data_preparation.run.node_array_size=1
