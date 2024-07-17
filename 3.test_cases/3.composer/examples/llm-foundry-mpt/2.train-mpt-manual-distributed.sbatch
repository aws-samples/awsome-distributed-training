#!/bin/bash
#SBATCH --nodes=1 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --ntasks=1
#SBATCH --job-name=train-mpt # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --ntasks-per-node 1 # Number of GPU per node
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --gpus-per-task=8 # Number of GPU per node
#SBATCH --gres=gpu:8 # number of GPU we reserve
#SBATCH --exclusive

set -euxo pipefail

# use MTP 7B by default
MODEL=${1:-mpt-7b}

# default variables for Enroot
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/composer.sqsh}"
: "${DATA_PATH:=/fsx}"
: "${FSX_MOUNT:=$DATA_PATH:$DATA_PATH}"
: "${APPS_MOUNT:=$APPS_PATH:$APPS_PATH}"

## EFA settings
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_USE_HUGE_PAGE=0
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
#export NCCL_SOCKET_IFNAME=ens
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO
### Increase the send queue depth and can turn NCCL communications into non-blocking.
### https://www.usenix.org/system/files/atc23-choi.pdf
export NCCL_BUFFSIZE=8388608
### Improve performance by increasing buffer size for Send/Recv, Gather, Scatter and Alltoall communications
### https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/p2p.html
export NCCL_P2P_NET_CHUNKSIZE=524288
export NCCL_SOCKET_IFNAME=en

# variables for Enroot
declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts ${FSX_MOUNT},${APPS_MOUNT}
)

NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NODES_ARRAY=($NODES)
HEAD_NODE=${NODES_ARRAY[0]}
MASTER_ADDR=$(hostname --ip-address)
MASTER_PORT=$((RANDOM + 10000))
NNODES=$SLURM_JOB_NUM_NODES
NPROC=$SLURM_GPUS_PER_NODE
WORLD_SIZE=$(( $NNODES * $NPROC ))
srun -l "${ARGS[@]}" python -c "import streaming; streaming.base.util.clean_stale_shared_memory()"

# [20230929, mlkeita@] Launch composer on each node one-by-one. Unclear why, but
# when I try torun composer with single command with appropriate worldsize and
# etc. it fails to establish communication between nodes.
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
        --verbose ${PWD}/llm-foundry/scripts/train/train.py \
        ${PWD}/llm-foundry/scripts/train/yamls/pretrain/${MODEL}.yaml \
        variables.data_local=${DATA_PATH}/c4-dataset \
        model.loss_fn=torch_crossentropy \
        train_loader.dataset.split=train_small \
        eval_loader.dataset.split=val_small \
        max_duration=3ba \
        eval_interval=0 \
        save_folder=${MODEL}
}

# run the composer
NODE_RANK=1
for (( NODE_RANK=1; NODE_RANK<${NNODES}; NODE_RANK++ ))
do
    NODE=${NODES[$NODE_RANK]}
    echo "Run compute node ${NODE} for rank: ${NODE_RANK}"
    run_compose &
done
NODE_RANK=0
NODE=${HEAD_NODE}
echo "Run main node ${NODE} for rank: ${NODE_RANK}"
run_compose
wait
