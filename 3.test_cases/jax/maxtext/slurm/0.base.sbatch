#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=2 # number of nodes to use
#SBATCH --job-name=MaxText # name of your job
#SBATCH --output logs/%x_%j.out
#SBATCH --exclusive # job has exclusive use of the resource, no sharing
#SBATCH --wait-all-nodes=1

set -ex;

# default variables for Enroot
: "${IMAGE:=/fsx/ubuntu/images/maxtext-jetstream-v0.2.2.sqsh}"
: "${FSX_MOUNT:=/fsx:/fsx}"


###########################
## Environment Variables ##
###########################

# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
#export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO

# async runtime error ...
export CUDA_DEVICE_MAX_CONNECTIONS=1

# EFA Flags
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export FI_EFA_FORK_SAFE=1

# NCCL Flags
export NCCL_DEBUG=INFO
export NCCL_NVLS_ENABLE=0

# XLA Configuration
export XLA_PYTHON_CLIENT_MEM_FRACTION=0.7
export XLA_FLAGS="--xla_gpu_enable_latency_hiding_scheduler=true --xla_gpu_enable_triton_gemm=false --xla_gpu_simplify_all_fp_conversions --xla_gpu_enable_async_all_gather=true --xla_gpu_enable_async_reduce_scatter=true --xla_gpu_enable_highest_priority_async_stream=true --xla_gpu_enable_triton_softmax_fusion=false --xla_gpu_all_reduce_combine_threshold_bytes=33554432 --xla_gpu_graph_level=0 --xla_gpu_enable_async_all_reduce=true"
export TPU_TYPE=gpu
export TF_FORCE_GPU_ALLOW_GROWTH=true

#########################
## Command and Options ##
#########################

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $FSX_MOUNT
)

# Enable auto-resume if this job running on HyperPod
AUTO_RESUME=""
if [ -d "/opt/sagemaker_cluster" ]; then
    echo "Detected Hyperpod cluster.. enabling --auto-resume=1"
    AUTO_RESUME="--auto-resume=1"
fi

declare -a MAXTEXT_ARGS=(
    MaxText/configs/base.yml \
    run_name=base-synthetic \
    base_output_directory=${DATA_PATH}/maxtext-outputs
    dataset_type=synthetic 
    steps=10
)

srun ${AUTO_RESUME} -l "${ARGS[@]}" python3 MaxText/train.py "${MAXTEXT_ARGS[@]}"