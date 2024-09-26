#!/bin/bash

# Define the container name
CONTAINER_NAME="dcgm-exporter"

# Check if the container exists and is running
if docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME is already running."
else
    echo "Container $CONTAINER_NAME is not running or does not exist..."
    echo "Checking if $CONTAINER_NAME container exists but is not running. If yes, removing it..."
    docker rm -f $CONTAINER_NAME && echo "Container $CONTAINER_NAME has been removed."

    # Check for GPU, then proceed with script
    if nvidia-smi > /dev/null 2>&1; then
        echo "NVIDIA GPU found. Proceeding with script..."

        # Get the instance-type from EC2 instance metadata
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
        INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)
       
        DCGM_EXPORTER_VERSION=3.3.8-3.6.0-ubuntu22.04

        echo "Instance Type is recognized as $INSTANCE_TYPE, setting DCGM_EXPORTER_VERSION to $DCGM_EXPORTER_VERSION"

        # Run the DCGM Exporter Docker container
        sudo docker run -d --restart always \
        --name $CONTAINER_NAME \
        --gpus all \
        --net host \
        --cap-add SYS_ADMIN \
        nvcr.io/nvidia/k8s/dcgm-exporter:${DCGM_EXPORTER_VERSION} \
        -f /etc/dcgm-exporter/dcp-metrics-included.csv || { echo "Failed to run DCGM Exporter Docker container"; exit 1; }

        echo "Running DCGM exporter in a Docker container on port 9400..."
    else
        echo "NVIDIA GPU not found. DCGM Exporter was not installed. If this is a controller node, you can safely ignore this warning. Exiting gracefully..."
        exit 0
    fi
fi