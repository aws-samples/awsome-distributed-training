#!/usr/bin/env bash
set -ex

# Check if Miniconda installer exists locally
if [ ! -f Miniconda3-latest-Linux-x86_64.sh ]; then
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
fi
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

# Initialize conda
source ./miniconda3/etc/profile.d/conda.sh

# Create environment with just Python first
conda create -y -p ./pt_fsdp python=3.11

# Activate the environment
conda activate ./pt_fsdp

# Install packages one at a time to minimize memory usage
echo "Installing PyTorch core..."
CONDA_OVERRIDE_CUDA="12.1" conda install -y pytorch=2.4.1 -c pytorch -c nvidia

echo "Installing torchvision..."
conda install -y torchvision -c pytorch -c nvidia

echo "Installing torchaudio..."
conda install -y torchaudio -c pytorch -c nvidia

echo "Installing fsspec..."
conda install -y fsspec=2023.9.2 -c conda-forge

echo "Installing numpy..."
conda install -y "numpy=1.*" -c conda-forge

# Use pip for remaining packages (often uses less memory than conda)
echo "Installing transformers..."
pip install --no-cache-dir transformers

echo "Installing datasets..."
pip install --no-cache-dir datasets

# Verify installation
python3 -c "import torch; print(torch.__version__)"
which python
which torchrun || python -m torch.distributed.run --help

# Create checkpoint dir
mkdir -p checkpoints
