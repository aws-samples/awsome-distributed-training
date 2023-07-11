#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Based on https://github.com/NVIDIA/NeMo-Megatron-Launcher/tree/23.03#5111-slurm

set -exuo pipefail

srun -N 1 \
    --container-mounts=/admin/ubuntu/sample-slurm-jobs/nemo-launcher-23.03:/workspace/mount_dir \
    --container-image=/admin/ubuntu/aws-nemo-megatron_23.03-py3.sqsh \
    bash -c "cp -a /opt/NeMo-Megatron-Launcher/launcher_scripts /opt/NeMo-Megatron-Launcher/auto_configurator /opt/FasterTransformer /workspace/mount_dir/"

cd /admin/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/
python3 -m venv .venv
source /admin/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/.venv/bin/activate
curl -LO https://raw.githubusercontent.com/NVIDIA/NeMo-Megatron-Launcher/23.03/requirements.txt
pip3 install -r requirements.txt
