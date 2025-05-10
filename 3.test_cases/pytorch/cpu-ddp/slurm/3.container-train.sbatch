#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=cpu-ddp-container
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1
#SBATCH --nodes 2
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr

export LOGLEVEL=INFO
export NVIDIA_VISIBLE_DEVICES=void

declare -a ARGS=(
    --container-image ${PWD}/pytorch.sqsh
    --container-mounts $(dirname "$PWD")
)

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=4
    --nnodes=$SLURM_JOB_NUM_NODES
    --rdzv_id=$SLURM_JOB_ID
    --rdzv_backend=c10d
    --rdzv_endpoint=$(hostname)
)

AUTO_RESUME=""
if [ -d "/opt/sagemaker_cluster" ]; then
    echo "Detected Hyperpod cluster.. enabling --auto-resume=1"
    AUTO_RESUME="--auto-resume=1"
fi

srun ${AUTO_RESUME} -l "${ARGS[@]}" torchrun \
    "${TORCHRUN_ARGS[@]}" \
    $(dirname "$PWD")/ddp.py 5000000 10
