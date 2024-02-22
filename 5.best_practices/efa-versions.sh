#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Fetch software versions related to EFA.
# Currently only tested on Ubuntu 20.04

# EFA Version
cat /opt/amazon/efa_installed_packages | grep "EFA installer version:"

# NCCL Version
sudo apt install mlocate
locate nccl| grep "libnccl.so" | tail -n1 | sed -r 's/^.*\.so\.//'

# libfabric Version
fi_info --version | grep "libfabric:"

# NCCL OFI Version
strings /opt/aws-ofi-nccl/lib/libnccl-net.so | grep Initializing

# CUDA Driver
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1

# CUDA Version
nvcc --version | grep "release"