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
#export NCCL_SOCKET_IFNAME=ens
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
#export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
composer \
    --verbose \
    --rank $1 \
    --local_rank $2 \
    --node_rank $3 \
    --world_size $4 \
    --local_world_size $5 \
    --master_addr $6 \
    --master_port $7 \
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
    global_train_batch_size=256