#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

conda create -n pt-nightlies python=3.10

conda activate pt-nightlies

# Install PyTorch Nightly distribution with Cuda 12.1
pip3 install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu121

# Install Diffusers and Transformers
pip3 install diffusers["torch"] transformers

# Install Weights and Biases
pip3 install wandb

# We will install Composer from source. First clone the Repo
git clone https://github.com/mosaicml/composer.git