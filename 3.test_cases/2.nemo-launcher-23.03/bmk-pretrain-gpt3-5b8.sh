#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Override the default values in the underlying step-02-bmk-pretrain-gpt3.sh script.
# See that underlying script to learn about the defaults.

export NUM_NODES=8
export RUNTIME=30m
export MAX_STEPS=40
export UNIQUE_OUTPUT_DIR=1

BIN_DIR=$(dirname `readlink -e ${BASH_SOURCE[0]}`)

$BIN_DIR/step-02-bmk-pretrain-gpt3.sh \
    training.model.data.data_prefix=[0.25,\${data_dir}/my-gpt3_00_text_document]
