#!/usr/bin/env bash
set -o pipefail

ulimit -n 65535

sudo sysctl -w net.ipv4.ip_local_reserved_ports=41000

export FI_EFA_USE_DEVICE_RDMA=1
export FI_PROVIDER=efa
export FI_EFA_FORK_SAFE=1

if [ -z "${SLURM_NNODES}" ]
then
    # Single-node, non-SLURM runs
    HOSTS=(localhost)
    NODEID=0
    NTASKS=1
    export NEMO_EXPM_VERSION=$(date "+%Y-%m-%d_%H-%M-%S")
else
    # SLURM runs, single or multi-node
    IPS=""
    for h in $(scontrol show hostname); do
        IPS="$IPS $(nslookup $h  | awk '/^Address: / { print $2 }')";
    done
    HOSTS=(${IPS//\ / })
    NODEID=$SLURM_NODEID
    NTASKS=$SLURM_NTASKS
    export NEMO_EXPM_VERSION=$SLURM_JOB_ID
fi

export HYDRA_FULL_ERROR=1
export PROCESSES_PER_NODE=32
export MASTER_ADDR=${HOSTS[0]}
export MASTER_PORT=41000

export NEURON_RT_EXEC_TIMEOUT=10
export TPU_NUM_DEVICES=$NEURON_RT_NUM_CORES
export TPU_CHIPS_PER_HOST_BOUNDS=$NEURON_RT_NUM_CORES
export NEURON_RT_DBG_A2A_CC=0
export NEURON_RT_ASYNC_EXEC_MODE=0

DISTRIBUTED_ARGS="--nproc_per_node $PROCESSES_PER_NODE --nnodes $NTASKS --node_rank $NODEID --master_addr $MASTER_ADDR --master_port $MASTER_PORT"
echo $DISTRIBUTED_ARGS

export NEURON_FUSE_SOFTMAX=1
export NEURON_RT_STOCHASTIC_ROUNDING_EN=1
export NEURON_RT_ENABLE_VERBOSE_NUMERICAL_ERRORS=0
export NEURON_RT_ASYNC_EXEC_MAX_INFLIGHT_REQUESTS=3
export NEURON_TRANSFER_WITH_STATIC_RING_OPS=""
export MALLOC_ARENA_MAX=128

export XLA_USE_BF16=1
export NEURON_CC_FLAGS="--model-type transformer --distribution-strategy=nemo --cache_dir=$HOME/neuron_cache/llama/`hostname`"
export TF_NUM_INTEROP_THREADS=8192

export TRAIN_ITERS=20000
CREATE_TB_LOGGER=True
CHECKPOINT_CALLBACK=True
if [ "$COMPILE" = "1" ]; then
    echo "compiling only run"
    MAYBE_COMPILE="neuron_parallel_compile"
    export TRAIN_ITERS=3
    CREATE_TB_LOGGER=False
    CHECKPOINT_CALLBACK=False
fi

: ${SEQ_LENGTH:=2048}
: ${HS:=4096}
: ${TP:=8}
: ${PP:=1}
: ${N_LAYERS:=32}
: ${N_AH:=32}
: ${UBS:=1}
: ${FFN_HS:=11008}
: ${GBS:=256}
echo "SEQ_LEN=$SEQ_LENGTH, HS=$HS, FFN_HS=$FFN_HS TP=$TP PP=$PP N_LAYERS=$N_LAYERS N_AH=$N_AH GBS=$GBS UBS=$UBS"

LOG_PATH=logs/$SLURM_JOB_ID/$NODEID/
mkdir -p $LOG_PATH

$MAYBE_COMPILE torchrun $DISTRIBUTED_ARGS megatron_gpt_pretraining.py  \
    --config-path=conf \
    --config-name=megatron_llama_config \
    trainer.devices=$PROCESSES_PER_NODE \
    trainer.num_nodes=$NTASKS \
    trainer.max_epochs=null \
    trainer.max_steps=$TRAIN_ITERS\
    trainer.val_check_interval=$TRAIN_ITERS \
    trainer.log_every_n_steps=1 \
    trainer.limit_val_batches=1 \
    trainer.limit_test_batches=1 \
    trainer.accumulate_grad_batches=1 \
    trainer.precision=32 \
    model.tokenizer.type='/root/scripts/example_datasets/llamav2_weights/7b-hf' \
    model.micro_batch_size=$UBS \
    model.global_batch_size=$GBS \
    model.tensor_model_parallel_size=$TP \
    model.pipeline_model_parallel_size=$PP \
    model.max_position_embeddings=$SEQ_LENGTH \
    model.encoder_seq_length=$SEQ_LENGTH \
    model.hidden_size=$HS \
    model.ffn_hidden_size=$FFN_HS \
    model.num_layers=$N_LAYERS \
    model.num_attention_heads=$N_AH \
    model.init_method_std=0.021 \
    model.hidden_dropout=0 \
    model.layernorm_epsilon=1e-5 \
    model.data.data_prefix=[1.0,/root/scripts/data/books/book.jsonl-processed_text_document] \
    model.data.num_workers=1 \
    model.data.seq_length=$SEQ_LENGTH \
    model.optim.name=adamw \
    model.optim.lr=3.0e-4 \
    model.optim.betas=[0.9,0.95] \
    model.optim.weight_decay=0.1 \
    model.optim.sched.name=CosineAnnealing \
    model.optim.sched.warmup_steps=10 \
    model.optim.sched.constant_steps=0 \
    model.optim.sched.min_lr=3.0e-5 \
    model.optim.capturable=True \
    model.sequence_parallel=True  \
    model.activations_checkpoint_granularity=full \
    model.activations_checkpoint_method=uniform \
    model.activations_checkpoint_num_layers=1 \
    +model.save_xser=True \
    exp_manager.create_tensorboard_logger=$CREATE_TB_LOGGER \
    exp_manager.resume_if_exists=False \
    exp_manager.resume_ignore_no_checkpoint=False \
    exp_manager.create_checkpoint_callback=$CHECKPOINT_CALLBACK \
    +exp_manager.checkpoint_callback_params.train_time_interval=36000 \
    exp_manager.checkpoint_callback_params.save_last=False \
    model.use_cpu_initialization=True   2>&1  | tee  $LOG_PATH/log

# Note: to resume training using a checkpoint, please add the following configuration above, adjusting for your checkpoint path
    # model.use_cpu_initialization=False \
    # +model.load_xser=True \
    # +model.resume_from_checkpoint='/root/scripts/example_datasets/llamav2_weights/llama7b_hf_converted_nemo_v3//mp_rank_07/model_optim_rng.ckpt' \
# To use mixed precision optimizer, add
    # model.megatron_amp_O2=True \