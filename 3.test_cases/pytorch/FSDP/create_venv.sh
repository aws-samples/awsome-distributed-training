#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

PYTHON_VERSION=$(python3 --version | awk '{print $2}' | awk -F'.' '{print $1"."$2}')
sudo apt install -y python$PYTHON_VERSION-venv

# Create and actiate Python virtual environment
python3 -m venv env
source ./env/bin/activate

pip install transformers==4.50.3 datasets fsspec==2023.9.2 python-etcd numpy==1.*
pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu124

# Create checkpoint dir
mkdir checkpoints
