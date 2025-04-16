#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=finetuning 
#SBATCH --output=/fsx/ubuntu/peft_ft/logs/3_finetune.log

export OMP_NUM_THREADS=1
export NEURON_EXTRACT_GRAPHS_ONLY=0

srun bash /fsx/ubuntu/awsome-distributed-training/3.test_cases/pytorch/optimum-neuron/llama3/slurm/fine-tuning/llama3-8B/finetune-llama3-8B.sh
