#!/bin/bash

# Define the container name and image version
CONTAINER_NAME="dcgm-exporter"
DCGM_EXPORTER_VERSION=3.3.8-3.6.0-ubuntu22.04
IMAGE="nvcr.io/nvidia/k8s/dcgm-exporter:${DCGM_EXPORTER_VERSION}"

# Maximum number of retries
MAX_RETRIES=5
RETRY_DELAY=5  # Initial delay in seconds

# Check if the container exists and is running
if docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME is already running."
    exit 0
else
    echo "Container $CONTAINER_NAME is not running or does not exist..."
    echo "Checking if $CONTAINER_NAME container exists but is not running. If yes, removing it..."
    docker rm -f $CONTAINER_NAME && echo "Container $CONTAINER_NAME has been removed."
    echo "Proceeding with script..."
fi

# Check for GPU, then proceed with script
if nvidia-smi > /dev/null 2>&1; then
    echo "NVIDIA GPU found. Proceeding with script..."

    # Get the instance-type from EC2 instance metadata
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)

    echo "Instance Type is recognized as $INSTANCE_TYPE, setting DCGM_EXPORTER_VERSION to $DCGM_EXPORTER_VERSION"

    # Retry logic for pulling the image
    attempt=0
    while [ $attempt -lt $MAX_RETRIES ]; do
        echo "Attempting to pull image ($attempt/$MAX_RETRIES)..."
        if sudo docker pull "$IMAGE"; then
            echo "Successfully pulled image."
            break
        else
            attempt=$((attempt + 1))
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "Pull failed. Retrying in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
                RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
            else
                echo "Failed to pull Docker image after $MAX_RETRIES attempts. Exiting..."
                exit 1
            fi
        fi
    done

    # Run the DCGM Exporter Docker container
    if sudo docker run -d --restart always \
        --name $CONTAINER_NAME \
        --gpus all \
        --net host \
        --cap-add SYS_ADMIN \
        $IMAGE \
        -f /etc/dcgm-exporter/dcp-metrics-included.csv; then
        echo "Running DCGM exporter in a Docker container on port 9400..."
    else
        echo "Failed to run DCGM Exporter Docker container"
        exit 1
    fi
else
    echo "NVIDIA GPU not found. DCGM Exporter was not installed. If this is a controller node, you can safely ignore this warning. Exiting gracefully..."
    exit 0
fi
