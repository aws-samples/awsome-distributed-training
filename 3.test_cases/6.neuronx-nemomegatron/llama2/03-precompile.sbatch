#!/bin/bash
#SBATCH --exclusive
#SBATCH --output=slurm-%x-%j.out
#SBATCH --cpus-per-task 96
#SBATCH --nodes 2

COMPILE=1 ./llama_7b.sh
