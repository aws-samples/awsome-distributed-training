#!/bin/bash

# Copyright (c) 2022-2023, NVIDIA CORPORATION. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#           http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#SBATCH --exclusive
#SBATCH --mem=0

set -eux

# Vars without defaults
: "${CONT:?CONT not set}"
: "${DGXSYSTEM:?DGXSYSTEM not set}"
: "${NEXP:?NEXP not set}"
: "${WALLTIME:=?WALLTIME not set}"

# Vars with defaults
: "${MLPERF_RULESET:=3.1.0}"
: "${MLPERF_CLUSTER_NAME:='unknown'}"
: "${CHECK_COMPLIANCE:=1}"
: "${SEED_BASE:=${SEED-$RANDOM}}"
export SHARE_RERUNS=${SHARE_RERUNS:=0}
: "${API_LOG_DIR:=./api_logs}" # apiLog.sh output dir
: "${API_LOGGING:=0}"
: "${CLEAR_CACHES:=1}"
: "${CONT_FILE:=/lustre/fsw/containers/${SLURM_JOBID}_$(basename ${CONT}).squashfs}"
: "${CONTAINER_PRELOAD_LUSTRE:=0}"
: "${DATESTAMP:=$(date +'%y%m%d%H%M%S%N')}"
: "${LOGDIR:=./results}"
: "${ABSLOGDIR:=${PWD}/results}"
: "${POWERCMDDIR:=' '}"
: "${NSYSCMD:=""}"
: "${NVTX_FLAG:=0}"
: "${TIME_TAGS:=0}"
: "${NCCL_TEST:=1}"
: "${NCCL_LLM_TEST:=1}"
: "${RUN_ONLY_NCCL:=0}"
: "${SYNTH_DATA:=0}"
: "${EPOCH_PROF:=0}"
: "${WORK_DIR:=/workspace/llm}"
: "${DGXNGPU:=8}"
: "${STORE_CKPTS_IN_LOGDIR:=1}"
: "${CHECKPOINTS_DIR:=}"
: "${GLOBAL_TMP_NPY_INDEX_DIR:=$LOGDIR}"
: "${GLOBAL_TMP_CHECKPOINTS_DIR:=}"
: "${SRUN_KILL_ON_BAD_EXIT:=0}"
: "${DROPCACHE_CMD:="sudo /sbin/sysctl vm.drop_caches=3"}"
: "${HANG_MONITOR_TIMEOUT:=$([[ "$WALLTIME" -ge 60 ]] && echo 7 || echo 0)}"  # by default turned off for jobs shorter than 1h, otherwise 5 minutes
: "${ATTEMPT_CUDA_GDB_CORE_DUMP:=1}"
: "${POSTPROCESS_CUDA_GDB_CORE_DUMP:=1}"  # set to 1 to extract active kernel info from dumps.
: "${REMOVE_CUDA_GDB_CORE_DUMP:=1}"  # set to 1 to remove coredumps after processing. Will save a lot of disk space. Valid if POSTPROCESS_CUDA_GDB_CORE_DUMP is 1
# Set GPC clock for MaxQ and minEDP
: "${SET_MAXQ_CLK:=0}"
: "${SET_MINEDP_CLK:=0}"

# NOTE: We need to mount npy_index directory _somewhere_ because those files
# are exchanged between nodes through filesystem. We can't mount it in a fixed
# place, because then they would be reused (which is forbidden).
# We want to remove the whole npy_index directory afterwards.
# In certain situations (slurm timeout) cleanup hook is not triggered,
# that's why we put npy_index in GLOBAL_TMP_NPY_INDEX_DIR by default
# so they can be easily removed manually.
: "${NPY_INDEX_DIR:=${GLOBAL_TMP_NPY_INDEX_DIR}/${DATESTAMP}_npy_index}"
: "${CLEANUP_NPY_INDEX_DIR:=1}"

# Add any cluster specific madditional mounts
: "${EXTRA_MOUNTS:=""}"

