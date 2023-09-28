#!/bin/bash
#SBATCH --nodes=2 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --ntasks=2
#SBATCH --job-name=train-mpt # name of your job
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --ntasks-per-node 1 # Number of GPU per node
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --gpus-per-task=8 # Number of GPU per node
#SBATCH --gres=gpu:8 # number of GPU we reserve
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1
set -euxo pipefail

MODEL=${1:-mpt-7b}
# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${IMAGE:=$APPS_PATH/llm-foundry.sqsh}"
: "${DATA_PATH:=/fsx}"
: "${FSX_MOUNT:=$DATA_PATH:$DATA_PATH}"
: "${APPS_MOUNT:=$APPS_PATH:$APPS_PATH}"

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


declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts ${FSX_MOUNT},${APPS_MOUNT}
)

NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NNODES=${#NODES[@]}
NODES_ARRAY=($NODES)
HEAD_NODE=${NODES_ARRAY[0]}
MASTER_ADDR=$(srun --nodes=1 --ntasks=1 -w "$HEAD_NODE" hostname --ip-address)
MASTER_PORT=$RANDOM
NPROC=8
WORLD_SIZE=$((NNODES * NPROC))
srun -l "${ARGS[@]}" python -c "import streaming; streaming.base.util.clean_stale_shared_memory()"
function run_compose() {
    # if [ ${NODE_RANK} -eq 0 ]; then
    #     OPTION="nodelist"
    # else
    #     OPTION="exclude"
    # fi
    srun --nodelist=${NODE} --ntasks=1 -l "${ARGS[@]}" composer \
        --world_size ${WORLD_SIZE} \
        --nproc ${NPROC} \
        --node_rank ${NODE_RANK} \
        --master_addr ${MASTER_ADDR} \
        --master_port ${MASTER_PORT} \
        --verbose /llm-foundry/scripts/train/train.py \
        /llm-foundry/scripts/train/yamls/pretrain/${MODEL}.yaml \
        data_local=/fsx/c4-dataset \
        train_loader.dataset.split=train_small \
        eval_loader.dataset.split=val_small \
        max_duration=3ba \
        eval_interval=0 \
        save_folder=${MODEL}
}
NODE_RANK=1
for (( NODE_RANK=1; NODE_RANK<${NNODES}; NODE_RANK++ ))
do
    NODE=${NODES[$NODE_RANK]}
    echo "Run compute node ${NODE} for rank: ${NODE_RANK}"
    run_compose &
done
NODE_RANK=0
NODE=${HEAD_NODE}
echo "Run master node ${NODE} for rank: ${NODE_RANK}"
run_compose
wait
