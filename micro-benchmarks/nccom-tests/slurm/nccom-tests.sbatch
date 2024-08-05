#!/bin/bash
#SBATCH --job-name=nccom-all_reduce_perf # name of your job
#SBATCH --nodes=2 # number of nodes to use
#SBATCH --output logs/%x_%j.out
#SBATCH --exclusive
set -euxo pipefail
export FI_LOG_LEVEL=Warn
export FI_PROVIDER=efa
NODES=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
NODES_ARRAY=($NODES)
HEAD_NODE=${NODES_ARRAY[0]}
NNODES=$SLURM_JOB_NUM_NODES
MASTER_ADDR=$SLURMD_NODENAME
MASTER_PORT=$((RANDOM + 10000))
NPROC=32 # number of Neuron Devices
NWORKERS=$(($NNODES * $NPROC))
declare -a NCCOM_ARGS=(
    --nworkers ${NWORKERS} 
    --nnodes ${NNODES} 
    --minbytes 8 
    --maxbytes 512KB
    --stepfactor 2 
    --iters 5 
    --warmup_iters 5 
    --datatype fp32
)
CC_OPS=all_reduce # all_reduce/all_gather/reduce_scatter/sendrecv/alltoall
NEURON_RT_ROOT_COMM_ID=${MASTER_ADDR}:${MASTER_PORT} \
    nccom-test \
    "${NCCOM_ARGS[@]}" ${CC_OPS} \
    --hosts ${NODES[@]}