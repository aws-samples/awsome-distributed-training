#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=megatron_gpt # name of your job
#SBATCH --nodes=2 # number of nodes to use, 2 p5 = 16 H100 GPUs
#SBATCH --ntasks-per-node=8
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --exclusive # job has exclusive use of the resource, no sharing
#SBATCH --wait-all-nodes=1

set -ex;

###########################
###### User Variables #####
###########################

# Parallelism decomposition variables
export TENSOR_PARALLEL=4
export PIPELINE_PARALLEL=2

# Model parameters, defaults to 39B model
# Refer to page 8 of this paper on how to tune models parameters
# https://arxiv.org/pdf/2104.04473.pdf
export NUM_LAYERS=36
export HIDDEN_SIZE=4096
export NUM_ATTENTION_HEADS=32

export SEQ_LENGTH=2048
export MAX_POSITION_EMBEDDINGS=2048
export MICRO_BATCH_SIZE=1
export GLOBAL_BATCH_SIZE=288

# default variables for Enroot

# default variables for Enroot
export IMAGE=$(pwd)/megatron-training.sqsh
export DATA_PATH=/fsx
export FSX_MOUNT=$(pwd):$DATA_PATH

###########################
## Environment Variables ##
###########################

# async runtime error ...
export CUDA_DEVICE_MAX_CONNECTIONS=1

## Set libfabric flags to use EFA
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1 # required for p4d
export FI_EFA_FORK_SAFE=1 # os fork error

## Set this flag for debugging EFA
#export FI_LOG_LEVEL=warn

## NCCL Environment variables
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO

### Increase the send queue depth and can turn NCCL communications into non-blocking.
### https://www.usenix.org/system/files/atc23-choi.pdf
export NCCL_BUFFSIZE=8388608
### Improve performance by increasing buffer size for Send/Recv, Gather, Scatter and Alltoall communications
### https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/p2p.html
export NCCL_P2P_NET_CHUNKSIZE=524288

### Improve performance for AllReduce by selecting specific protocol and algorithm for specific
### message size and number of ranks.
### More information https://github.com/aws/aws-ofi-nccl/wiki/Algorithm-and-Protocol-Tuner-for-AWS.
export NCCL_TUNER_PLUGIN=/opt/aws-ofi-nccl/install/lib/libnccl-ofi-tuner.so


#########################
## Command and Options ##
#########################

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $FSX_MOUNT
)


AUTO_RESUME=""
if [ -d "/opt/sagemaker_cluster" ]; then
    echo "Detected Hyperpod cluster.. enabling --auto-resume=1"
    AUTO_RESUME="--auto-resume=1"
fi

NSYS_PROFILING_FLAG=0
NSYS_PROFILING=""
NSYS_PROFILING_MEGATRON_ARGS=""

if [ $NSYS_PROFILING_FLAG -eq 1 ]; then
    NSYS_PROFILING="/usr/local/cuda/bin/nsys profile -t cuda,nvtx,osrt,cudnn,cublas -s process-tree --capture-range=cudaProfilerApi --capture-range-end=stop --force-overwrite true --trace-fork-before-exec true --output /fsx/report_megatron_job%q{SLURM_JOB_ID}_rank%q{SLURM_PROCID}_on_%q{HOSTNAME}.nsys-rep"
    NSYS_PROFILING_MEGATRON_ARGS="--profile --profile-step-start 19 --profile-step-end 30"
fi
export NSYS_PROFILING
export NSYS_PROFILING_MEGATRON_ARGS

srun ${AUTO_RESUME} -l "${ARGS[@]}" bash -c '
export MASTER_ADDR=$SLURM_LAUNCH_NODE_IPADDR;
export MASTER_PORT=6000;
export WORLD_SIZE=$SLURM_NTASKS;
export RANK=$SLURM_PROCID;
export LOCAL_RANK=$SLURM_LOCALID;
$NSYS_PROFILING \
python3 -u /workspace/Megatron-LM/pretrain_gpt.py \
$NSYS_PROFILING_MEGATRON_ARGS \
--num-layers $NUM_LAYERS \
--hidden-size $HIDDEN_SIZE \
--num-attention-heads $NUM_ATTENTION_HEADS \
--seq-length $SEQ_LENGTH \
--max-position-embeddings $MAX_POSITION_EMBEDDINGS \
--micro-batch-size $MICRO_BATCH_SIZE \
--global-batch-size $GLOBAL_BATCH_SIZE \
--tensor-model-parallel-size $TENSOR_PARALLEL \
--pipeline-model-parallel-size $PIPELINE_PARALLEL \
--train-samples 146484375 \
--lr-decay-samples 126953125 \
--lr-warmup-samples 183105 \
--lr 6.0e-5 \
--min-lr 6.0e-6 \
--lr-decay-style cosine \
--log-interval 1 \
--eval-iters 40 \
--eval-interval 1000 \
--data-path ${DATA_PATH}/gpt2/my-gpt2_text_document \
--vocab-file ${DATA_PATH}/gpt2/gpt2-vocab.json \
--merge-file ${DATA_PATH}/gpt2/gpt2-merges.txt \
--split 98,2,0 \
--clip-grad 1.0 \
--weight-decay 0.1 \
--adam-beta1 0.9 \
--adam-beta2 0.95 \
--init-method-std 0.006 \
--fp16 \
--recompute-activations '
