#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Define the container name
CONTAINER_NAME="headnode-exporter"

# Check if the container exists and is running
if docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME is already running."
else
    echo "Container $CONTAINER_NAME is not running or does not exist..."
    echo "Checking if $CONTAINER_NAME container exists but is not running. If yes, removing it..."
    docker rm -f $CONTAINER_NAME && echo "Container $CONTAINER_NAME has been removed."
     echo "Proceeding with script..."

  # Run the Docker container with appropriate configurations
  sudo docker run -d --restart always \
    --name=$CONTAINER_NAME \
    --net="host" \
    --pid="host" \
    -v "/:/host:ro,rslave" \
    public.ecr.aws/bitnami/node-exporter:latest \
    --path.rootfs=/host && { echo "Successfully started Node Exporter on node"; exit 0; } || { echo "Failed to run Docker container"; exit 1; }
fi