# RUNSUB_DIR is the directory containing the run.sub script, so we can call
# other scripts relative to the location of the run.sub script
if [[ "${SLURM_JOB_ID}" ]]; then
    export RUNSUB_DIR=$(dirname $(scontrol show job "${SLURM_JOB_ID}" | awk -F= '/Command=/{print $2}'))
else
    export RUNSUB_DIR=$(dirname "${BASH_SOURCE[0]}")
fi
export MLPERF_SLURM_FIRSTNODE="$(scontrol show hostnames "${SLURM_JOB_NODELIST-}" | head -n1)"
#export MLPERF_SLURM_FIRSTNODE="$(hostname -I | cut -f1 -d ' ')"

# pyxis sometimes leaves containers lying around which can really confuse things:
cleanup_pyxis() {
    srun --ntasks="${SLURM_JOB_NUM_NODES}" /bin/bash -c 'if [[ "$(enroot list)" ]]; then enroot remove -f $(enroot list); fi'
}
cleanup_pyxis

# Other vars
export MODEL_NAME="large_language_model"
export MODEL_FRAMEWORK="pytorch"
LOGBASE="${DATESTAMP}"
SPREFIX="${MODEL_NAME}_${MODEL_FRAMEWORK}_${DGXNNODES}x${DGXNGPU}_${DATESTAMP}"

if [ ${SHARE_RERUNS:-0} -eq 1 ]; then
  export NEMO_RESULTS_SUBDIR='shared_logs'
else
  export NEMO_RESULTS_SUBDIR=$LOGBASE
fi

