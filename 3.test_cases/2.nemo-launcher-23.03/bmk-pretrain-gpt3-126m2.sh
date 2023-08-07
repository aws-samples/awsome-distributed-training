#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Override the default values in the underlying step-02-bmk-pretrain-gpt3.sh script.
# See that underlying script to learn about the defaults.

export MODEL_SIZE=126m
export NUM_NODES=2
export RUNTIME=30m
export MAX_STEPS=40
export UNIQUE_OUTPUT_DIR=1

BIN_DIR=$(dirname `readlink -e ${BASH_SOURCE[0]}`)

# Node_count == 8 can work without full activations checkpointing.
$BIN_DIR/step-02-bmk-pretrain-gpt3.sh \
    training.model.data.data_prefix=[1.0,\${data_dir}/my-gpt3_00_text_document]
