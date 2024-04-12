#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

conda create -y -p ./pt_torchtune python=3.10

source activate ./pt_torchtune/

# Install AWS Pytorch, see https://aws-pytorch-doc.com/
# conda install -y pytorch=2.2.0 torchvision torchaudio torchtriton=2.2.0 pytorch-cuda=12.1 transformers datasets --strict-channel-priority --override-channels -c https://aws-ml-conda.s3.us-west-2.amazonaws.com -c nvidia -c conda-forge
conda install -y pytorch torchvision torchaudio pytorch-cuda=12.1 transformers datasets -c pytorch -c nvidia

git clone https://github.com/pytorch/torchtune.git
pip install -e ./torchtune

# Create checkpoint dir
mkdir checkpoints
