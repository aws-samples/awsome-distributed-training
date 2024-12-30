#!/bin/bash
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --exclusive   		# exclusive node access
#SBATCH -o logs/%x-%j.out
#SBATCH -J train-cosmoflow


: "${IMAGE:=/home/ubuntu/awsome-distributed-training/3.test_cases/tensorflow/cosmoflow/cosmoflow.sqsh}"

set -euxo pipefail
# export OMP_NUM_THREADS=32
# export KMP_BLOCKTIME=1
# export KMP_AFFINITY="granularity=fine,compact,1,0"
# export HDF5_USE_FILE_LOCKING=FALSE

export FI_PROVIDER=efa
export FI_EFA_FORK_SAFE=1
## Set this flag for debugging EFA
#export FI_LOG_LEVEL=warn

## NCCL Environment variables
export NCCL_DEBUG=INFO
export OPAL_PREFIX=

# variables for Enroot
declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts /fsx,/home
    --mpi=pmix
)

declare -a CMD=(
    python
    /home/ubuntu/awsome-distributed-training/3.test_cases/tensorflow/cosmoflow/train.py
    /workspace/configs/cosmo_dummy.yaml
    --distributed
    --mlperf
)

srun -l "${ARGS[@]}"  "${CMD[@]}"
