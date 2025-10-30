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
    # Amazon Linux 2023 logic (systemd override with custom config)
    logger "Amazon Linux 2023 detected. Creating custom containerd config and systemd override"

    # Clean up old containerd data to avoid AL2->AL23 compatibility issues
    if [[ -d "/opt/sagemaker/containerd/data-root" ]]; then
      logger "Removing existing containerd data-root to prevent AL2/AL23 incompatibility"
      rm -rf /opt/sagemaker/containerd/data-root
    fi

    # Create custom containerd config directory
    mkdir -p /opt/sagemaker/containerd

    # Create complete custom containerd config
    cat <<EOF | tee /opt/sagemaker/containerd/config.toml
version = 2
root = "/opt/sagemaker/containerd/data-root"
state = "/run/containerd"

[grpc]
address = "/run/containerd/containerd.sock"

[plugins."io.containerd.grpc.v1.cri".containerd]
default_runtime_name = "nvidia"
discard_unpacked_layers = true

[plugins."io.containerd.grpc.v1.cri"]
sandbox_image = "localhost/kubernetes/pause"
enable_cdi = false

[plugins."io.containerd.grpc.v1.cri".registry]
config_path = "/etc/containerd/certs.d:/etc/docker/certs.d"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
runtime_type = "io.containerd.runc.v2"
base_runtime_spec = "/etc/containerd/base-runtime-spec.json"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
BinaryName = "/usr/bin/nvidia-container-runtime"
SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri".cni]
bin_dir = "/opt/cni/bin"
conf_dir = "/etc/cni/net.d"
EOF

    # Create systemd override
    mkdir -p /etc/systemd/system/containerd.service.d

    cat <<EOF | tee /etc/systemd/system/containerd.service.d/override.conf
[Service]
Environment="CONTAINERD_CONFIG=/opt/sagemaker/containerd/config.toml"
ExecStart=
ExecStart=/usr/bin/containerd --config \$CONTAINERD_CONFIG
EOF

    systemctl daemon-reload

    cp -a /var/lib/containerd /opt/sagemaker/containerd/data-root

  else
    logger "Unsupported OS version: $os_version. Skipping containerd configuration."
  fi

else
  logger "/opt/sagemaker not mounted. Skipping containerd configuration"
fi

logger "no more steps to run"
logger "[stop] on_create.sh"
