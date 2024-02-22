#!/bin/bash
#SBATCH --nodes=2 # number of nodes to use, 24 p4d(e) = 192 A100 GPUs
#SBATCH --ntasks=2
#SBATCH --job-name=train-resnet-tf # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --ntasks-per-node 1 # Number of GPU per node
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --gpus-per-task=8 # Number of GPU per node
#SBATCH --gres=gpu:8 # number of GPU we reserve
#SBATCH --exclusive

set -euxo pipefail

# default variables for Enroot
: "${APPS_PATH:=/apps}"
: "${IMAGE:=$APPS_PATH/tensorflow.sqsh}"
: "${DATA_PATH:=/fsx}"
: "${FSX_MOUNT:=$DATA_PATH:$DATA_PATH}"
: "${APPS_MOUNT:=$APPS_PATH:$APPS_PATH}"

## EFA settings
export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
# export NCCL_ALGO=Ring
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa # change to eth if you want to use ENA for comparisons
export FI_EFA_ENABLE_SHM_TRANSFER=1
export FI_EFA_USE_HUGE_PAGE=0
# https://discuss.pytorch.org/t/nccl-network-is-unreachable-connection-refused-when-initializing-ddp/137352
# https://github.com/pytorch/pytorch/issues/68893
#export NCCL_SOCKET_IFNAME=ens
export NCCL_ASYNC_ERROR_HANDLING=1
export NCCL_DEBUG=INFO

# variables for Enroot
declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts ${FSX_MOUNT},${APPS_MOUNT}
)

NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NODES_ARRAY=($NODES)
HEAD_NODE=${NODES_ARRAY[0]}
MASTER_ADDR=$(hostname --ip-address)
MASTER_PORT=$RANDOM
NNODES=$SLURM_JOB_NUM_NODES
NPROC=$SLURM_GPUS_PER_NODE
WORLD_SIZE=$(( $NNODES * $NPROC ))
SCRIPTPATH="/apps/awsome-distributed-training/3.test_cases/7.tensorflow-distributed"

function run_worker() {
    # TODO TF_CONFIG
    srun --nodelist=${NODE} --ntasks=1 -l "${ARGS[@]}" python /src/worker.py ${NODE_RANK} $( scontrol show hostnames $SLURM_JOB_NODELIST )
}


echo "DUBUG" $NODES_ARRAY
# run the workers
NODE_RANK=1
for (( NODE_RANK=1; NODE_RANK<${NNODES}; NODE_RANK++ ))
do
    NODE=${NODES[$NODE_RANK]}
    echo "Run worker node ${NODE} for rank: ${NODE_RANK}"
    run_worker &
done
NODE_RANK=0
NODE=${HEAD_NODE}
echo "Run main node ${NODE} for rank: ${NODE_RANK}"
run_worker
wait
