#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=inference
#SBATCH --output=/fsx/peft_ft/logs/6_inference_%j.log

export OMP_NUM_THREADS=1
export HUGGINGFACE_TOKEN="<Your Hugging Face Token>"

srun python3 "/fsx/peft_optimum_neuron/run_inference.py" \
    --model_path "/fsx/peft_ft/model_checkpoints/final_model_output" \
    --model_id "meta-llama/Meta-Llama-3-8B-Instruct"