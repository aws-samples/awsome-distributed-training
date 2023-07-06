#!/bin/bash
#SBATCH -N 1
#SBATCH --exclusive

# cd MegatronLoader
# docker build -t megatronloader .
# .sqsh file produced by enroot import -o ./megatronloader.sqsh  dockerd://megatronloader:latest
: "${IMAGE:=$APPS_PATH/megatronloader.sqsh}"
: "${FSX_MOUNT:=/fsx:/fsx}"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mount-home
    --container-mounts $FSX_MOUNT
)

# runs in
srun -l "${ARGS[@]}"  python3 /workspace/Megatron-LM//tools/preprocess_data.py \
        --input ${DATA_PATH}/oscar-1GB.jsonl \
        --output-prefix ${DATA_PATH}/my-gpt2 \
        --vocab-file ${DATA_PATH}/gpt2-vocab.json \
        --dataset-impl mmap \
        --tokenizer-type GPT2BPETokenizer \
        --merge-file ${DATA_PATH}/gpt2-merges.txt \
        --append-eod \
        --workers 64
