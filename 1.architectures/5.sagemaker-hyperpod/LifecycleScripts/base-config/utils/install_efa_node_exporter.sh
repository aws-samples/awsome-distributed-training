#!/bin/bash

if nvidia-smi; then
    echo "NVIDIA GPU found. Proceeding with script..."

    # Get the instance-type from EC2 instance metadata
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)

    # Set DCGM-Exporter-Version, for g5s, use older version (https://github.com/NVIDIA/dcgm-exporter/issues/319)
    if [[ $INSTANCE_TYPE == *"g5"* ]]; then
        echo "Instance Type is recognized as $INSTANCE_TYPE setting DCGM_EXPORTER_VERSION to 2.1.4-2.3.1-ubuntu20.04"
        DCGM_EXPORTER_VERSION=2.1.4-2.3.1-ubuntu20.04
    else
        echo "Instance Type is recognized as $INSTANCE_TYPE, setting DCGM_EXPORTER_VERSION to 3.3.5-3.4.0-ubuntu22.04"
        DCGM_EXPORTER_VERSION=3.3.5-3.4.1-ubuntu22.04
    fi
    echo "DCGM_EXPORTER_VERSION = $DCGM_EXPORTER_VERSION"

    # Run the DCGM Exporter Docker container
    sudo docker run -d --restart always \
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
