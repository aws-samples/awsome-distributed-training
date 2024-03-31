#!/bin/bash
#SBATCH --job-name=cpu-ddp-conda
#SBATCH --exclusive
#SBATCH --wait-all-nodes=1
#SBATCH --nodes 2
#SBATCH --cpus-per-task=4
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr

nodes=( $( scontrol show hostnames $SLURM_JOB_NODELIST ) )
nodes_array=($nodes)
head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address)

echo Node IP: $head_node_ip
export LOGLEVEL=INFO

srun ./pt_cpu/bin/torchrun \
--nnodes 2 \
--nproc_per_node 4 \
--rdzv_id $RANDOM \
--rdzv_backend c10d \
--rdzv_endpoint $head_node_ip:29500 \
ddp.py 5000000 10
