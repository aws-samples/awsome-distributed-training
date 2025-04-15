#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=merge 
#SBATCH --output=/fsx/peft_ft/logs/5_lora_weights_%j.log

export OMP_NUM_THREADS=1

srun python3 "/fsx/peft_optimum_neuron/merge_lora_weights.py" \
    --final_model_path "/fsx/peft_ft/model_checkpoints/final_model_output" \
    --adapter_config_path "/fsx/peft_ft/model_checkpoints/checkpoint-1251/adapter_config.json"\
    --base_model_path "/fsx/peft_ft/model_artifacts/llama3-8B" \
    --lora_safetensors_path "/fsx/peft_ft/model_checkpoints/adapter_shards_consolidation/model.safetensors" 
