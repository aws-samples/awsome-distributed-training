#!/bin/bash
#SBATCH --nodes=1                    # number of nodes
#SBATCH --ntasks-per-node=1          # n tasks per machine (one task per gpu) <required>
#SBATCH --gpus-per-node=8
#SBATCH --exclusive                   # exclusive node access
#SBATCH --output slurm-uniref-%j.out


###########################
###### User Variables #####
###########################

# default variables for Enroot
: "${IMAGE:=$(pwd)/bionemo.sqsh}"
: "${DATA_PATH:=/fsx}"
: "${FSX_MOUNT:=$DATA_PATH:$DATA_PATH}"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts $FSX_MOUNT
)

srun -l "${ARGS[@]}"  python3 /workspace/bionemo/prepare_uniref50.py
