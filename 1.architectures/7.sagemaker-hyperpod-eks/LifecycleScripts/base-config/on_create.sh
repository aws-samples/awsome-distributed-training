#!/bin/bash

set -ex

LOG_FILE="/var/log/provision/provisioning.log"
mkdir -p "/var/log/provision"
touch "$LOG_FILE"

logger() {
  echo "$@" | tee -a "$LOG_FILE"
}

logger "[start] on_create.sh"

# Wait for /opt/sagemaker to be mounted (max 60s)
for i in {1..12}; do
  if mount | grep -q "/opt/sagemaker"; then
    logger "/opt/sagemaker is mounted"
    break
  else
    logger "Waiting for /opt/sagemaker to be mounted..."
    sleep 5
  fi
done

if mount | grep -q "/opt/sagemaker"; then
  logger "Found secondary EBS volume. Setting containerd data root to /opt/sagemaker/containerd/data-root"

  # Detect OS version reliably
  source /etc/os-release
  os_version="$VERSION_ID"
  logger "Detected OS version: $os_version"

  if [[ "$os_version" == "2" ]]; then
    # Amazon Linux 2 logic
    CONFIG_FILE="/etc/eks/containerd/containerd-config.toml"
    if [[ -f "$CONFIG_FILE" ]]; then
      logger "Amazon Linux 2 detected. Modifying $CONFIG_FILE using sed"
      sed -i -e "/^[# ]*root\s*=/c\root = \"/opt/sagemaker/containerd/data-root\"" "$CONFIG_FILE"
    else
      logger "Amazon Linux 2 detected, but $CONFIG_FILE not found!"
    fi

  elif [[ "$os_version" == "2023" ]]; then
    # Amazon Linux 2023 logic (systemd override)
    logger "Amazon Linux 2023 detected. WARNING: nodeadm will override containerd configuration"
    logger "Current containerd config will be reset by nodeadm to use /var/lib/containerd"
    logger "Manual intervention required post-nodeadm execution to set data-root to /opt/sagemaker/containerd/data-root"
    logger "Consider implementing post-nodeadm hook or alternative solution"

  else
    logger "Unsupported OS version: $os_version. Skipping containerd configuration."
  fi

else
  logger "/opt/sagemaker not mounted. Skipping containerd configuration"
fi

logger "no more steps to run"
logger "[stop] on_create.sh"
