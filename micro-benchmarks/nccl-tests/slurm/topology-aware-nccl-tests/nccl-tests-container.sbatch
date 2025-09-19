#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name=nccl-tests-container # name of your job
#SBATCH --nodes=16 # number of nodes to use, 
#SBATCH --ntasks-per-node 8 # Number of GPU per node (e.g 8 H200 for p5en.48xlarge)
###SBATCH --gpus-per-node=8 # number of GPU we reserve. Uncomment for AWS ParallelCluster
#SBATCH --output logs/%x_%j.out
#SBATCH --error logs/%x_%j.err
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1

### Disable hyperthreading by setting the tasks per core to 1
#SBATCH --ntasks-per-core=1

# Create logs directory if it doesn't exist
mkdir -p logs

###########################
###### User Variables #####
###########################

# Supported NCCL collective operations:
# - allreduce     : AllReduce collective (default)
# - allgather     : AllGather collective  
# - reducescatter : ReduceScatter collective
# - alltoall      : AllToAll collective
# - gather        : Gather collective
# - reduce        : Reduce collective
# - scatter       : Scatter collective
# - broadcast     : Broadcast collective
# - hypercube     : Hypercube collective
# - sendrecv      : SendRecv point-to-point

TEST_TYPE=${1:-allreduce}
APPS_PATH=${2:-/fsx}
SPLIT_MASK=${3:-0x0}
ENABLE_NCCL_DEBUG=${4:-false}

# default variables for Enroot
: "${NCCL_TESTS_PATH:=/opt/nccl-tests/build}"
: "${IMAGE:=$APPS_PATH/nccl-tests.sqsh}"

# Set binary path based on test type
case ${TEST_TYPE} in
    allreduce)
        TEST_BINARY="${NCCL_TESTS_PATH}/all_reduce_perf"
        ;;
    allgather)
        TEST_BINARY="${NCCL_TESTS_PATH}/all_gather_perf"
        ;;
    reducescatter)
        TEST_BINARY="${NCCL_TESTS_PATH}/reduce_scatter_perf"
        ;;
    alltoall)
        TEST_BINARY="${NCCL_TESTS_PATH}/alltoall_perf"
        ;;
    gather)
        TEST_BINARY="${NCCL_TESTS_PATH}/gather_perf"
        ;;
    reduce)
        TEST_BINARY="${NCCL_TESTS_PATH}/reduce_perf"
        ;;
    scatter)
        TEST_BINARY="${NCCL_TESTS_PATH}/scatter_perf"
        ;;
    broadcast)
        TEST_BINARY="${NCCL_TESTS_PATH}/broadcast_perf"
        ;;
    hypercube)
        TEST_BINARY="${NCCL_TESTS_PATH}/hypercube_perf"
        ;;
    sendrecv)
        TEST_BINARY="${NCCL_TESTS_PATH}/sendrecv_perf"
        ;;
    *)
        echo "Error: Unsupported test type '${TEST_TYPE}'"
        echo "Supported types: allreduce, allgather, reducescatter, alltoall, gather, reduce, scatter, broadcast, hypercube, sendrecv"
        exit 1
        ;;
esac

echo "Running NCCL ${TEST_TYPE} test in container with split mask ${SPLIT_MASK}"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting NCCL ${TEST_TYPE} test"

export NCCL_TESTS_SPLIT_MASK=${SPLIT_MASK}

## Set this flag for debugging EFA
#export FI_LOG_LEVEL=warn

## NCCL Environment variables
if [[ "${ENABLE_NCCL_DEBUG}" == "true" ]]; then
    export NCCL_DEBUG=INFO
    echo "NCCL debug enabled"
fi

declare -a ARGS=(
    --container-image $IMAGE
)

#Get Hostname and Instance IDs
mpirun -N 1 bash -c '
  HOSTNAME=$(hostname)
  ASSET_TAG=$(cat /sys/devices/virtual/dmi/id/board_asset_tag | tr -d " ")
  NCCL_VER=$(strings /opt/nccl/build/lib/libnccl.so | grep "NCCL version" | head -1 | awk "{print \$3}" 2>/dev/null || echo "N/A")
  AWS_OFI_NCCL_VER=$(strings /opt/amazon/ofi-nccl/lib/libnccl-net.so | grep "NET/OFI Initializing aws-ofi-nccl" | awk "{print \$4}" 2>/dev/null || echo "N/A")
  EFA_VER=$(grep -E "(version|installer)" /opt/amazon/efa_installed_packages 2>/dev/null | head -1 || echo "N/A")
  echo "hostname=$HOSTNAME ➡️ $ASSET_TAG | NCCL: $NCCL_VER | OFI-NCCL: $OFI_NCCL_VER | AWS-OFI-NCCL: $AWS_OFI_NCCL_VER | EFA: $EFA_VER"
'
# In the echo statement above , don't remove the string hostname=, it is used in converting the nccl output to csv in process_nccl_results.sh


# Run NCCL test with configurable split masks
srun "${ARGS[@]}" --mpi=pmix --cpu-bind=none $TEST_BINARY -b 8 -e 16G -f 2 -g 1 -c 1 -n 100
