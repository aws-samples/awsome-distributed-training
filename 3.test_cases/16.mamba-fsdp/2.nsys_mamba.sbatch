#!/bin/bash
#SBATCH --nodes=4                    # number of nodes, modify as needed
#SBATCH --ntasks-per-node=8          # one task per gpu, modify as needed
#SBATCH --gpus-per-node=8            # set for p4de, modify as needed
#SBATCH --exclusive                  # exclusive node access
#SBATCH --output slurm-mamba-pretrain-nsys-%j.out

set -ex;

###########################
###### User Variables #####
###########################

GPUS_PER_NODE=8 # 4 for G5.12x, 8 for P4/P5

###########################
## Environment Variables ##
###########################

export FI_EFA_USE_DEVICE_RDMA=1 # use for p4d
export FI_EFA_FORK_SAFE=1
export FI_LOG_LEVEL=1
export FI_PROVIDER=efa
export NCCL_DEBUG=INFO

###########################
####### Torch Dist  #######
###########################

declare -a TORCHRUN_ARGS=(
    --nproc_per_node=$GPUS_PER_NODE \
    --nnodes=$SLURM_JOB_NUM_NODES \
    --rdzv_id=$SLURM_JOB_ID \
    --rdzv_backend=c10d \
    --rdzv_endpoint=$(hostname) \
)

export TRAIN_SCRIPT=./train_fsdp.py

# Logging
# =========================
PROJECT_NAME="mamba_pretraining" # project name, will be used for logging
EXP_TAG="-small" # any additional experiment info, can be empty
EXP_NAME="mamba_pretrain_nodes${SLURM_JOB_NUM_NODES}${EXP_TAG}"
# =========================

srun -l /fsx/nsight-efa/target-linux-x64/nsys profile --output /fsx/nsys_profiles/ --stats true torchrun "${TORCHRUN_ARGS[@]}" $TRAIN_SCRIPT