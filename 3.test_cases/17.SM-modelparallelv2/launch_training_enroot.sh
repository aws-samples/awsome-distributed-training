#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=8 # number of nodes to use, 2 p4d(e) = 16 A100 GPUs
#SBATCH --job-name=smpv2_llama # name of your job
#SBATCH --exclusive # job has exclusive use of the resource, no sharing
#SBATCH --wait-all-nodes=1

set -ex;

###########################
###### User Variables #####
###########################

#########################
model_type=llama_v2
model_size=70b

#Toggle this to use synthetic data
use_synthetic_data=1


# To run training on your own data  set Training/Test Data path  -> Change this to the tokenized dataset path in Fsx. Acceptable formats are huggingface (arrow) and Jsonlines.
# Also change the use_synthetic_data to 0

export TRAINING_DIR=/fsx/path_to_data
export TEST_DIR=/fsx/path_to_data
export CHECKPOINT_DIR=$(pwd)/checkpoints

# default variables for Enroot
: "${IMAGE:=$(pwd)/smpv2.sqsh}"
: "${HYPERPOD_PATH:="/var/log/aws/clusters":"/var/log/aws/clusters"}" #this is need for validating its hyperpod cluster
: "${TRAIN_DATA_PATH:=$TRAINING_DIR:$TRAINING_DIR}"
: "${TEST_DATA_PATH:=$TEST_DIR:$TEST_DIR}"
: "${CHECKPOINT_PATH:=$CHECKPOINT_DIR:$CHECKPOINT_DIR}"   
############


###############
## Environment Variables ##
###########################

#export NCCL_SOCKET_IFNAME=en
export NCCL_ASYNC_ERROR_HANDLING=1

export NCCL_PROTO="simple"
export NCCL_SOCKET_IFNAME="^lo,docker"
export RDMAV_FORK_SAFE=1
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_DEBUG_SUBSYS=off
export NCCL_DEBUG="INFO"
export SM_NUM_GPUS=8
export GPU_NUM_DEVICES=8
export FI_EFA_SET_CUDA_SYNC_MEMOPS=0


# async runtime error ...
export CUDA_DEVICE_MAX_CONNECTIONS=1

#########################
## Command and Options ##



if [ "$model_size" == "7b" ]; then
    HIDDEN_WIDTH=4096
    NUM_LAYERS=32
    NUM_HEADS=32
    LLAMA_INTERMEDIATE_SIZE=11008
    DEFAULT_SHARD_DEGREE=8
elif [ "$model_size" == "13b" ]; then
    HIDDEN_WIDTH=5120
    NUM_LAYERS=40
    NUM_HEADS=40
    LLAMA_INTERMEDIATE_SIZE=13760
    # Reduce for better perf on p4de
    DEFAULT_SHARD_DEGREE=64
elif [ "$model_size" == "20b" ]; then
    if [ "$model_type" == "llama_v2" ]; then
        echo "Llama V2 is only configured for 7b, 13b and 70b, please add the configuration if you wish to run 20b"
        exit 1
    fi
    HIDDEN_WIDTH=6144
    NUM_LAYERS=44
    NUM_HEADS=64
    # Reduce for better perf on p4de
    DEFAULT_SHARD_DEGREE=64
elif [ "$model_size" == "65b" ]; then
    if [ "$model_type" == "llama_v2" ]; then
        echo "Llama V2 is only configured for 7b, 13b and 70b, please add the configuration if you wish to run 65b"
        exit 1
    fi
    HIDDEN_WIDTH=8192
    NUM_LAYERS=80
    NUM_HEADS=64
    # Reduce for better perf on p4de
    DEFAULT_SHARD_DEGREE=128
elif [ "$model_size" == "70b" ]; then
    HIDDEN_WIDTH=8192
    NUM_LAYERS=80
    NUM_HEADS=64
    LLAMA_INTERMEDIATE_SIZE=28672
    # Reduce for better perf on p4de
    DEFAULT_SHARD_DEGREE=64
fi


if [ -z "$shard_degree" ]; then
    SHARD_DEGREE=$DEFAULT_SHARD_DEGREE
else
    SHARD_DEGREE=$shard_degree
fi

if [ -z "$LLAMA_INTERMEDIATE_SIZE" ]; then
    LLAMA_ARGS=""
else
    LLAMA_ARGS="--llama_intermediate_size $LLAMA_INTERMEDIATE_SIZE "
fi


if [ $use_synthetic_data == 1 ]; then
    echo "using synthetic data"
    declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $HYPERPOD_PATH,$CHECKPOINT_PATH
    )
else
    echo "using real data...."
    declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $HYPERPOD_PATH,$TRAIN_DATA_PATH,$TEST_DATA_PATH,$CHECKPOINT_PATH
    )
fi


declare -a TORCHRUN_ARGS=(
    # change this to match the number of gpus per node:
    --nproc_per_node=8 \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_id=$SLURM_JOB_ID \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname) \
)

srun -l "${ARGS[@]}" torchrun "${TORCHRUN_ARGS[@]}" /workspace/train_external.py \
            --train_batch_size 4 \
            --max_steps 100 \
            --hidden_width $HIDDEN_WIDTH \
            --num_layers $NUM_LAYERS \
            --num_heads $NUM_HEADS \
            ${LLAMA_ARGS} \
            --shard_degree $SHARD_DEGREE \
            --model_type $model_type \
            --profile_nsys 1 \
            --use_smp_implementation 1 \
            --max_context_width 4096 \
            --tensor_parallel_degree 1 \
            --use_synthetic_data $use_synthetic_data \
            --training_dir $TRAINING_DIR \
            --test_dir $TEST_DIR \
            --dataset_type hf \
            --checkpoint_dir $CHECKPOINT_DIR \
            --checkpoint_freq 100 \