#!/bin/bash
#SBATCH --output=logs/%x_%j.out  # Redirects outputs to file in current_dir/logs
#SBATCH --error=logs/%x_%j.out  # Redirects err to same file in current_dir/logs
#SBATCH --job-name=fsdp_smp

# has to be shared dir
CONDA_ENV_PATH=${1:-"$CONDA_DEFAULT_ENV"}
SHELL_SCRIPT=${2:-"scripts/model.sh"}
shift 2
SCRIPT_ARGS=$@

if [ -z $CONDA_ENV_PATH ]; then
    echo "Conda env path needs to be passed. Exiting"
    exit 1
fi
if [ -z "$SCRIPT_ARGS" ]; then
    SCRIPT_ARGS=""
else
    SCRIPT_ARGS+=" "
fi

SCRIPT_ARGS+="--use_synthetic_data 1 "

# Replace with real data like below
# SCRIPT_ARGS+="--training_dir /fsx/datasets/train_ids_wsvocab_redo_2048_smaller "
# SCRIPT_ARGS+="--test_dir /fsx/datasets/val_ids_wsvocab_2048 "

SCRIPT_ARGS+="--model_type gpt_neox --model_size 7b "
# SCRIPT_ARGS+="--max_steps 10 "
# SCRIPT_ARGS+="--train_batch_size 1 "

HOSTFILE=hosts_${SLURM_JOB_ID}
scontrol show hostnames | sort > $HOSTFILE
srun -l -D `pwd` conda run -p $CONDA_ENV_PATH --no-capture-output $SHELL_SCRIPT --hostfile $HOSTFILE $SCRIPT_ARGS
