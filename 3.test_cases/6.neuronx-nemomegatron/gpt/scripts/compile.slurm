#!/bin/bash
#SBATCH --exclusive
#SBATCH --output=slurm-%x-%j.out
#SBATCH --cpus-per-task 96

source /home/ec2-user/aws_neuron_venv_pytorch/bin/activate
srun neuron_parallel_compile $1
