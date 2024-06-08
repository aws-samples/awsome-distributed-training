#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0


# Run the Docker container with appropriate configurations
sudo docker run -d --restart always \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  public.ecr.aws/bitnami/node-exporter:latest \
  --path.rootfs=/host && { echo "Successfully started Node Exporter on node"; exit 0; } || { echo "Failed to run Docker container"; exit 1; }
