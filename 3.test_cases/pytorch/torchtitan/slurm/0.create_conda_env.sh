#!/bin/bash

# Download and install Miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
bash miniconda.sh -b -p ./miniconda3
rm miniconda.sh

# Initialize conda
source ./miniconda3/bin/activate

# Create a new conda environment
conda create -y -p ./pt_torchtitan python=3.11

# Activate the environment
source activate ./pt_torchtitan/

# Clone and install torchtitan
git clone https://github.com/pytorch/torchtitan
cd torchtitan
pip install -r requirements.txt
pip3 install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu124 --force-reinstall
pip install --pre torchao --index-url https://download.pytorch.org/whl/nightly/cu124
pip install -e .
