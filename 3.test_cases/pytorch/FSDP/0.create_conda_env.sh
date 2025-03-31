#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Check if Miniconda installer exists locally
if [ ! -f Miniconda3-latest-Linux-x86_64.sh ]; then
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
fi
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

conda create -y -p ./pt_fsdp python=3.11

source activate ./pt_fsdp/

conda install -y pytorch=2.4.1 torchvision torchaudio transformers datasets fsspec=2023.9.2 pytorch-cuda=12.1 "numpy=1.*" -c pytorch -c nvidia

# Create checkpoint dir
mkdir checkpoints
