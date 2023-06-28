#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Define variables
NUM_CONNECTIONS=16
NUM_FILES_PARALLEL_DOWNLOAD=16
URL_LIST_FILE_NAME="./url_list.txt"
OUTPUT_DIR=""

# Check for output directory argument
if [ $# -eq 1 ]
then
  OUTPUT_DIR="$1"
else
  echo "OUTPUT_DIR is not defined. So using default ./"
  OUTPUT_DIR="./"
  exit 1
fi

# Install aria2 if not already installed
if ! command -v aria2c &> /dev/null
then
  echo "aria2c not found. Installing..."
  sudo apt update
  sudo apt install -y aria2
fi

# Download PILE dataset with aria2c
aria2c -x${NUM_CONNECTIONS} -s${NUM_FILES_PARALLEL_DOWNLOAD} -i ${URL_LIST_FILE_NAME} -d ${OUTPUT_DIR}

echo "PILE dataset download complete!"
