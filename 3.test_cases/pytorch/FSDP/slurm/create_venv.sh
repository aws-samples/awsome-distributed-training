#!/usr/bin/env bash
set -ex

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

PYTHON_VERSION=$(python3 --version | awk '{print $2}' | awk -F'.' '{print $1"."$2}')
sudo apt install -y python$PYTHON_VERSION-venv

# Create and actiate Python virtual environment
python3 -m venv env
source ./env/bin/activate

pip install -r ../src/requirements.txt

# Create checkpoint dir
mkdir checkpoints
