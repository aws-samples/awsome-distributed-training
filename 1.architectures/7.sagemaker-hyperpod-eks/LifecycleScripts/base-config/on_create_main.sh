#!/bin/bash

set -ex

# Configuration: Choose disk for containerd and kubelet
# Options: "/opt/sagemaker" or "/opt/dlami/nvme"

DISK_FOR_CONTAINERD_KUBELET="/opt/sagemaker"
#DISK_FOR_CONTAINERD_KUBELET="/opt/dlami/nvme"

logger() {
  echo "$@"
}

logger "[start] on_create_main.sh"
logger "Disk for containerd and kubelet: $DISK_FOR_CONTAINERD_KUBELET"

# Wait for disk to be mounted (max 60s)
for i in {1..12}; do
  if mount | grep -q "$DISK_FOR_CONTAINERD_KUBELET"; then
    logger "$DISK_FOR_CONTAINERD_KUBELET is mounted"
    break
  else
    logger "Waiting for $DISK_FOR_CONTAINERD_KUBELET to be mounted..."
    sleep 5
  fi
done


# Dump the status of containerd.service and kubelet.service
logger "Dumping the status of containerd.service and kubelet.service"
systemctl status containerd.service --no-pager || true
systemctl status kubelet.service --no-pager || true


if mount | grep -q "$DISK_FOR_CONTAINERD_KUBELET"; then
  logger "Setting containerd data root to $DISK_FOR_CONTAINERD_KUBELET/containerd/data-root"

  # Detect OS version reliably
  source /etc/os-release
  os_version="$VERSION_ID"
  logger "Detected OS version: $os_version"

  if [[ "$os_version" == "2" ]]; then
    # Amazon Linux 2 logic
    CONFIG_FILE="/etc/eks/containerd/containerd-config.toml"
    if [[ -f "$CONFIG_FILE" ]]; then
      logger "Amazon Linux 2 detected. Modifying $CONFIG_FILE using sed"
      sed -i -e "/^[# ]*root\s*=/c\root = \"$DISK_FOR_CONTAINERD_KUBELET/containerd/data-root\"" "$CONFIG_FILE"
    else
      logger "Amazon Linux 2 detected, but $CONFIG_FILE not found!"
    fi

  elif [[ "$os_version" == "2023" ]]; then
    # Amazon Linux 2023 logic (systemd override with custom config)
    logger "Amazon Linux 2023 detected. Creating custom containerd config and systemd override"

    # Clean up old containerd data to avoid AL2->AL23 compatibility issues
    if [[ -d "$DISK_FOR_CONTAINERD_KUBELET/containerd/data-root" ]]; then
      logger "Removing existing containerd data-root to prevent AL2/AL23 incompatibility"
      rm -rf "$DISK_FOR_CONTAINERD_KUBELET/containerd/data-root"
    fi

    # Create custom containerd config directory
    mkdir -p "$DISK_FOR_CONTAINERD_KUBELET/containerd"

    # Create complete custom containerd config
    cat <<EOF | tee "$DISK_FOR_CONTAINERD_KUBELET/containerd/config.toml"
version = 2
root = "$DISK_FOR_CONTAINERD_KUBELET/containerd/data-root"
state = "/run/containerd"

[grpc]
address = "/run/containerd/containerd.sock"

[plugins."io.containerd.grpc.v1.cri".containerd]
default_runtime_name = "nvidia"
discard_unpacked_layers = true

[plugins."io.containerd.grpc.v1.cri"]
sandbox_image = "localhost/kubernetes/pause"
enable_cdi = true

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
Environment="CONTAINERD_CONFIG=$DISK_FOR_CONTAINERD_KUBELET/containerd/config.toml"
ExecStart=
ExecStart=/usr/bin/containerd --config \$CONTAINERD_CONFIG
EOF

    systemctl daemon-reload

    cp -a /var/lib/containerd "$DISK_FOR_CONTAINERD_KUBELET/containerd/data-root"

  else
    logger "Unsupported OS version: $os_version. Skipping containerd configuration."
  fi

  logger "Creating symbolic link from /var/lib/kubelet to $DISK_FOR_CONTAINERD_KUBELET/kubelet"
  mkdir -p "$DISK_FOR_CONTAINERD_KUBELET/kubelet"
  if [ "$(ls -A /var/lib/kubelet 2>/dev/null)" ]; then
    mv /var/lib/kubelet/* "$DISK_FOR_CONTAINERD_KUBELET/kubelet/"
  else
    logger "/var/lib/kubelet is empty, skipping file move"
  fi
  rmdir /var/lib/kubelet
  ln -s "$DISK_FOR_CONTAINERD_KUBELET/kubelet" /var/lib/

else
  logger "$DISK_FOR_CONTAINERD_KUBELET not mounted. Skipping containerd configuration"
fi

logger "no more steps to run"
logger "[stop] on_create_main.sh"
