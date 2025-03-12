#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# Install NeMo-Run
pip install git+https://github.com/NVIDIA/NeMo-Run.git@4d056535b5cce475b0536243e2cefcfa3897eee8

# # Install PyTorch
pip install torch==2.6.0
 
# Install Megatron-LM
pip install --no-deps git+https://github.com/NVIDIA/Megatron-LM.git@b5d90de8e7c7fae5f35be89d665f237970540bed

# # Download and install Mamba SSM
wget https://github.com/state-spaces/mamba/releases/download/v2.2.2/mamba_ssm-2.2.2+cu118torch2.0cxx11abiFALSE-cp310-cp310-linux_x86_64.whl  # Adjusted for torch 2.0
pip install mamba_ssm-2.2.2+cu118torch2.0cxx11abiFALSE-cp310-cp310-linux_x86_64.whl
rm mamba_ssm-2.2.2+cu118torch2.0cxx11abiFALSE-cp310-cp310-linux_x86_64.whl

# Install NeMo Toolkit
pip install nemo_toolkit['all']==2.1.0

# Install OpenCC
pip install opencc==1.1.6

# Clone and install NVIDIA Resiliency Extension
pip install git+https://github.com/NVIDIA/nvidia-resiliency-ext.git@292886dce09e24f320b733da1c366bcc4f48548d

echo "Environment setup complete."
