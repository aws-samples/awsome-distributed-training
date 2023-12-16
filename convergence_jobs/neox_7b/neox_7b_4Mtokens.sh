#!/bin/bash
#SBATCH --output=logs/%x_%j.out  # Redirects outputs to file in current_dir/logs
#SBATCH --error=logs/%x_%j.out  # Redirects err to same file in current_dir/logs
#SBATCH --job-name=neox_7b

# has to be shared dir
CONDA_ENV_PATH=${1:-"$CONDA_DEFAULT_ENV"}
SHELL_SCRIPT=${2:-"scripts/model.sh"}

set -ex

if [ -z $CONDA_ENV_PATH ]; then
    echo "Conda env path needs to be passed. Exiting"
    exit 1
fi

# To keep track of which job used which node for identifying node causing crash if any
HOSTFILE=hosts_${SLURM_JOB_ID}
scontrol show hostnames | sort > $HOSTFILE
NUM_NODES=$(cat $HOSTFILE | wc -l)

## DATA
## CHANGE TO YOUR OWN CUSTOM DATASET PATH
SCRIPT_ARGS="--training_dir /fsx/datasets/train_ids_wsvocab_redo_2048_smaller "
SCRIPT_ARGS+="--test_dir /fsx/datasets/val_ids_wsvocab_2048 "

## MODEL
model_type=gpt_neox
SCRIPT_ARGS+="--model_type $model_type --model_size 7b "


## BATCH SIZE
if [ $NUM_NODES -lt 16 ]; then
    echo "Can't use 4M tokens with less than 16 nodes"
    exit 1
else
    GLOBAL_BATCH_SIZE=4194304
fi
max_context_width=2048  # seqlen
train_batch_size=$(python -c "print($GLOBAL_BATCH_SIZE//($NUM_NODES * 8 * $max_context_width))")

if [ $train_batch_size -le 2 ]; then
    SCRIPT_ARGS+="--activation_checkpointing 0 "
fi

SCRIPT_ARGS+="--train_batch_size $train_batch_size "
SCRIPT_ARGS+="--val_batch_size $train_batch_size "
SCRIPT_ARGS+="--max_context_width $max_context_width "
SCRIPT_ARGS+="--max_steps 143000 "
SCRIPT_ARGS+="--validation_freq 200 "

## ARTIFACTS
SCRIPT_ARGS+="--checkpoint_dir checkpoints/$SLURM_JOB_NAME/ "
SCRIPT_ARGS+="--tensorboard_dir tensorboard_logs/$SLURM_JOB_NAME/ "

## RESUME
# SCRIPT_ARGS+="--resume_from_checkpoint checkpoints/$SLURM_JOB_NAME/$model_type-400steps "

srun -l -D `pwd` conda run -p $CONDA_ENV_PATH --no-capture-output $SHELL_SCRIPT --hostfile $HOSTFILE $SCRIPT_ARGS
