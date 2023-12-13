#!/usr/bin/env bash

parse_inputs() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        --hostfile)
            hostfile=$2
            shift 2
            ;;
        --model_type)
            model_type=$2
            shift 2
            ;;
        --model_size)
            model_size=$2
            shift 2
            ;;
        --shard_degree)
            shard_degree=$2
            shift 2
            ;;
        --nsys_path)
            nsys_path=$2
            shift 2
            ;;
        *)
            shift 1
            ;;
        esac
    done
}

parse_inputs $@

if [ -z "$hostfile" ]; then
    echo "Hostfile needs to be passed"
    exit 1
fi

num_nodes=$(cat $hostfile | wc -l)

export NCCL_PROTO="simple"
export NCCL_SOCKET_IFNAME="^lo,docker"
export RDMAV_FORK_SAFE=1
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_DEBUG_SUBSYS=off
export NCCL_DEBUG="INFO"
export SM_NUM_GPUS=8
export MASTER_ADDR=$(head -n 1 $hostfile)
export GPU_NUM_DEVICES=8

if [[ "$@" == *"--use_smp_implementation 1"* ]] || [[ "$@" == *"--tensor_parallel_degree"* ]]; then
    # When using SMP implementation not setting NVTE_TORCH_COMPILE=0 causes a crash
    export NVTE_TORCH_COMPILE=0
    # When using SMP implementation, there's a message asking to set this for better perf
fi

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
    DEFAULT_SHARD_DEGREE=128
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

TORCH_CMD="torchrun --nnodes=${num_nodes} --nproc_per_node=8"

# If nsys path provided, profile using Nsys, but only on 1st node. Requires job to be launched using sbatch
if [[ -n $nsys_path ]]; then
    profile_nsys=1
    if [[ $SLURM_PROCID -eq 1 ]]; then
        NSYS_CMD="nsys profile -w true -t cuda,nvtx,osrt,cudnn,cublas -s cpu  --capture-range=cudaProfilerApi --cuda-memory-usage=true --cudabacktrace=true -x true -o $nsys_path --force-overwrite=true"
        TORCH_CMD="$NSYS_CMD $TORCH_CMD"
    fi
else
    profile_nsys=0
fi

$TORCH_CMD \
    --rdzv_endpoint=$MASTER_ADDR:29400 --rdzv_id=100 --rdzv_backend=c10d \
    train.py \
    --train_batch_size 2 \
    --max_steps 100 \
    --checkpoint_freq 200 \
    --hidden_width $HIDDEN_WIDTH \
    --num_layers $NUM_LAYERS \
    --num_heads $NUM_HEADS \
    ${LLAMA_ARGS} \
    --shard_degree $SHARD_DEGREE \
    --model_type $model_type \
    --profile_nsys $profile_nsys \
    $@

# $@ forwards other args given to model.sh to train.py script
# if any arg is repeated second value is used automatically by argparse, so overrides the value here
