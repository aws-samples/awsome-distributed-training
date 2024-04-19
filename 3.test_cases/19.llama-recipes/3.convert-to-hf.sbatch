#!/bin/bash
#SBATCH --exclusive
#SBATCH --job-name=convert-llama-weights
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr
#SBATCH --nodes 1

: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/llama3.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${DATA_PATH:=$FSX_PATH/$DATASET}"
: "${MODEL_PATH:=$FSX_PATH/models}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"


declare -a ARGS=(
    --container-image ${IMAGE}
    --container-mounts /fsx
)

srun -l "${ARGS[@]}" python3 ${PWD}/llama/convert_llama_weights_to_hf.py \
    --input_dir ${MODEL_PATH}/llama2-meta --model_size 7B --output_dir ${MODEL_PATH}/llama2-hf/7B