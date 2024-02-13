#!/usr/bin/env bash
set -ex

# Create checkpoint directry
mkdir -p "${BASE_DIR}/checkpoints"

# TRAINING_CONFIG example paxml.tasks.lm.params.lm_cloud.LmCloudSpmd2B
python3.10 -m paxml.main  \
  --job_log_dir="${BASE_DIR}/LOG_DIR" \
  --fdl_config=${TRAINING_CONFIG} \
  $JAX_FLAGS \
  --multiprocess_gpu=true \
  --server_addr=${LEAD_NODE}:12345 \
  --num_hosts=${OMPI_COMM_WORLD_SIZE} \
  --host_idx=${OMPI_COMM_WORLD_RANK} \
  --alsologtostderr
