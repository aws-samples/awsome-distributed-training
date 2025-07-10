#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=4 # number of nodes to use
#SBATCH --job-name=llama2_7b-FSDP # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --exclusive # job has exclusive use of the resource, no sharing

set -ex;

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=4 

###########################
## Environment Variables ##
###########################

export CUDA_HOME="/usr/local/cuda"
export EFA_PATH="/opt/amazon/efa"
export OPEN_MPI_PATH="/opt/amazon/openmpi"
export OFI_NCCL_PATH="/opt/amazon/ofi-nccl"
export LD_LIBRARY_PATH="lib:${EFA_PATH}/lib:${OPEN_MPI_PATH}/lib:${CUDA_HOME}/lib64:/usr/local/lib:/lib/x86_64-linux-gnu:/opt/nccl/build/lib:${OFI_NCCL_PATH}/lib/x86_64-linux-gnu:/usr/local/nvidia/lib"

# LD_PRELOAD is required for PyTorch to find the NCCL library
export LD_PRELOAD="/usr/local/lib/libnccl.so.2"

# NCCL settings for EFA
export NCCL_PROTO=simple                    # Use a simpler communication protocol, often more reliable for EFA
export NCCL_ALGO=ring                       # Use ring algorithm for collective operations, typically best for EFA
export NCCL_NET_GDR_LEVEL=5                 # Enable GPUDirect RDMA for direct GPU-to-network transfers
export NCCL_DEBUG=INFO                      # Set NCCL debug level for troubleshooting
export NCCL_DEBUG_SUBSYS=ALL                # Enable detailed debugging output for all NCCL subsystems
export NCCL_SOCKET_IFNAME=^lo               # Exclude loopback interface
export NCCL_NET_MAX_REQUESTS=8              # Maximum number of concurrent network requests, optimized for EFA
export NCCL_MIN_NCHANNELS=8                 # Minimum number of channels for NCCL communications, increases parallelism
export NCCL_NSOCKS_PERTHREAD=8              # Number of sockets per thread for network operations

# HuggingFace settings 
export HF_HUB_ETAG_TIMEOUT=60     # Metadata timeout (in seconds) for large clusters
export HF_TOKEN=<your-token-here> # Token used to avoid throttling for data streaming

###########################
####### Torch Dist  #######
###########################

# Debug Slurm environment
echo "=== Slurm Environment ==="
echo "SLURM_JOB_ID: $SLURM_JOB_ID"
echo "SLURM_JOB_NUM_NODES: $SLURM_JOB_NUM_NODES"
echo "SLURM_NODELIST: $SLURM_NODELIST"
echo "SLURM_JOB_NODELIST: $SLURM_JOB_NODELIST"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "======================="


declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE
    --nnodes=$SLURM_JOB_NUM_NODES
    --rdzv_id=$SLURM_JOB_ID
    --rdzv_backend=c10d
    --rdzv_endpoint=$(hostname)
)

export PATH="/usr/local/bin:$PATH"
export TRAIN_SCRIPT="/fsx/awsome-distributed-training/3.test_cases/pytorch/FSDP/src/train.py"
export PYTHONPATH="/usr/local/lib/python3.12/site-packages:$PYTHONPATH"
export TORCHRUN="/usr/local/bin/python3 -m torch.distributed.run"

############################
# llama2_7b Training Params ##
############################
declare -a TRAINING_ARGS=(
    --max_context_width=4096
    --num_key_value_heads=32
    --intermediate_size=11008
    --hidden_width=4096
    --num_layers=32
    --num_heads=32
    --model_type=llama_v2
    --tokenizer="hf-internal-testing/llama-tokenizer"
    --checkpoint_freq=5000
    --validation_freq=500
    --max_steps=5000
    --checkpoint_dir=./checkpoints
    --dataset='allenai/c4'
    --dataset_config_name='en'
    --resume_from_checkpoint=./checkpoints
    --train_batch_size=1
    --val_batch_size=1
    --sharding_strategy="full" # https://pytorch.org/docs/stable/fsdp.html
    --offload_activations=1
)

srun -l ${TORCHRUN} "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${TRAINING_ARGS[@]}"