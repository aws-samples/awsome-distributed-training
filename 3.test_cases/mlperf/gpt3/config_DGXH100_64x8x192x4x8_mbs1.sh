# dryrun "large" config

## DL params
export MINIBS=192
export TENSOR_MODEL_PARALLEL=4   #  training.model.tensor_model_parallel_size
export PIPELINE_MODEL_PARALLEL=8 #  training.model.pipeline_model_parallel_size
export DGXNNODES=64
#=======================================================================
## System run parms
export DGXSYSTEM=$(basename $(readlink -f ${BASH_SOURCE[0]}) | sed 's/^config_//' | sed 's/\.sh$//' )

export WALLTIME_MINUTES=190
export WALLTIME=$(( (${NEXP:-1} * WALLTIME_MINUTES) ))

## System config params
source $(dirname ${BASH_SOURCE[0]})/config_common.sh
source $(dirname ${BASH_SOURCE[0]})/config_fp8.sh

export MICRO_BATCH_SIZE=1
export TP_COMM_OVERLAP=True