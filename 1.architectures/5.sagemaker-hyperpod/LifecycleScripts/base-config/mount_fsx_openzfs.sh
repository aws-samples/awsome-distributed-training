#!/bin/bash

# must be run as sudo

set -x
set -e

# FSx OpenZFS Endpoints
FSX_OPENZFS_DNS_NAME="$1"
OPENZFS_MOUNT_POINT="$2"

is_mounted() {
  mountpoint -q "$1"
  return $?
}

check_already_mounted() {
  # Check if FSx OpenZFS is already mounted to $OPENZFS_MOUNT_POINT
  if is_mounted $OPENZFS_MOUNT_POINT; then
    if grep -qs "$FSX_OPENZFS_DNS_NAME:/fsx $OPENZFS_MOUNT_POINT nfs" /proc/mounts; then
      echo "FSx OpenZFS already mounted to $OPENZFS_MOUNT_POINT. Exiting."
      exit 0
    else
      echo "$OPENZFS_MOUNT_POINT is mounted, but not to DNS name: $FSX_OPENZFS_DNS_NAME. Exiting."
      exit 1
    fi
  fi
}

install_nfs_client() {
  # Install NFS client based on the OS
  if [ -f /etc/lsb-release ]; then
    # Ubuntu
    apt-get update
    apt-get -y install nfs-common
  elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL
    yum -y install nfs-utils
  fi
}

add_to_fstab() {
  # Add FSx OpenZFS to /etc/fstab
  echo "$FSX_OPENZFS_DNS_NAME:/fsx $OPENZFS_MOUNT_POINT nfs nfsvers=4.2,_netdev 0 0" | tee -a /etc/fstab
}

mount_fs() {
  if [[ ! -d $OPENZFS_MOUNT_POINT ]]; then
    mkdir -p $OPENZFS_MOUNT_POINT
    chmod 755 $OPENZFS_MOUNT_POINT
  fi

  if mount -t nfs -o nfsvers=4.2 "$FSX_OPENZFS_DNS_NAME:/fsx" "$OPENZFS_MOUNT_POINT"; then
    if ! is_mounted $OPENZFS_MOUNT_POINT; then
      echo "Mounting FSx OpenZFS to $OPENZFS_MOUNT_POINT directory successful, but mountpoint was not detected. Exiting."
      exit 1
    fi
  else
    echo "FAILED to mount FSx OpenZFS to $OPENZFS_MOUNT_POINT directory. Exiting."
    exit 1
  fi
}

# create a systemd service to check mount periodically and remount FSx if necessary
install_remount_service() {
  if [[ ! -d /opt/ml/scripts ]]; then
    mkdir -p /opt/ml/scripts
    chmod 755 /opt/ml/scripts
    echo "Created dir /opt/ml/scripts"
  fi

  CHECK_MOUNT_FILE=/opt/ml/scripts/check_mount_openzfs.sh

  cat > $CHECK_MOUNT_FILE << EOF
#!/bin/bash
OPENZFS_MOUNT_POINT=$OPENZFS_MOUNT_POINT
if ! grep -qs "\$OPENZFS_MOUNT_POINT" /proc/mounts; then
  mount -t nfs -o nfsvers=4.2 "$FSX_OPENZFS_DNS_NAME:/fsx" "\$OPENZFS_MOUNT_POINT"
  echo "Mounted FSx OpenZFS to \$OPENZFS_MOUNT_POINT"
else
  echo "FSx OpenZFS already mounted to \$OPENZFS_MOUNT_POINT. Stopping services check_fsx_openzfs_mount.timer and check_fsx_openzfs_mount.service"
  systemctl stop check_fsx_openzfs_mount.timer
fi
EOF

  chmod +x $CHECK_MOUNT_FILE

  cat > /etc/systemd/system/check_fsx_openzfs_mount.service << EOF
[Unit]
Description=Check and remount FSx OpenZFS filesystems if necessary

[Service]
ExecStart=$CHECK_MOUNT_FILE
EOF

  cat > /etc/systemd/system/check_fsx_openzfs_mount.timer << EOF
[Unit]
Description=Run check_fsx_openzfs_mount.service every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now check_fsx_openzfs_mount.timer
}

main() {
  echo "Mount_fsx_openzfs called with fsx_openzfs_dns_name: $FSX_OPENZFS_DNS_NAME"
  echo "Using openzfs_mount_point: $OPENZFS_MOUNT_POINT"
  install_nfs_client
  check_already_mounted
  add_to_fstab
  mount_fs
  install_remount_service
  echo "FSx OpenZFS mounted successfully to $OPENZFS_MOUNT_POINT"
}

main "$@"
