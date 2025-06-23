#!/bin/bash

# Install PyTorch
pip install torch==2.6.0+cu12

# Install wheel, packaging, and ninja
pip install wheel packaging ninja urllib


# Install flash-attn and deepspeed
# Install flash-attn and deepspeed
pip install https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiTRUE-cp312-cp312-linux_x86_64.whl

pip install deepspeed

# Install requirements from requirements.txt
pip install -r requirements.txt
