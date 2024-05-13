#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --job-name="evaluate"
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gpus-per-node=8 # Number of GPU per node
#SBATCH --output=logs/%x_%j.out # logfile for stdout
#SBATCH --error=logs/%x_%j.err # logfile for stderr, remove it to merge both outputs
#SBATCH --wait-all-nodes=1
#SBATCH --exclusive
set -euxo pipefail
source .env
: "${FSX_PATH:=/fsx}"
: "${APPS_PATH:=${FSX_PATH}/apps}"
: "${IMAGE:=$APPS_PATH/llama3.sqsh}"
: "${CONTAINER_MOUNT:=$FSX_PATH:$FSX_PATH}"
export HF_HOME=/fsx/.cache

declare -a ARGS=(
    --container-image $IMAGE
    --container-mounts $CONTAINER_MOUNT
)

#declare -a HELP=(
#    "[--help]"
#    "[--host]"
#    "[--port]"
#    "[--model-url]"
#)
#
#parse_args() {
#    local key
#    while [[ $# -gt 0 ]]; do
#        key="$1"
#        case $key in
#        --help)
#            echo "Launch Gradio App locally, querying endpoint hosted on a compute node" 
#            echo "It requires endpoint pre-deployed. Use 4.serve-vllm.sbatch for deployment" 
#            echo "Usage: $(basename ${BASH_SOURCE[0]}) ${HELP[@]}"
#            exit 0
#            ;;
#        --host)
#            HOST="$2"
#            shift 2
#            ;;
#        --port)
#            PORT="$2"
#            shift 2
#            ;;
#        esac
#    done
#}
#
#parse_args $@

export PYTHONPATH=${PWD}/llama-recipes/src
srun -l "${ARGS[@]}" bash -c "pip uninstall -y transformer_engine \
    && pip install -e ${PWD}/lm-evaluation-harness \
    && python ${PWD}/llama-recipes/recipes/evaluation/eval.py \
    --model vllm --tasks hellaswag --model_args "pretrained=meta-llama/Meta-Llama-3-70B,tensor_parallel_size=8,dtype=auto,gpu_memory_utilization=0.8,data_parallel_size=1" \
    --limit 100  --output_path /fsx/lm-evaluation-harness-results --log_samples --batch_size 1"
    # && python ${PWD}/llama-recipes/recipes/evaluation/eval.py \
    # --model vllm --model_args "pretrained=meta-llama/Meta-Llama-3-70B,tensor_parallel_size=8,dtype=auto,gpu_memory_utilization=0.8,data_parallel_size=1" \
    # --limit 100 --open_llm_leaderboard_tasks --output_path ./results.json --log_samples --batch_size auto"
    # && torchrun ${PWD}/llama-recipes/recipes/evaluation/eval.py \
    #  --model hf --model_args pretrained=meta-llama/Meta-Llama-3-8B --tasks hellaswag --device cuda:0   --batch_size 8"