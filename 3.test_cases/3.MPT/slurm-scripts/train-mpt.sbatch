#!/bin/bash

#SBATCH -N 8 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --job-name=train-mpt # name of your job
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --ntasks-per-node 8 # Number of GPU per node
#SBATCH --gres=gpu:8 # number of GPU we reserve
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1


# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${IMAGE:=$APPS_PATH/llm-foundry.sqsh}"

## Plenty of EFA level variables
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
# export NCCL_ALGO=Ring
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_ENABLE_SHM_TRANSFER=1
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
#export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO

export PROFILE_FILE=/report/profile_file

declare -a ARGS=(
    --container-image $IMAGE
)
NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NODES_ARRAY=($NODES)
HEAD_NODE=${NODES_ARRAY[0]}
HEAD_NODE_IP=$(srun --nodes=1 --ntasks=1 -w "$HEAD_NODE" hostname --ip-address)
srun -l "${ARGS[@]}" nsys profile -w true -t cuda,nvtx,osrt,cudnn,cublas \
  --force-overwrite=true -s cpu --cudabacktrace=true -x true -o ${PROFILE_FILE} composer \
  --nproc 8 \
  --world_size 8 \
  --base_rank 0 \
  --master_addr $HEAD_NODE_IP \
  --master_port $RANDOM \
  train/train.py \
  train/yamls/pretrain/mpt-7b.yaml \
  data_local=my-copy-c4 \
  train_loader.dataset.split=train_small \
  eval_loader.dataset.split=val_small \
  max_duration=3ba \
  eval_interval=0 \
  save_folder=mpt-7b \
  device_train_microbatch_size=8 \
  global_train_batch_size=256
