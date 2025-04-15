#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=finetuning 
#SBATCH --output=/fsx/peft_ft/logs/3_finetune_%j.log

export OMP_NUM_THREADS=1
export NEURON_EXTRACT_GRAPHS_ONLY=0

srun bash /fsx/peft_optimum_neuron/llama3-8B/finetune-llama3-8B.sh
