#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -ex
# Mamba to be installed in shared FSx
MAMBA_VERSION=23.1.0-1

curl -L -o ./mambaforge.sh https://github.com/conda-forge/miniforge/releases/download/${MAMBA_VERSION}/Mambaforge-${MAMBA_VERSION}-Linux-x86_64.sh
chmod +x ./mambaforge.sh
./mambaforge.sh -b -p ./conda
rm ./mambaforge.sh
./conda/bin/mamba clean -afy

source ./conda/bin/activate

conda create -n smdataparallel python=3.10
conda activate smdataparallel

# Install pytorch and SM data parallelism library
conda install -y pytorch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 pytorch-cuda=11.8 -c pytorch -c nvidia
pip install https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.0.1/cu118/2023-11-07/smdistributed_dataparallel-2.0.2-cp310-cp310-linux_x86_64.whl
pip install -r scripts/requirements.txt
