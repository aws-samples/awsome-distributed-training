#!/usr/bin/env bash
set -euxo pipefail

export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
# export NCCL_ALGO=Ring
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_ENABLE_SHM_TRANSFER=1
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
# export NCCL_SOCKET_IFNAME=ens
# async runtime error ...
export CUDA_DEVICE_MAX_CONNECTIONS=1

export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
export HEAD_NODE_IP=$1
export NODES=$3
export RANK=${SLURM_PROCID}
export WORLD_SIZE=1
export LOCAL_RANK=${SLURM_LOCALID}
export LOCAL_WORLD_SIZE=1 # 1 gpu の検証から
export NODE_RANK=${SLURM_NODEID}
[[ ${NODE_RANK} == 0 ]] && export MASTER_ADDR=0.0.0.0 || export MASTER_ADDR=$(hostname)
export MASTER_PORT=$2
export PYTHONUNBUFFERED=1
#python -c "import streaming; streaming.base.util.clean_stale_shared_memory()"
nvidia-smi
#  VISIBLE_DIVICES does not work
export CUDA_VISIBLE_DEVICES=${LOCAL_RANK}
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
composer \
    --verbose \
    /llm-foundry/scripts/train/train.py \
    /llm-foundry/scripts/train/yamls/pretrain/mpt-7b.yaml \
    data_local=/fsx/my-copy-c4 \
    train_loader.dataset.split=train_small \
    eval_loader.dataset.split=val_small \
    max_duration=3ba \
    eval_interval=0 \
    save_folder=mpt-7b \
    model.loss_fn=torch_crossentropy \
    device_train_microbatch_size=8 \
    global_train_batch_size=8
# bash \
#     /apps/reference-architectures/3.test_cases/3.MPT/slurm-scripts/run-composer.sh \
#     ${RANK} ${LOCAL_RANK} ${NODE_RANK} ${WORLD_SIZE} ${LOCAL_WORLD_SIZE} ${MASTER_ADDR} ${MASTER_PORT}
#$ if [ ${NODE_RANK} == 0 ]; then
#$ else
#$     ssh -p 2221 -q $(hostname)  \
#$     bash \
#$     /apps/reference-architectures/3.test_cases/3.MPT/slurm-scripts/run-composer.sh \
#$     ${WORLD_SIZE} ${NODE_RANK} ${MASTER_ADDR} ${MASTER_PORT}
#$ fi