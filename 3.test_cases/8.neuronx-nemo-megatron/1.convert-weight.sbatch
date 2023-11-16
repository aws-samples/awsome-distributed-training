#!/bin/bash
#SBATCH --exclusive
#SBATCH --output=slurm-%x-%j.out
#SBATCH --cpus-per-task 96
#SBATCH --nodes 1


source ~/aws_neuron_venv_pytorch/bin/activate
python /home/ec2-user/aws_neuron_venv_pytorch/lib/python3.8/site-packages/transformers/models/llama/convert_llama_weights_to_hf.py \
    --input_dir /fsx/Llama2-meta --model_size 7B --output_dir /fsx/Llama2-7b-hf
