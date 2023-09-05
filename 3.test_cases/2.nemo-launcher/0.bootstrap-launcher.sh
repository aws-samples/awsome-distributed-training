#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Based on https://github.com/NVIDIA/NeMo-Megatron-Launcher/tree/23.05#5111-slurm

set -exuo pipefail

: "${NEMO_VERSION:=23.07}"
: "${REPO:=aws-nemo-megatron}"
: "${TAG:=$NEMO_VERSION-py3}"
: "${ENROOT_IMAGE:=/apps/${REPO}_${TAG}.sqsh}"
: "${TARGET_PATH:=/fsx/nemo-launcher-$NEMO_VERSION}"   # must be a shared filesystem

srun -N 1 \
    --container-mounts=$TARGET_PATH:/workspace/mount_dir \
    --container-image=$ENROOT_IMAGE \
    bash -c "cp -a /opt/NeMo-Megatron-Launcher/launcher_scripts /opt/NeMo-Megatron-Launcher/auto_configurator /opt/FasterTransformer /workspace/mount_dir/"

cd $TARGET_PATH
/usr/bin/python3.8 -m venv .venv
source $TARGET_PATH/.venv/bin/activate
curl -LO https://raw.githubusercontent.com/NVIDIA/NeMo-Megatron-Launcher/$NEMO_VERSION/requirements.txt
pip3.8 install --upgrade pip setuptools
pip3.8 install -r requirements.txt
