#!/bin/bash

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=32
if [ $NEURON_EXTRACT_GRAPHS_ONLY -gt 0 ]; then
    MAX_STEPS=10
    MAYBE_COMPILE="neuron_parallel_compile"
    model_checkpoint_path="/fsx/ubuntu/peft_ft/compile"
else
    MAX_STEPS=-1
    model_checkpoint_path="/fsx/ubuntu/peft_ft/model_checkpoints"
fi

###########################
## Environment Variables ##
###########################

CACHE_DIR='/fsx/ubuntu/peft_ft/cache/neuron_compile_cache/llama3-8B'
mkdir -p $CACHE_DIR
export NEURON_CC_FLAGS="--model-type=transformer --distribution-strategy=llm-training --enable-saturate-infinity --target=trn1 --cache_dir=$CACHE_DIR"
export OMP_NUM_THREADS=1
export NEURON_FUSE_SOFTMAX=1
export NEURON_RT_ASYNC_EXEC_MAX_INFLIGHT_REQUESTS=5
export NEURON_RT_STOCHASTIC_ROUNDING_EN=1 # Stochastic rounding mode is enabled by default in PyTorch-Neuron when XLA_USE_BF16=1.
export MALLOC_ARENA_MAX=70
export FI_PROVIDER="efa"

###########################
####### Torch Dist  #######
###########################

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE
    --nnodes=$SLURM_JOB_NUM_NODES
)

export TRAIN_SCRIPT=/fsx/ubuntu/awsome-distributed-training/3.test_cases/pytorch/optimum-neuron/llama3/slurm/fine-tuning/train.py

############################
##### Training Params ######
############################

declare -a TRAINING_ARGS=(
    --bf16 True \
    --checkpoint_frequency 400 \
    --dataset "databricks/databricks-dolly-15k" \
    --early_stopping_patience 3 \
    --max_steps $MAX_STEPS\
    --max_seq_length 1024 \
    --epochs 1 \
    --gradient_accumulation_steps 3 \
    --learning_rate 2e-05 \
    --model_path "/fsx/ubuntu/peft_ft/model_artifacts/llama3-8B" \
    --tokenizer_path "/fsx/ubuntu/peft_ft/tokenizer/llama3-8B" \
    --model_type "causal_lm" \
    --model_checkpoint_path $model_checkpoint_path \
    --model_final_path "/fsx/ubuntu/peft_ft/model_checkpoints/final" \
    --pp_size 1 \
    --tp_size 8 \
    --train_batch_size 1 \
    --warmup_steps 100 \
    --weight_decay 0.01 \
    --seed 42
)

source /fsx/ubuntu/peft_ft/env_llama3_8B_peft/bin/activate

$MAYBE_COMPILE torchrun "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT "${TRAINING_ARGS[@]}"
