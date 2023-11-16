#!/bin/bash

cd ~/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling
source ~/aws_neuron_venv_pytorch/bin/activate
sbatch --nodes 4 run.slurm ./llama_7b.sh