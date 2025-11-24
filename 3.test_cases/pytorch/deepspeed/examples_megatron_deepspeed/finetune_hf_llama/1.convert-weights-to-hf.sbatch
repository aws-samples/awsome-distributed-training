#!/bin/bash
#SBATCH --exclusive
#SBATCH --job-name=convert-llama-weights
#SBATCH --output=logs/%x_%j.out # logfile for stdout/stderr
#SBATCH --nodes 1

: "${CONTAINER_PATH:=/fsxl/containers}"
: "${IMAGE:=$CONTAINER_PATH/deepspeed.sqsh}"
: "${FSX_PATH:=/fsxl}"
: "${DATASET:=c4_subset}"
: "${DATA_PATH:=$FSX_PATH/$DATASET}"
: "${MODEL_PATH:=$FSX_PATH/deepspeed}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"


declare -a ARGS=(
    --container-image ${IMAGE}
    --container-mount-home
    --container-mounts ${FSX_PATH}
)

srun -l "${ARGS[@]}" python3 ${PWD}/src/convert_llama_weights_to_hf.py \
    --input_dir ${MODEL_PATH}/Llama2-meta --model_size 7B --output_dir ${MODEL_PATH}/Llama2-7b-hf