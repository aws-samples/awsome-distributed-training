#!/bin/bash

# Define variables
REPO_DIR="awsome-distributed-training"
REPO_URL="https://github.com/aws-samples/awsome-distributed-training.git"

# Check if the repository directory exists
if [ -d "$REPO_DIR" ]; then
    echo "Repository already exists, skipping cloning."
else
    # Clone the repository
    git clone --depth=1 "$REPO_URL" || { echo "Failed to clone the repository"; exit 1; }
fi

# Change directory to the desired location
cd "$REPO_DIR/4.validation_and_observability/3.efa-node-exporter" || { echo "Failed to change directory"; exit 1; }

# Build the Docker image explicitly
sudo docker build -t node_exporter_efa:latest . || { echo "Failed to build Docker image"; exit 1; }

# Run the Docker container with appropriate configurations
sudo docker run -d --restart always \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  node_exporter_efa:latest \
  --path.rootfs=/host && { echo "Successfully started EFA Node Exporter on node"; exit 0; } || { echo "Failed to run Docker container"; exit 1; }
