#!/bin/bash
#SBATCH --exclusive
#SBATCH --output=slurm-%x-%j.out
#SBATCH --cpus-per-task 96
#SBATCH --nodes 1

source ~/aws_neuron_venv_pytorch/bin/activate
python /home/ec2-user/neuronx-nemo-megatron/nemo/scripts/nlp_language_modeling/preprocess_data_for_megatron.py \
    --input=/fsx/data/llama2/book.jsonl \
    --json-keys=text \
    --tokenizer-library=huggingface \
    --tokenizer-type=/fsx/Llama2-7b-hf \
    --dataset-impl=mmap \
    --output-prefix=/fsx/data/llama2/book-tokenized \
    --append-eod \
    --need-pad-id \
    --workers=32