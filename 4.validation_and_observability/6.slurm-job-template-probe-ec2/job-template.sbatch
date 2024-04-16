#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SBATCH --nodes=2           # number of nodes to use

set -exuo pipefail


################################################################################
## Preamble
################################################################################
# Helper function to query instance topology
lstopo_ec2() {
    local INSTANCE_IDS=( $(srun cat /sys/devices/virtual/dmi/id/board_asset_tag) )
    aws ec2 describe-instance-topology --instance-ids "${INSTANCE_IDS[@]}"
}

# Are SLURM_NNODES on the same network spine?
validate_ec2_same_spine() {
    local TOPO_JSON="$(lstopo_ec2)"
    echo "${TOPO_JSON}"

    local UNIQ_NN=$(echo "$TOPO_JSON" | grep '^  *"nn\-.................\"' | sort -n | uniq -c | wc -l)
    echo Expected 3 nn ids, got $UNIQ_NN nn ids
    [[ $UNIQ_NN -eq 3 ]] || echo WARNING: ec2 instances on different network spine...
}
validate_ec2_same_spine

# Track instance ids, later on to view their CloudWatch metrics.
srun -l bash -c "echo \"hostname <=> instance_id mapping: \$(hostname) <=> \$(cat /sys/devices/virtual/dmi/id/board_asset_tag)\""

# Track per-instance cumulative Lustre statistics. In this example, we only show the write_bytes.
srun -l bash -c "echo BEFORE: \$(hostname) \$(sudo lctl get_param llite.*.stats | grep write_bytes)" || true

env


################################################################################
## Actual scripts. Below example runs /usr/bin/hostname on all allocated nodes.
################################################################################
BEGIN_TRAINING=$(date)
SECONDS=0
srun -l /usr/bin/hostname
END_TRAINING=$(date)
echo "BEGIN_TRAINING: ${BEGIN_TRAINING}"
echo "END_TRAINING  : ${END_TRAINING}"
echo "Elapsed: $(($SECONDS / 60))min $(($SECONDS % 60))sec"


################################################################################
## Postamble
################################################################################
# Track per-instance cumulative Lustre statistics. In this exmaple, we only show the write_bytes.
srun -l bash -c "echo AFTER: \$(hostname) \$(sudo lctl get_param llite.*.stats | grep write_bytes)" || true
