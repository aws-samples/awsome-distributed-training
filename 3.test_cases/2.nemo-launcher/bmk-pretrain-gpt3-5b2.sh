#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Override the default values in the underlying step-02-bmk-pretrain-gpt3.sh script.
# See that underlying script to learn about the defaults.

export NUM_NODES=2
export RUNTIME=30m
export MAX_STEPS=20
#export UNIQUE_OUTPUT_DIR=1

BIN_DIR=$(dirname `readlink -e ${BASH_SOURCE[0]}`)

# When node_count < 8, needs full activations checkpointing. These're settings found on
# Nemo repo's Jenkin script.
#
# Below settings is similar to 22.09, except that 22.09 funnily didn't OOM with
# activations_checkpoint_num_layers=0.
$BIN_DIR/1.bmk-pretrain-gpt3.sh \
    training.model.activations_checkpoint_granularity='full' \
    training.model.activations_checkpoint_method='block' \
    training.model.activations_checkpoint_num_layers=1
