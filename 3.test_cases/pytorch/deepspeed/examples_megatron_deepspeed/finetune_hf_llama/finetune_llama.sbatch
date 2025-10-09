#!/bin/bash
#SBATCH --exclusive
#SBATCH --job-name=convert-llama-weights-to-megatron-deepspeed
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr
#SBATCH --nodes 1

set -euxo pipefail
: "${CONTAINER_PATH:=/fsxl/containers}"
: "${IMAGE:=$CONTAINER_PATH/deepspeed.sqsh}"
: "${FSX_PATH:=/fsxl}"
: "${DATA_PATH:=$FSX_PATH/alpaca/alpaca_data.json}"
: "${MODEL_PATH:=$FSX_PATH/deepspeed}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
: "${HF_LLAMA_PATH:=$FSX_PATH/deepspeed/Llama2-7b-hf}"

export NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
export NODES_ARRAY=($NODES)
export HEAD_NODE=${NODES_ARRAY[0]}
export MASTER_ADDR=$(hostname --ip-address)
export MASTER_PORT=$((RANDOM + 10000))
export NNODES=$SLURM_JOB_NUM_NODES
export NUM_GPUS_PER_NODE=8
## EFA settings
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_USE_HUGE_PAGE=0
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
export NCCL_SOCKET_IFNAME=en
export NCCL_ASYNC_ERROR_HANDLING=1
export OMPI_MCA_plm=^slurm 
export MICRO_BATCH_SIZE=16
export GLOBAL_BATCH_SIZE=256
export TP=4
export PP=2
# require to align with weight dimensions
export HIDDEN_SIZE=4096
export FFN_HIDDEN_SIZE=11008
export NUM_LAYERS=32
export NUM_HEADS=32
export SEQ_LENGTH=512
export MEGA_DS_LLAMA_PATH=${MODEL_PATH}/Llama2-7b-mega-ds-T${TP}P${PP}
cat <<EOF > configs/ds_config.json
{
    "train_batch_size": ${GLOBAL_BATCH_SIZE},
    "train_micro_batch_size_per_gpu": ${MICRO_BATCH_SIZE},
    "steps_per_print": 100,
    "zero_optimization": {
        "stage": 0
    },
    "bf16": {
        "enabled": true
    }
}
EOF

declare -a ARGS=(
    --container-image ${IMAGE}
    --container-mounts ${FSX_PATH}
    --container-mount-home
)

declare -a DIST_ARGS=(
    --nnodes ${NNODES}
    --nproc-per-node ${NUM_GPUS_PER_NODE}
    --master_addr ${MASTER_ADDR}
    --master_port ${MASTER_PORT}
    --rdzv_id $RANDOM
    --rdzv_backend c10d
    --rdzv_endpoint ${MASTER_ADDR}:${MASTER_PORT}
)

declare -a CONVERT_HF2MDS_ARGS=(
    --hf-ckpt-num-shards 2
    --hf-ckpt-dir $HF_LLAMA_PATH
    --load-mode auto
    --save $MEGA_DS_LLAMA_PATH
)

declare -a CONVERT_MDS2HF_ARGS=(
    --hf-ckpt-num-shards 2
    --hf-ckpt-dir $HF_LLAMA_PATH
    --load-mode auto
    --to-hf-ckpt
    --load $MEGA_DS_LLAMA_PATH
    --save ${HF_LLAMA_PATH}-hf-out
)

declare -a FINETUNE_ARGS=(
    --load $MEGA_DS_LLAMA_PATH
)

declare -a COMM_ARGS=(
    --tensor-model-parallel-size $TP
    --pipeline-model-parallel-size $PP
    --lr-warmup-iters 2000
    --weight-decay 0.1
    --clip-grad 1
    --num-layers $NUM_LAYERS
    --hidden-size $HIDDEN_SIZE
    --num-attention-heads $NUM_HEADS
    --ffn-hidden-size $FFN_HIDDEN_SIZE
    --attention-dropout 0
    --hidden-dropout 0
    --no-query-key-layer-scaling
    --disable-bias-linear
    --normalization rmsnorm
    --use-rotary-position-embeddings
    --untie-embeddings-and-output-weights
    --swiglu
    --seq-length $SEQ_LENGTH
    --max-position-embeddings $SEQ_LENGTH
    --micro-batch-size $MICRO_BATCH_SIZE
    --global-batch-size $GLOBAL_BATCH_SIZE
    --train-iters 3500
    --lr 2e-5
    --tensorboard-dir tensorboard_output
    --lr-decay-iters 320000
    --lr-decay-style cosine
    --log-interval 1
    --eval-iters 100
    --eval-interval 100
    --data-path $DATA_PATH
    --save-interval 1500
    --split 100,0,0
    --bf16
    --zero-stage 0
    --tokenizer-type HFTokenizer
    --tokenizer-model $HF_LLAMA_PATH
    --deepspeed_config ${PWD}/configs/ds_config.json
    --deepspeed
    --distributed-backend nccl
    --num-workers 0
    --no-masked-softmax-fusion
    --no-bias-gelu-fusion
    --no-bias-dropout-fusion
    --no-gradient-accumulation-fusion
    --repeated-dataloader
)


if [ "$1" = "convert_hf2mds" ]; then
    srun -l "${ARGS[@]}" python3 \
    ${PWD}/../Megatron-DeepSpeed/tools/hf2megads_weight_converter.py \
    "${CONVERT_HF2MDS_ARGS[@]}" "${COMM_ARGS[@]}"
elif [ "$1" = "convert_mds2hf" ]; then
    srun -l "${ARGS[@]}" python3 \
    ${PWD}/../Megatron-DeepSpeed/tools/hf2megads_weight_converter.py \
    "${CONVERT_MDS2HF_ARGS[@]}" "${COMM_ARGS[@]}"
else
    srun -l "${ARGS[@]}" torchrun "${DIST_ARGS[@]}" \
    ${PWD}/../Megatron-DeepSpeed/finetune_llama.py \
    "${FINETUNE_ARGS[@]}" "${COMM_ARGS[@]}"
fi