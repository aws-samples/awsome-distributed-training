#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

conda create -y -p ./pt_cpu python=3.10 --strict-channel-priority --override-channels -c https://aws-ml-conda.s3.us-west-2.amazonaws.com -c nvidia -c conda-forge

source activate ./pt_cpu/

conda install -y pytorch=2.0.1  --strict-channel-priority --override-channels -c https://aws-ml-conda.s3.us-west-2.amazonaws.com -c nvidia -c conda-forge

rm Miniconda3-latest-Linux-x86_64.sh*