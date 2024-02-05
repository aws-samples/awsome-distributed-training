#!/bin/bash

# Check if Nvidia GPU is present
if nvidia-smi; then
    echo "NVIDIA GPU found. Proceeding with script..."
    # Set DCGM Exporter version
    DCGM_EXPORTER_VERSION=2.1.4-2.3.1

    # Run the DCGM Exporter Docker container
    sudo docker run -d --rm \
       --gpus all \
       --net host \
       --cap-add SYS_ADMIN \
       nvcr.io/nvidia/k8s/dcgm-exporter:${DCGM_EXPORTER_VERSION}-ubuntu20.04 \
       -f /etc/dcgm-exporter/dcp-metrics-included.csv || { echo "Failed to run DCGM Exporter Docker container"; exit 1; }

    echo "Running DCGM exporter in a Docker container on port 9400..."
else
    echo "NVIDIA GPU not found. DCGM Exporter was not installed. If this is controller node, you can safelly ignore this warning. Exiting gracefully..."
    exit 0
fi