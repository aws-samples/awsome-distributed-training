#!/bin/bash
# Runs inside Pyxis once per node. NVRx owns the finite worker restart loop.
set -euo pipefail
export TMPDIR=${NVRX_LOCAL_TMPDIR:?}
((${#TMPDIR} <= 65)) || { printf 'Use a short node-local NVRX_LOCAL_TMPDIR (<=65 characters)\n' >&2; exit 1; }
mkdir -p "$TMPDIR"
# Logs live beside, not inside, the initially nonexistent training directory.
exec ft_launcher \
    --nnodes="$SLURM_JOB_NUM_NODES" --nproc-per-node="$NVRX_GPUS_PER_NODE" \
    --rdzv-id="$SLURM_JOB_ID" --rdzv-endpoint="$NVRX_RDZV_HOST:$NVRX_RDZV_PORT" \
    --rdzv-conf=join_timeout=120,store_connect_wait_seconds=60 \
    --max-restarts="$NVRX_MAX_RESTARTS" \
    --ft-rank-section-timeouts="$NVRX_SECTION_TIMEOUTS" \
    --ft-rank-out-of-section-timeout=60 \
    --ft-checkpoint-iteration-file="$NVRX_RUN_DIR/latest_checkpointed_iteration.txt" \
    --log-dir="${NVRX_RUN_DIR}-logs/$SLURM_JOB_ID/node-$SLURM_NODEID" --tee=3 \
    /app/src/train_slurm.py --run-dir="$NVRX_RUN_DIR" "$@"
