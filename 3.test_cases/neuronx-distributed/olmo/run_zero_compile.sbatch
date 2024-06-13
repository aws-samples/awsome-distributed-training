#!/bin/bash
#SBATCH --nodes=4
#SBATCH --exclusive
#SBATCH --output=logs/slurm-%x-%j.out

srun neuron_parallel_compile ./run_zero.sh MIXED 