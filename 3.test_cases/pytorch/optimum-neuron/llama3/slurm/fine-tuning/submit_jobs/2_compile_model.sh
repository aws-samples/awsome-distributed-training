#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=compile
#SBATCH --output=/fsx/peft_ft/logs/2_parallel_compile_%j.out

export OMP_NUM_THREADS=1
export NEURON_EXTRACT_GRAPHS_ONLY=1

srun bash /fsx/peft_optimum_neuron/llama3-8B/finetune-llama3-8B.sh
