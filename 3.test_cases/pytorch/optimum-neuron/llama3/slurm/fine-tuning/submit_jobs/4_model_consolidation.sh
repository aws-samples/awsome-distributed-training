#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=consolidation 
#SBATCH --output=/fsx/peft_ft/logs/4_model_consolidation_%j.log

export OMP_NUM_THREADS=1

srun python3 "/fsx/peft_optimum_neuron/model_consolidation.py" \
    --input_dir "/fsx/peft_ft/model_checkpoints/checkpoint-1251" \
    --output_dir "/fsx/peft_ft/model_checkpoints/adapter_shards_consolidation"\
    --save_format "safetensors"