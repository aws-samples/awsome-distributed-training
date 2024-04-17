#!/bin/bash

# must be run a sudo

set -x
set -e

# FSx Lustre Endpoints
FSX_DNS_NAME="$1"
FSX_MOUNTNAME="$2"
MOUNT_POINT="$3"

is_mounted() {
  mountpoint -q "$1"
  return $?
}

check_already_mounted() {
  # Check if FSx is already mounted to $MOUNT_POINT
  if is_mounted $MOUNT_POINT; then
    if grep -qs "$FSX_MOUNTNAME $MOUNT_POINT lustre" /proc/mounts; then
      echo "FSx Lustre already mounted to $MOUNT_POINT. Exiting."
      exit 0
    else
      echo "$MOUNT_POINT is mounted, but not to mountname: $FSX_MOUNTNAME from provisioning_parameters.json. Exiting."
      exit 1
    fi
  fi
}

is_fsx_reachable() {
  if lctl ping "$FSX_DNS_NAME"; then
    echo "FSx is reachable"
  else
    echo "FSx is not reachable, Trying to mount system anyway"
  fi
}

add_to_fstab() {
  # Add FSx to /etc/fstab
  echo "$FSX_DNS_NAME@tcp:/$FSX_MOUNTNAME $MOUNT_POINT lustre defaults,noatime,flock,_netdev 0 0" | tee -a /etc/fstab  
}

mount_fs() {
  if [[ ! -d $MOUNT_POINT ]]; then
    mkdir -p $MOUNT_POINT
    chmod 644 $MOUNT_POINT
  fi

  if mount -t lustre -o noatime,flock "$FSX_DNS_NAME"@tcp:/"$FSX_MOUNTNAME" "$MOUNT_POINT"; then
    if ! is_mounted $MOUNT_POINT ;then
      echo "Mounting FSx to $MOUNT_POINT directory successful, but mountpoint was not detected. Exiting."
      exit 1
    fi
  else
    echo "FAILED to mount, FSX to $MOUNT_POINT directory. Exiting."
    exit 1
  fi
}


load_lnet_modules() {
  modprobe -v lnet
}

# create a systemd service to check mount periodically and remount FSx if necessary
# To stop the service, run: 
# `systemctl stop check_mount.service`
# To disable the service, run:
# `systemctl disable check_mount.service`
install_remount_service() {
  
  if [[ ! -d /opt/ml/scripts ]]; then
    mkdir -p /opt/ml/scripts
    chmod 644 /opt/ml/scripts
    echo "Created dir /opt/ml/scripts"
  fi

  CHECK_MOUNT_FILE=/opt/ml/scripts/check_mount_$FSX_MOUNTNAME.sh

  cat > $CHECK_MOUNT_FILE << EOF
#!/bin/bash
MOUNT_POINT=$MOUNT_POINT
if ! grep -qs "$MOUNT_POINT" /proc/mounts; then
  mount -t lustre -o noatime,flock "$FSX_DNS_NAME"@tcp:/"$FSX_MOUNTNAME" "$MOUNT_POINT"
  echo "Mounted FSx to $MOUNT_POINT"
else
  echo "FSx Lustre already mounted to $MOUNT_POINT. Stopping services check_fsx_mount_$FSX_MOUNTNAME.timer and check_fsx_mount_$FSX_MOUNTNAME.service"
  systemctl stop check_fsx_mount_$FSX_MOUNTNAME.timer
fi
EOF

  chmod +x $CHECK_MOUNT_FILE

  cat > /etc/systemd/system/check_fsx_mount_$FSX_MOUNTNAME.service << EOF
[Unit]
Description=Check and remount FSx Lustre filesystems if necessary

[Service]
ExecStart=$CHECK_MOUNT_FILE
EOF

  cat > /etc/systemd/system/check_fsx_mount_$FSX_MOUNTNAME.timer << EOF
[Unit]
Description=Run check_fsx_mount_$FSX_MOUNTNAME.service every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now check_fsx_mount_$FSX_MOUNTNAME.timer
}

main() {
  echo "Mount_fsx called fsx_dns_name: $FSX_DNS_NAME, fsx_mountname: $FSX_MOUNTNAME"
  echo "Using mount_point: $MOUNT_POINT"
  load_lnet_modules
  check_already_mounted
  is_fsx_reachable
  add_to_fstab
  mount_fs
  install_remount_service
  echo "FSx Lustre mounted successfully to $MOUNT_POINT"
}

main "$@"

