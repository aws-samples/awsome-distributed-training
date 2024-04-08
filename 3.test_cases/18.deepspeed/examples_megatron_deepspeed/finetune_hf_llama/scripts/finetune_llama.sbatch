#!/bin/bash
#SBATCH --exclusive
#SBATCH --job-name=convert-llama-weights-to-megatron-deepspeed
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr
#SBATCH --nodes 1

set -euxo pipefail
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/deepspeed.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${DATA_PATH:=/fsx/alpaca/alpaca_data.json}"
: "${MODEL_PATH:=$FSX_PATH/deepspeed}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
: "${HF_LLAMA_PATH:=/fsx/deepspeed/Llama2-7b-hf}"

export NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
export NODES_ARRAY=($NODES)
export HEAD_NODE=${NODES_ARRAY[0]}
export MASTER_ADDR=$(hostname --ip-address)
export MASTER_PORT=$((RANDOM + 10000))
export NNODES=$SLURM_JOB_NUM_NODES
export NUM_GPUS_PER_NODE=8

export MICRO_BATCH_SIZE=16
export GLOBAL_BATCH_SIZE=256
export TP=2
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

export HOSTFILE=/fsx/hostfile
# create hostfile on the fly
# https://github.com/microsoft/DeepSpeed/issues/3489
function makehostfile() {
perl -e '$slots=split /,/, $ENV{"SLURM_STEP_GPUS"};
$slots=4 if $slots==0; # workaround 8 gpu machines
@nodes = split /\n/, qx[scontrol show hostnames $ENV{"SLURM_JOB_NODELIST"}];
print map { "$b$_ slots=$slots\n" } @nodes'
}
makehostfile > ${HOSTFILE}


declare -a ARGS=(
    --container-image ${IMAGE}
    --container-mounts /fsx
)
declare -a DIST_ARGS=(
    --num_nodes ${NNODES}
    --num_gpus ${NUM_GPUS_PER_NODE}
    --master_addr ${MASTER_ADDR}
    --hostfile  ${HOSTFILE}
    --launcher "OpenMPI"
    --no_ssh_check
)
declare -a CONVERT_ARGS=(
    --hf-ckpt-num-shards 3 
    --origin-hf-ckpt-dir ${MODEL_PATH}/Llama2-7b-hf
    --save ${MEGA_DS_LLAMA_PATH}
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

if [ "$1" = "convert" ]; then
    srun -l "${ARGS[@]}" deepspeed "${DIST_ARGS[@]}" \
    ${PWD}/../Megatron-DeepSpeed/tools/hf2megads_weight_converter.py \
    "${CONVERT_ARGS[@]}" "${COMM_ARGS[@]}"
else
    srun -l "${ARGS[@]}" deepspeed "${DIST_ARGS[@]}" \
    ${PWD}/../Megatron-DeepSpeed/finetune_llama.py \
    --load ${MEGA_DS_LLAMA_PATH} "${COMM_ARGS[@]}"
fi
