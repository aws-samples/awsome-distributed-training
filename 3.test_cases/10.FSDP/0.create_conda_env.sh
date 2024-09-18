#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

conda create -y -p ./pt_fsdp python=3.11

source activate ./pt_fsdp/

# Set true to install AWS Pytorch. see https://aws-pytorch-doc.com/
use_aws_pytorch=true

if $use_aws_pytorch; then
    conda install -y pytorch=2.3.0 pytorch-cuda=12.1 aws-ofi-nccl torchvision torchaudio transformers datasets fsspec=2023.9.2 --strict-channel-priority --override-channels -c https://aws-ml-conda.s3.us-west-2.amazonaws.com -c nvidia -c conda-forge
else
    conda install -y pytorch=2.4.1 torchvision torchaudio transformers datasets fsspec=2023.9.2 pytorch-cuda=12.1 -c pytorch -c nvidia
    conda install -y aws-ofi-nccl=1.9.1 -c https://aws-ml-conda.s3.us-west-2.amazonaws.com -c conda-forge
fi

# Create checkpoint dir
mkdir checkpoints
