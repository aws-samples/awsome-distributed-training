#!/bin/bash
#SBATCH --exclusive
#SBATCH --job-name=convert-llama-weights-to-megatron-deepspeed
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr
#SBATCH --nodes 1

: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/deepspeed.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${DATASET:=c4_subset}"
: "${DATA_PATH:=$FSX_PATH/$DATASET}"
: "${MODEL_PATH:=$FSX_PATH/deepspeed}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"

MICRO_BATCH_SIZE=16
GLOBAL_BATCH_SIZE=256
TP=2
PP=2
# require to align with weight dimensions
HIDDEN_SIZE=4096
FFN_HIDDEN_SIZE=11008
NUM_LAYERS=32
NUM_HEADS=32
SEQ_LENGTH=512

declare -a ARGS=(
    --container-image ${IMAGE}
    --container-mounts /fsx
)
declare -a DIST_ARGS=(
    --num_nodes ${NUM_NODES} \
    --num_gpus ${NUM_GPUS_PER_NODE} \
    --master_addr ${MASTER_ADDR}
)
declare -a CONVERT_ARGS=(
    --hf-ckpt-num-shards 2 
    --origin-hf-ckpt-dir ${MODEL_PATH}/Llama2-7b-hf
    --save ${MODEL_PATH}/Llama2-7b-mega-ds-T${TP}P${PP}
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
    --data-path $DATASET_PATH 
    --save-interval 1500 
    --split 100,0,0 
    --bf16 
    --zero-stage 0 
    --tokenizer-type HFTokenizer 
    --tokenizer-model $HF_LLAMA_PATH 
    --deepspeed_config ./examples_deepspeed/finetune_hf_llama/ds_config.json 
    --deepspeed 
    --distributed-backend nccl 
    --num-workers 0 
    --no-masked-softmax-fusion 
    --no-bias-gelu-fusion 
    --no-bias-dropout-fusion 
    --no-gradient-accumulation-fusion 
    --repeated-dataloader
)

if [ "$1" = "convert" ]; then
    TASK_ARGS=${PWD}/../Megatron-DeepSpeed/tools/hf2megads_weight_converter.py ${CONVERT_ARGS}
else
    TASK_ARGS=${PWD}/../Megatron-DeepSpeed/finetune_llama.py --load ${MEGA_DS_LLAMA_PATH}
fi

srun -l "${ARGS[@]}" deepspeed "${DIST_ARGS[@]}" "${TASK_ARGS}" "${COMM_ARGS[@]}"