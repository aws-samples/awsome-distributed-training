#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Based on https://github.com/NVIDIA/NeMo-Megatron-Launcher/tree/23.05#5111-slurm

set -exuo pipefail

NEMO_LAUNCHER_VERSION=23.07
srun -N 1 \
    --container-mounts=/fsx/ubuntu/sample-slurm-jobs/nemo-launcher-$NEMO_LAUNCHER_VERSION:/workspace/mount_dir \
    --container-image=/fsx/ubuntu/aws-nemo-megatron_$NEMO_LAUNCHER_VERSION-py3.sqsh \
    bash -c "cp -a /opt/NeMo-Megatron-Launcher/launcher_scripts /opt/NeMo-Megatron-Launcher/auto_configurator /opt/FasterTransformer /workspace/mount_dir/"

cd /fsx/ubuntu/sample-slurm-jobs/nemo-launcher-$NEMO_LAUNCHER_VERSION/
/usr/bin/python3 -m venv .venv
source /fsx/ubuntu/sample-slurm-jobs/nemo-launcher-$NEMO_LAUNCHER_VERSION/.venv/bin/activate
curl -LO https://raw.githubusercontent.com/NVIDIA/NeMo-Megatron-Launcher/$NEMO_LAUNCHER_VERSION/requirements.txt
pip3 install --upgrade pip setuptools
pip3 install -r requirements.txt
