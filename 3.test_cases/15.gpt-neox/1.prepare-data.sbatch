#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH -N 1 # number of nodes to use
#SBATCH --job-name=pile-dataprep # name of your job
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --exclusive

# default variables for Enroot, if these variables are defined then use them
: "${APPS_PATH:=/fsx/apps}"
: "${IMAGE:=$APPS_PATH/gpt-neox.sqsh}"
: "${FSX_PATH:=/fsx}"
: "${DATA_PATH:=$FSX_PATH/pile_subset}"  # use pile to download entire dataset
: "${MODEL_PATH:=$FSX_PATH/gpt-neox}"    # use pile to download entire dataset
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"

DATASET=pile_subset                      # use pile to download entire dataset
echo "Retrieve and preprocess ${DATASET}"

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

srun -l "${ARGS[@]}" python prepare_data.py -d ${DATA_PATH} -t HFTokenizer \
        --vocab-file ${MODEL_PATH}/tokenizers/20B_tokenizer.json ${DATASEET}
