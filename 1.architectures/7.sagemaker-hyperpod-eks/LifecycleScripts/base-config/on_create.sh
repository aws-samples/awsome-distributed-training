#!/bin/bash

set -ex

LOG_FILE="/var/log/provision/provisioning.log"
mkdir -p "/var/log/provision"
touch $LOG_FILE

# Function to log messages
logger() {
  echo "$@" | tee -a $LOG_FILE
}

logger "[start] on_create.sh"

if [[ $(mount | grep /opt/sagemaker) ]]; then
  logger "Found secondary EBS volume. Setting containerd data root to /opt/sagemaker/containerd/data-root"
  sed -i -e "/^[# ]*root\s*=/c\root = \"/opt/sagemaker/containerd/data-root\"" /etc/eks/containerd/containerd-config.toml
fi

logger "no more steps to run"
logger "[stop] on_create.sh"