if [ -z "${CHECKPOINTS_DIR}" ] && [ ${STORE_CKPTS_IN_LOGDIR:-1} -eq 0 ]; then
  if [ -z "${GLOBAL_TMP_CHECKPOINTS_DIR}" ]; then
    echo "Error: if STORE_CKPTS_IN_LOGDIR=0, either CHECKPOINTS_DIR or GLOBAL_TMP_CHECKPOINTS_DIR must be set."
    exit 1
  fi
  LOGDIR_SUFFIX=${LOGDIR#$(dirname $(dirname $(dirname $LOGDIR)))}
  CHECKPOINTS_DIR=${GLOBAL_TMP_CHECKPOINTS_DIR}/$LOGDIR_SUFFIX/checkpoints  # take 3 immediate parents of LOGDIR
  echo "Storing checkpoints in CHECKPOINTS_DIR=${CHECKPOINTS_DIR}."
  ( umask 0002; mkdir -p "${CHECKPOINTS_DIR}" )
fi

# Setup directories
( umask 0002; mkdir -p "${LOGDIR}"; mkdir -p "${LOGDIR}/${NEMO_RESULTS_SUBDIR}"; mkdir -p $NPY_INDEX_DIR )

if [ ${TIME_TAGS} -gt 0 ]; then
    LOGBASE="${SPREFIX}_mllog"
fi
if [ ${NVTX_FLAG} -gt 0 ]; then
    if [[ "$LOGBASE" == *'-'* ]];then
        LOGBASE="${LOGBASE}_nsys"
    else
        LOGBASE="${SPREFIX}_nsys"
    fi
fi
if [ ${SYNTH_DATA} -gt 0 ]; then
    if [[ "$LOGBASE" == *'-'* ]];then
        LOGBASE="${LOGBASE}_synth"
    else
        LOGBASE="${SPREFIX}_synth"
    fi
fi
if [ ${EPOCH_PROF} -gt 0 ]; then
    if [[ "$LOGBASE" == *'-'* ]];then
        LOGBASE="${LOGBASE}_epoch"
    else
        LOGBASE="${SPREFIX}_epoch"
    fi
fi

readonly LOG_FILE_BASE="${LOGDIR}/${LOGBASE}"
readonly _logfile_base="${LOGDIR}/${LOGBASE}"
readonly _cont_name="${MODEL_NAME}_${SLURM_JOB_ID}"

_cont_mounts="${SPM}:/workspace/llm/tokenizer.model,${LOAD_CHECKPOINTS_PATH}:/load_checkpoints"
_cont_mounts="${LOGDIR}:/results,${NPY_INDEX_DIR}:/npy_index,${_cont_mounts}"

if [ "${EXTRA_MOUNTS}" != "" ]; then
    _cont_mounts="${EXTRA_MOUNTS},${_cont_mounts}"
fi

if [ "${API_LOGGING}" -eq 1 ]; then
    API_LOG_DIR=${API_LOG_DIR}/${MODEL_FRAMEWORK}/${MODEL_NAME}/${DGXSYSTEM}
    mkdir -p ${API_LOG_DIR}
    _cont_mounts="${_cont_mounts},${API_LOG_DIR}:/logs"

    # Create JSON file for cuDNN
    JSON_MODEL_NAME="MLPERF_${MODEL_NAME}_${MODEL_FRAMEWORK}_train"
    JSON_README_LINK="${README_PREFIX}/${MODEL_NAME}/${MODEL_FRAMEWORK}/README.md"
    JSON_FMT='{model_name: $mn, readme_link: $rl, configs: {($dt): [$bs]}, sweep: {($dt): [$bs]}}'
    JSON_OUTPUT="${JSON_MODEL_NAME}.cudnn.json"
    jq -n --indent 4 --arg mn $JSON_MODEL_NAME --arg rl $JSON_README_LINK --arg dt $APILOG_PRECISION --arg bs $BATCHSIZE "$JSON_FMT" > ${API_LOG_DIR}/$JSON_OUTPUT
fi
if [ "${USE_SYNTHETIC_DATASET:-0}" -eq 0 ]; then
    _cont_mounts="${_cont_mounts},$PREPROC_DATA:/preproc_data"
fi
if [ "${JET:-0}" -eq 1 ]; then
    _cont_mounts="${_cont_mounts},${JET_DIR}:/root/.jet"
fi
if [[ -n "${CHECKPOINTS_DIR}" ]] && [[ ${RUN_ONLY_NCCL} -eq 0 ]]; then
    _cont_mounts="${_cont_mounts},${CHECKPOINTS_DIR}:/results/${NEMO_RESULTS_SUBDIR}/checkpoints"
fi
if [ "${REMOUNT_WORKDIR:-0}" -eq 1 ]; then
    echo 'Remounting workdir'
    _cont_mounts="$(pwd):/workspace/llm,${_cont_mounts}"
fi
if [ -n "${REMOUNT_NEMO_PATH:-}" ]; then
    echo "Remounting Nemo from ${REMOUNT_NEMO_PATH}"
    _cont_mounts="${REMOUNT_NEMO_PATH}:/opt/bignlp/NeMo,${_cont_mounts},${REMOUNT_NEMO_PATH}:/workspace/NeMo"
fi

echo _cont_mounts="${_cont_mounts}"

SRUN_EXTRA_ARGS=""
if [ "${SRUN_KILL_ON_BAD_EXIT}" -eq 1 ]; then
    SRUN_EXTRA_ARGS+=" --kill-on-bad-exit=1"
else
    SRUN_EXTRA_ARGS+=" --kill-on-bad-exit=0"
fi

#########################################################################
# make sure "preload" tmp containers get cleaned on all possible exits (except
# kill -9)
#########################################################################
cleanup_preload_lustre() {
    if [[ "${CONTAINER_PRELOAD_LUSTRE:-0}" != "0" ]]; then
	# since this command only needs to run once, and impacts the global
	# file system, not something local to nodes, we don't need to run it
	# under srun.  It's preferable to run this directly, rarther than under
	# srun, because if we're running cleanup because we exceeded our time
	# limit, slurm won't launch a new srun for us, while just running a
	# command directly should work
	rm "${CONT_FILE:?ERROR!CONT_FILE!UNDEFINED}"
    fi
}


#########################################################################
# container preload option
#########################################################################
if [[ $CONTAINER_PRELOAD_LUSTRE -gt 0 ]]; then
    CONT_FILE="/lustre/fsw/containers/${SLURM_JOBID}_$(basename ${CONT}).squashfs"
    # Prepull container to LUSTRE
    srun --ntasks=1 enroot import --output ${CONT_FILE} docker://${CONT}
else
    CONT_FILE=${CONT}
fi

echo "CI directory structure\n"
echo $(ls)

cleanup_npy_index_dir() {
    if [[ $CLEANUP_NPY_INDEX_DIR -gt 0 ]]; then
	# since this command only needs to run once, and impacts the global
	# file system, not something local to nodes, we don't need to run it
	# under srun.  It's preferable to run this directly, rarther than under
	# srun, because if we're running cleanup because we exceeded our time
	# limit, slurm won't launch a new srun for us, while just running a
	# command directly should work
	rm -rf "${NPY_INDEX_DIR}"
    fi
}

cleanup_containers() {
    cleanup_npy_index_dir
    cleanup_preload_lustre
    cleanup_pyxis
}
trap cleanup_containers TERM EXIT

# do we need to fetch the data from remote disk into local /tmp disk?
if [[ "${TARFILE_FOR_PREPROC_DATA:-}" ]]; then
    # make sure we didn't accidentally specify the remote disk as the tmpdir
    if [[ "${PREPROC_DATA}" == *mnt* ]]; then
	echo "ERROR: ${PREPROC_DATA} looks like a lustre mount rather than a tmp dir, yet TARFILE_FOR_PREPROC_DATA is set to ${TARFILE_FOR_PREPROC_DATA}!!!"
	exit 1
    fi
    # manage data in tmpdir on every node
    srun --ntasks="${SLURM_JOB_NUM_NODES}" \
	 "${RUNSUB_DIR}/manage-tmp-data" \
	 "${TARFILE_FOR_PREPROC_DATA}" "${PREPROC_DATA}"   \
	 "${MD5SUM_FOR_PREPROC_DATA}"
fi

# Setup container
echo MELLANOX_VISIBLE_DEVICES="${MELLANOX_VISIBLE_DEVICES:-}"
srun --ntasks="$((SLURM_JOB_NUM_NODES))" --container-image="${CONT_FILE}" --container-name="${_cont_name}" true

srun -N1 -n1 --container-name="${_cont_name}" ibv_devinfo --list
srun -N1 -n1 --container-name="${_cont_name}" nvidia-smi topo -m

# Run NCCL test (700 MB FP16 allreduce)
#srun --mpi=pmix --ntasks="$(( SLURM_JOB_NUM_NODES * DGXNGPU ))" --ntasks-per-node="${DGXNGPU}" \
#        --container-image=${CONT_FILE} \
#        all_reduce_perf_mpi -b 85M -e 680M -f 2 -d half

if [[ "${USE_IPOIB:-}" == "1" ]]; then
    # list out the ipoib ip addresses and (arbitrarily) choose the last one
    export MASTER_ADDR=$(ip -4 -o addr | egrep -v 'enp|127.0.0.1|docker' | awk '{print $4}' | awk -F / '{print $1}' | tail -n1)
    export MASTER_PORT=55501
fi

echo "LLM NCCL_TEST"
if [[ ${NCCL_LLM_TEST} -eq 1 ]]; then
    (srun --mpi="${SLURM_MPI_TYPE:-pmix}" --ntasks="$(( SLURM_JOB_NUM_NODES * DGXNGPU ))" --ntasks-per-node="${DGXNGPU}" \
         --container-name="${_cont_name}" --container-mounts=${_cont_mounts} --container-workdir=${WORK_DIR} slurm2pytorch python3 /workspace/llm/scripts/nccl-tests/pytorch_nccltest.py -n 200 -t ${TENSOR_MODEL_PARALLEL} -p ${PIPELINE_MODEL_PARALLEL} -b 100M -e 100M --coll-only -c reduce_scatter )
fi

echo "NCCL_TEST = ${NCCL_TEST}"
if [[ ${NCCL_TEST} -eq 1 ]]; then
    (srun --mpi="${SLURM_MPI_TYPE:-pmix}" --ntasks="$(( SLURM_JOB_NUM_NODES * DGXNGPU ))" --ntasks-per-node="${DGXNGPU}" \
         --container-name="${_cont_name}" --container-mounts="${_cont_mounts}" all_reduce_perf_mpi -b 100M -e 100M -d half -G 1 -f 2 ) |& tee "${LOGDIR}/${SPREFIX}_nccl.log"

fi
if [ ${RUN_ONLY_NCCL} -gt 0 ]; then
    exit 0
fi

#ssh to nodes for power measurements
NODELIST=$(scontrol show hostnames ${SLURM_JOB_NODELIST})
NODELIST=(${NODELIST[*]})
k=0
if [ -f "$POWERCMDDIR/power_monitor.sh"  ]; then
    ( umask 0002; mkdir -p "${ABSLOGDIR}" )
    for i in "${NODELIST[@]}"
    do
      echo $i $k
	    if [[ "$((k++))" == '8' ]]; then
	      echo "Power log is being collected for 8 nodes only"
	      break
	    fi
      ssh $i 'export NODENAME='"'$i'"';export ABSLOGDIR='"'$ABSLOGDIR'"';export SLURM_JOB_NODELIST='"'$SLURM_JOB_NODELIST'"';export SLURM_JOB_ID='"'$SLURM_JOB_ID'"';POWERCMDDIR='"'$POWERCMDDIR'"';bash ${POWERCMDDIR}/power_monitor.sh' &
#	break
    done
fi

#Set GPU clocks for MaxQ and MinEDP run
if [[ "${SET_MAXQ_CLK}" == "1" ]] || [[ "${SET_MINEDP_CLK}" == "1" ]]; then
	if [[ "${SET_MAXQ_CLK}" == "1" ]]; then
		GPCCLK=${MAXQ_CLK}
	fi
	if [[ "${SET_MINEDP_CLK}" == "1" ]]; then
		GPCCLK=${MINEDP_CLK}
	fi
	for i in "${NODELIST[@]}"
	do
		ssh $i 'export GPCCLK='"'$GPCCLK'"';sudo nvidia-smi -lgc ${GPCCLK}'
	done
fi

if [ "${HANG_MONITOR_TIMEOUT-0}" -gt 0 ]; then
  HANG_MONITOR_EXEC_CMD="
    srun \
      --overlap -l --no-container-mount-home --container-mounts=${_cont_mounts} \
      --container-name=${_cont_name} --container-workdir=${WORK_DIR} --ntasks=${SLURM_JOB_NUM_NODES} \
      bash scripts/tracebacks/dump_tracebacks_node.sh"

    if [ "${ATTEMPT_CUDA_GDB_CORE_DUMP}" == "1" ]; then
      echo "Enabling user triggered CPU core dump"
      export CUDA_ENABLE_LIGHTWEIGHT_COREDUMP=1
      export CUDA_ENABLE_USER_TRIGGERED_COREDUMP=1

      export CUDA_COREDUMP_PIPE_DIR="/workspace/cuda-gdb-pipes/${DATESTAMP}"
      export CUDA_COREDUMP_BASEDIR="/results/coredumps/${DATESTAMP}"
      export CUDA_COREDUMP_HOSTDIR="${LOGDIR}/coredumps/${DATESTAMP}"
      export CUDA_COREDUMP_PIPE="${CUDA_COREDUMP_PIPE_DIR}/corepipe.cuda.%h.%p"
      export CUDA_COREDUMP_FILE="${CUDA_COREDUMP_BASEDIR}/core_%h_%p.nvcudmp"

      mkdir -p "${CUDA_COREDUMP_HOSTDIR}"
      mkdir -p "${CUDA_COREDUMP_PIPE_DIR}"

      HANG_MONITOR_EXEC_CMD+=";
        srun \
          --overlap -l --no-container-mount-home --container-mounts=${_cont_mounts} \
          --container-name=${_cont_name} --container-workdir=${WORK_DIR} --ntasks=${SLURM_JOB_NUM_NODES} \
          bash scripts/tracebacks/dump_core_node.sh"
    fi

  source "${RUNSUB_DIR}/scripts/tracebacks/hang_monitor.sh"
  ( TRACEBACKS_ID=$DATESTAMP hang_monitor &> "${LOGDIR}/${SPREFIX}_hang_monitor.log" ) &
  hang_monitor_pid=$!
else
  hang_monitor_pid=
fi

env > ${LOG_FILE_BASE}_env.log

# Run experiments
for _experiment_index in $(seq -w 1 "${NEXP}"); do
    (
        echo "Beginning trial ${_experiment_index} of ${NEXP}"
	echo ":::DLPAL ${CONT} ${SLURM_JOB_ID} ${SLURM_JOB_NUM_NODES} ${SLURM_JOB_NODELIST} ${MLPERF_CLUSTER_NAME} ${DGXSYSTEM}"

	# TODO: ideally we should exchange seeds in the application (right before `build_train_valid_test_datasets`)
  # For now we can do this upfront by setting seeds here
  export SEED=$(($SEED_BASE - 1 + 10#$_experiment_index))  # `10#` makes sure we interpret number in base 10

        # Clear caches
        if [ "${CLEAR_CACHES}" -eq 1 ]; then
            srun --ntasks="${SLURM_JOB_NUM_NODES}" bash -c "echo -n 'Clearing cache on ' && hostname && sync && ${DROPCACHE_CMD}"
            srun --ntasks="${SLURM_JOB_NUM_NODES}" --container-name="${_cont_name}" python -c "
from mlperf_logger import mllogger
mllogger.event(key=mllogger.constants.CACHE_CLEAR, value=True)"
        fi

        # Run experiment
	srun -l --mpi="${SLURM_MPI_TYPE:-pmix}" --no-container-mount-home                                              \
	--ntasks="$(( SLURM_JOB_NUM_NODES * DGXNGPU ))" --ntasks-per-node="${DGXNGPU}" \
	--container-name="${_cont_name}" --container-mounts="${_cont_mounts}"                 \
	--container-workdir=${WORK_DIR} ${SRUN_EXTRA_ARGS} "slurm2pytorch" "./run_and_time.sh"

    ) |& tee "${LOG_FILE_BASE}_${_experiment_index}.log"
    # compliance checker
    if [ "${CHECK_COMPLIANCE}" -eq 1 ]; then
      srun --ntasks=1 --nodes=1 --container-name="${_cont_name}" \
           --container-mounts="$(realpath ${LOGDIR}):/results"   \
           --container-workdir="/results"                        \
           python3 -m mlperf_logging.compliance_checker --usage training \
           --ruleset "${MLPERF_RULESET}"                                 \
           --log_output "/results/compliance_${DATESTAMP}.out"           \
           "/results/${LOGBASE}_${_experiment_index}.log" \
    || true
    fi

    if [ "${POSTPROCESS_CUDA_GDB_CORE_DUMP}" -eq 1 ] \
        && [ "${HANG_MONITOR_TIMEOUT-0}" -gt 0 ] \
        && [ "${ATTEMPT_CUDA_GDB_CORE_DUMP}" == "1" ] \
        && [ -n "$(ls -A ${CUDA_COREDUMP_HOSTDIR}/*.nvcudmp)" ]; then
      echo "Postprocessing CUDA core dumps"
      srun --ntasks=1 --nodes=1 --container-name="${_cont_name}" \
           --container-mounts="$(realpath ${LOGDIR}):/results"   \
           --container-workdir="${WORK_DIR}"                        \
           bash scripts/tracebacks/postprocess_core_dumps.sh     \
    || true
    fi

    if [ "${JET:-0}" -eq 1 ]; then
      JET_CREATE="${JET_CREATE:-} --data workload.spec.nodes=${DGXNNODES} --data workload.spec.name=${MODEL_NAME}_${MODEL_FRAMEWORK}_${DGXSYSTEM} --data workload.key=${MODEL_NAME}_${MODEL_FRAMEWORK}_${DGXSYSTEM} --mllogger "
      srun -N1 -n1 --container-name="${_cont_name}" --container-mounts="${_cont_mounts}" bash -c "${JET_CREATE} /results/${LOGBASE}_${_experiment_index}.log && ${JET_UPLOAD}"
    fi

done

if [ -n ${hang_monitor_pid} ] && ps -p $hang_monitor_pid > /dev/null; then
  pkill -P $hang_monitor_pid
fi

# Cleanup: performed by cleanup_preload_lustre (see above) on EXIT trap
