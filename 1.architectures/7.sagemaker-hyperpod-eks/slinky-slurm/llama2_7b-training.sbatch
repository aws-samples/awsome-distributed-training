#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=4 # number of nodes to use
#SBATCH --job-name=llama2_7b-FSDP  # name of your job
#SBATCH --output=logs/%x_%j.out    # logfile for stdout
#SBATCH --error=logs/%x_%j.err     # logfile for stderr, remove it to merge both outputs
#SBATCH --exclusive                # job has exclusive use of the resource, no sharing
#SBATCH --ntasks-per-node=1        # one task per node
#SBATCH --cpus-per-task=32         # match the number of CPUs per node
set -ex;

GPUS_PER_NODE=1 # 4 for G5.12x, 8 for P4/P5

# Set environment variables
export CUDA_VISIBLE_DEVICES=0
export NVIDIA_VISIBLE_DEVICES=all
# Set LD_LIBRARY_PATH to prioritize pip-installed CUDA 12.4 libraries

# Check if NCCL exists before setting LD_PRELOAD
if [ -f "/usr/local/lib/libnccl.so.2" ]; then
    export LD_PRELOAD="/usr/local/lib/libnccl.so.2"
fi

# Basic NCCL settings
export NCCL_DEBUG=INFO
export NCCL_SOCKET_IFNAME=^docker,lo,veth,eth

# Performance settings
export NCCL_IB_DISABLE=0                 # Enable InfiniBand
export NCCL_IB_GID_INDEX=3               # Specify GID index for IB
export NCCL_IB_TC=106                    # Traffic class for IB
export NCCL_IB_SL=3                      # Service level for IB
export NCCL_NET_GDR_LEVEL=2              # GPU Direct RDMA level

# Timeout settings
export NCCL_TIMEOUT=1800                 # 30 minutes timeout (in seconds)
export NCCL_SOCKET_TIMEOUT=300           # wait 5 minutes for TCP connections between nodes
export NCCL_ASYNC_ERROR_HANDLING=1       # Enable async error handling

# Buffer settings
export NCCL_BUFFSIZE=2097152            # 2MB buffer size
export NCCL_IB_CUDA_SUPPORT=1           # Enable CUDA support for IB

# Remove this if not debugging specific issues
# export NCCL_DEBUG_SUBSYS=ALL          # Very verbose debugging

## Set HuggingFace metadata timeout (in seconds) for large clusters
export HF_HUB_ETAG_TIMEOUT=60

# TCP connection settings
export TORCH_DISTRIBUTED_DETAILED_LOGGING=1
export GLOO_SOCKET_IFNAME=eth0
export TP_SOCKET_IFNAME=eth0
export NCCL_SOCKET_IFNAME=eth0

# TCP Store timeout settings
export TORCHELASTIC_MAX_CALLTIME=3600
export PYTORCH_TIMEOUT=3600
export TORCH_DISTRIBUTED_TIMEOUT=3600

# PyTorch specific settings
export TORCH_DISTRIBUTED_DEBUG=DETAIL    # Enable distributed debug info
export TORCH_CPP_LOG_LEVEL=INFO          # C++ front-end logging
export CUDA_LAUNCH_BLOCKING=0            # Async CUDA operation

###########################
####### Torch Dist  #######
###########################

# Debug Slurm environment
echo "=== Slurm Environment ==="
echo "SLURM_JOB_ID: $SLURM_JOB_ID"
echo "SLURM_JOB_NUM_NODES: $SLURM_JOB_NUM_NODES"
echo "SLURM_NODELIST: $SLURM_NODELIST"
echo "SLURM_JOB_NODELIST: $SLURM_JOB_NODELIST"

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE
    --nnodes=$SLURM_JOB_NUM_NODES
    --rdzv_id=$SLURM_JOB_ID
    --rdzv_backend=c10d
    --rdzv_endpoint=$(hostname)
)

export PATH="/usr/local/bin:$PATH"
export PYTHONPATH="/usr/local/lib/python3.12/site-packages:$PYTHONPATH"
export TORCHRUN="/usr/local/bin/python3 -m torch.distributed.run"
export TRAIN_SCRIPT="/fsx/awsome-distributed-training/3.test_cases/pytorch/FSDP/src/train.py"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

############################
# llama2_7b Training Params ##
############################
declare -a TRAINING_ARGS=(
    --max_context_width=512
    --num_key_value_heads=8
    --intermediate_size=2048
    --hidden_width=1024
    --num_layers=8
    --num_heads=16
    --model_type=llama_v2
    --tokenizer="hf-internal-testing/llama-tokenizer"
    --checkpoint_freq=100
    --validation_freq=100
    --max_steps=1000
    --checkpoint_dir=./checkpoints
    --dataset='c4' \
    --dataset_path='/fsx/datasets/c4/allenai___c4' # Point to downloaded dataset
    --dataset_config_name='en'
    --resume_from_checkpoint=./checkpoints
    --train_batch_size=1
    --val_batch_size=1
    --gradient_checkpointing=True
    --mixed_precision=bf16
    --sharding_strategy="full" # https://pytorch.org/docs/stable/fsdp.html
    --offload_activations=1
)

srun --export=ALL -l ${TORCHRUN} "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${TRAINING_ARGS[@]}"