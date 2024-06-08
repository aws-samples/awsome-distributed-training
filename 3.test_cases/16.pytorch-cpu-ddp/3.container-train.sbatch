#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=cpu-ddp-container
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1
#SBATCH --nodes 2
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr

nodes=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
nodes_array=($nodes)
head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address)

echo Node IP: $head_node_ip
export LOGLEVEL=INFO
export NVIDIA_VISIBLE_DEVICES=void

declare -a ARGS=(
    --container-image ${PWD}/pytorch.sqsh
    --container-mounts ${PWD}
)

AUTO_RESUME=""
if [ -d "/opt/sagemaker_cluster" ]; then
    echo "Detected Hyperpod cluster.. enabling --auto-resume=1"
    AUTO_RESUME="--auto-resume=1"
fi

srun ${AUTO_RESUME} -l "${ARGS[@]}" torchrun \
    --nnodes 2 \
    --nproc_per_node 4 \
    --rdzv_id $RANDOM \
    --rdzv_backend c10d \
    --rdzv_endpoint $head_node_ip:29500 \
    ${PWD}/ddp.py 5000000 10
