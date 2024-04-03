#!/bin/bash

# Clone the repository
git clone https://github.com/aws-samples/awsome-distributed-training.git || { echo "Failed to clone the repository"; exit 1; }
# Change directory to the desired location
cd awsome-distributed-training/4.validation_and_observability/3.efa-node-exporter || { echo "Failed to change directory"; exit 1; }

# Build the Docker image explicitly
sudo docker build -t node_exporter_efa:latest . || { echo "Failed to build Docker image"; exit 1; }

# Run the Docker container with appropriate configurations
sudo docker run -d --restart always\
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  node_exporter_efa:latest \
  --path.rootfs=/host && { echo "Successfully started EFA Node Exporter on node"; exit 0; } || { echo "Failed to run Docker container"; exit 1; }

