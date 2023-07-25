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

export PROFILE_FILE=/report/profile_file

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
    if [ ${NODE_RANK} -eq 0 ]; then
        OPTION="nodelist"
    else
        OPTION="exclude"
    fi
    srun --${OPTION}=${HEAD_NODE} --ntasks=1 -l "${ARGS[@]}" bash \
    /apps/reference-architectures/3.test_cases/3.MPT/slurm-scripts/run-composer.sh \
    ${WORLD_SIZE} ${NPROC} ${NODE_RANK} ${MASTER_ADDR} ${MASTER_PORT}
}
NODE_RANK=1
run_compose &
NODE_RANK=0
run_compose &
wait