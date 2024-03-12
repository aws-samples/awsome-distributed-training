#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

export OMP_NUM_THREADS=1
export GPUS_PER_NODE=8 # p4d/p4de instances have 8 GPUs per node
MASTER_NODE=$(scontrol show hostname | head -n 1)
export MASTER_ADDR=$(scontrol show node=$MASTER_NODE | awk -F= '/NodeAddr=/{print $2}' | awk '{print $1}')
export NNODES=$SLURM_NTASKS
export NODE_RANK=$SLURM_NODEID
export MASTER_PORT=9001
export WORLD_SIZE=$SLURM_NTASKS
export DISTRIBUTED_ARGS="--nproc_per_node $GPUS_PER_NODE --nnodes $NNODES --node_rank $NODE_RANK --master_addr $MASTER_ADDR --master_port $MASTER_PORT "

echo "Launching torchrun..."

torchrun $DISTRIBUTED_ARGS \
	train_deepspeed.py \
	--gradient_checkpointing True \
	--bf16 True \
	--optimizer "adamw_torch" \
	--per_device_train_batch_size 1 \
	--epochs 1 \
	--max_steps 30 \
	--deepspeed_config "zero_stage3_config.json"


