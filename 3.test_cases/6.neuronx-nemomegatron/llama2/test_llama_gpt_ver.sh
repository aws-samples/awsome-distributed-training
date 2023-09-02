#!/usr/bin/env bash
set -xo pipefail
# set -euxo pipefail

sudo sysctl -w net.ipv4.ip_local_reserved_ports=48620

export FI_EFA_USE_DEVICE_RDMA=1
export FI_PROVIDER=efa
export FI_EFA_FORK_SAFE=1
export TPU_PORT=51101

if [ -z "${SLURM_NNODES}" ]
then
    # Single-node, non-SLURM runs
    HOSTS=(localhost)
    NODEID=0
    NTASKS=1
else
    # SLURM runs, single or multi-node
    IPS=""
    for h in $(scontrol show hostname); do
        IPS="$IPS $(nslookup $h  | awk '/^Address: / { print $2 }')";
    done
    HOSTS=(${IPS//\ / })
    NODEID=$SLURM_NODEID
    NTASKS=$SLURM_NTASKS
fi
export LOG_PATH=logs-gpt-ver
mkdir -p ${LOG_PATH}
export HYDRA_FULL_ERROR=1 
export PROCESSES_PER_NODE=32
export XRT_LOCAL_WORKER="c_localservice:$NODEID"
export XRT_SHARD_ORDINAL=$NODEID
export XRT_MESH_SERVICE_ADDRESS=${HOSTS[0]}:8477
export TPU_MESH_CONTROLLER_ADDRESS=${HOSTS[0]}:8476
export TPU_MESH_CONTROLLER_PORT=8476
export NEURON_RT_ROOT_COMM_ID=${HOSTS[0]}:48620
export TF_GRPC_DEFAULT_OPTIONS="grpc.keepalive_time_ms=60000,grpc.keepalive_timeout_ms=14400000,grpc.http2.max_pings_without_data=0,grpc.http2.min_ping_interval_without_data_ms=300000"
export XRT_SHARD_WORLD_SIZE=$NTASKS
export WORLD_SIZE=$((NTASKS*PROCESSES_PER_NODE))
export MASTER_ADDR=${HOSTS[0]}
export MASTER_PORT=41000
export ALLOW_MULTIPLE_LIBTPU_LOAD=1
export NEURON_USE_LOAD_COLLECTIVES=1
export NEURON_GLOBAL_DEVICE_COUNT=$WORLD_SIZE
export NEURON_RT_NUM_CORES=$PROCESSES_PER_NODE
export NEURON_NUM_DEVICES=$NEURON_RT_NUM_CORES
export CLOUD_TPU_TASK_ID=$NODEID
export RANK=$((NODEID*PROCESSES_PER_NODE))
export NEURON_GLOBAL_DEVICE_ID=$RANK

export NEURON_FUSE_SOFTMAX=1
export NEURON_RT_STOCHASTIC_ROUNDING_EN=0
export NEURON_TRANSFER_WITH_STATIC_RING_OPS=""
export ALLOC_ARENA_MAX=128

#### Need to set all the server related env variables before server launch
export TPU_CHIPS_PER_HOST_BOUNDS=$NEURON_RT_NUM_CORES,$NEURON_RT_NUM_CORES

export XLA_USE_BF16=1
export NEURON_CC_FLAGS="--model-type=transformer --enable-internal-seeded-rng-dropout --tensorizer-options='--no-keep-remat-dma-transpose' --cache_dir=$HOME/neuron_cache/$NODEID"
export TF_NUM_INTEROP_THREADS=8192

echo "Starting XRT server"
if [ "$NODEID" = 0 ]; then
    idx=0
    for ip in ${HOSTS[@]}; do
        tpu_configs+=("c_localservice;$((idx++));$ip:$TPU_PORT")
    done
    export XRT_TPU_CONFIG=$(IFS="|"; echo "${tpu_configs[*]}")
    export TPU_NUM_DEVICES=$PROCESSES_PER_NODE
fi

echo "NTASKS: $NTASKS"
if [ $NTASKS = 1 ]; then
    export XRT_TPU_CONFIG="localservice;0;localhost:$TPU_PORT"
    export XRT_LOCAL_WORKER="localservice:$NODEID"
    export TPU_NUM_DEVICES=$PROCESSES_PER_NODE
fi

export XRT_START_LOCAL_SERVER=0

export TRAIN_ITERS=300000
export GBS=$((NTASKS*32))
if [ "$NEURON_EXTRACT_GRAPHS_ONLY" = "1" ]; then
    export TRAIN_ITERS=3
fi

: ${SEQ_LENGTH:=2048}
: ${HS:=4096}
: ${TP:=8}
: ${PP:=1}
: ${N_LAYERS:=32}
: ${N_AH:=32}
: ${UBS:=1}
export FFN_HS=$(($HS*4))
echo "SEQ_LEN=$SEQ_LENGTH, HS=$HS, FFN_HS=$FFN_HS TP=$TP PP=$PP N_LAYERS=$N_LAYERS N_AH=$N_AH GBS=$GBS UBS=$UBS"
source /home/ec2-user/aws_neuron_venv_pytorch/bin/activate
python3 /home/ec2-user/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/megatron_gpt_pretraining.py  \
    --config-path=conf \
    --config-name=megatron_llama_config \
    trainer.devices=$NEURON_NUM_DEVICES \
    trainer.num_nodes=$NTASKS \
    trainer.max_epochs=null \
    trainer.max_steps=$TRAIN_ITERS\
    trainer.val_check_interval=$TRAIN_ITERS \
    trainer.log_every_n_steps=1 \
    trainer.limit_val_batches=1 \
    trainer.limit_test_batches=1 \
    trainer.accumulate_grad_batches=1 \
    trainer.precision=32 \
    model.tokenizer.type='/fsx/Llama2-7b-hf' \
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
    model.data.data_prefix=[1.0,/fsx/data/llama2/book/book-tokenized_text_document.idx] \
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
    exp_manager.create_tensorboard_logger=False \
    exp_manager.resume_if_exists=False \
    exp_manager.resume_ignore_no_checkpoint=False \
    exp_manager.create_checkpoint_callback=False \
    +exp_manager.checkpoint_callback_params.train_time_interval=36000 \
    exp_manager.checkpoint_callback_params.save_last=False \
    model.use_cpu_initialization=True   2>&1  | tee  $LOG_PATH/log &

# Note: to resume training using a checkpoint, please add the following configuration above, adjusting for your checkpoint path
    # model.use_cpu_initialization=False \
    # +model.load_xser=True \
    # +model.resume_from_checkpoint='/root/scripts/example_datasets/llamav2_weights/llama7b_hf_converted_nemo_v3//mp_rank_07/model_optim_rng.ckpt' \
# To use mixed precision optimizer, add
    # model.megatron_amp_O2=True \
python3 -m torch_neuronx.distributed._xrt_run_server --port $TPU_PORT --pid_to_track $!
