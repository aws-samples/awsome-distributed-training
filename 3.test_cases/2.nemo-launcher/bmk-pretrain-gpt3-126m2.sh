#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This script is meant for advance users who've gone through README.md
#
# Override the default values in the underlying step-02-bmk-pretrain-gpt3.sh script.
# See that underlying script to learn about the defaults.

export MODEL_SIZE=126m
export NUM_NODES=2
export RUNTIME=30m
export MAX_STEPS=40
#export UNIQUE_OUTPUT_DIR=1

BIN_DIR=$(dirname `readlink -e ${BASH_SOURCE[0]}`)

# Node_count == 2 can work without full activations checkpointing.
$BIN_DIR/1.bmk-pretrain-gpt3.sh
