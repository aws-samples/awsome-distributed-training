#!/bin/bash
#SBATCH --job-name="neox"
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --gres=gpu:8

set -uxo pipefail

# default variables for Enroot, if these variables are defined then use them
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/gpt-neox.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH,/opt/slurm/bin:/opt/slurm/bin}"
# SLurmRunner need `sinfo`
# https://github.com/microsoft/DeepSpeed/blob/bcc617a0009dd27b4e144de59979bd7770eaf57c/deepspeed/launcher/multinode_runner.py#L327
export PATH=${PATH}:/opt/slurm/bin
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

MODEL_CONFIG=${PWD}/configs/pythia/1-4B.json
#MODEL_CONFIG=${PWD}/configs/gpt2/350M.json
# Some potentially useful distributed environment variables
export HOSTNAMES=`scontrol show hostnames "$SLURM_JOB_NODELIST"`
export MASTER_ADDR=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)
export MASTER_PORT=12802
export COUNT_NODE=`scontrol show hostnames "$SLURM_JOB_NODELIST" | wc -l`
NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NODES_ARRAY=($NODES)
HEAD_NODE=${NODES_ARRAY[0]}
MASTER_ADDR=$(hostname --ip-address)
MASTER_PORT=$RANDOM
NNODES=$SLURM_JOB_NUM_NODES
NPROC=$SLURM_GPUS_PER_NODE
WORLD_SIZE=$(( $NNODES * $NPROC ))

mkdir -p ${FSX_PATH}/tmp/hostfiles
# need to add the current slurm jobid to hostfile name so that we don't add to previous hostfile
HOSTFILE=${FSX_PATH}/tmp/hostfiles/hosts_$SLURM_JOBID
# be extra sure we aren't appending to a previous hostfile
rm $HOSTFILE &> /dev/null
# loop over the node names
# for i in `scontrol show hostnames $SLURM_NODELIST`
# do
#     # add a line to the hostfile
#     echo $i slots=$SLURM_GPUS_PER_NODE >>$HOSTFILE
# done
function makehostfile() {
    perl -e '$slots=split /,/, $ENV{"SLURM_STEP_GPUS"};
    $slots=8 if $slots==0; # workaround 8 gpu machines
    @nodes = split /\n/, qx[scontrol show hostnames $ENV{"SLURM_JOB_NODELIST"}];
    print map { "$b$_ slots=$slots\n" } @nodes'
}
makehostfile > $HOSTFILE
echo "hostfile" $HOSTFILE
cat $HOSTFILE

# Tell DeepSpeed where to find our generated hostfile via DLTS_HOSTFILE
export DLTS_HOSTFILE=${HOSTFILE}

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

function run_deepspeed() {
    srun --nodelist=${NODE} --ntasks=1 -l "${ARGS[@]}" python3 deepy.py train.py ${MODEL_CONFIG} 
}

NODE_RANK=1
for (( NODE_RANK=1; NODE_RANK<${NNODES}; NODE_RANK++ ))
do
    NODE=${NODES[$NODE_RANK]}
    echo "Run compute node ${NODE} for rank: ${NODE_RANK}"
    run_deepspeed &
done
NODE_RANK=0
NODE=${HEAD_NODE}
echo "Run main node ${NODE} for rank: ${NODE_RANK}"
run_deepspeed
wait

