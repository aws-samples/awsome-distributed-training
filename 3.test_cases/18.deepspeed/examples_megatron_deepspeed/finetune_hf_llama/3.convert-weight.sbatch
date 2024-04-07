#!/bin/bash
#SBATCH --exclusive
#SBATCH --output=slurm-%x-%j.out
#SBATCH --nodes 1

: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/deepspeed.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${DATASET:=c4_subset}"
: "${DATA_PATH:=$FSX_PATH/$DATASET}"
: "${MODEL_PATH:=$FSX_PATH/deepspeed}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"


declare -a ARGS=(
    --container-image ${APPS_PATH}
    --container-mounts realpath ${PWD}/../..
)

srun -l "${ARGS[@]}" python src/convert_llama_weights_to_hf.py \
    --input_dir ${MODEL_PATH}/Llama2-meta --model_size 7B --output_dir ${MODEL_PATH}/Llama2-7b-hf