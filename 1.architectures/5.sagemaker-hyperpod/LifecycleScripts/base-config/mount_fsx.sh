#!/bin/bash

#set -x  # Debug output

# FSx Lustre Endpoints
FSX_DNS_NAME="$1"
FSX_MOUNTNAME="$2"
MOUNT_POINT="$3"

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        echo "Script failed, checking logs..."
        sudo dmesg | tail -n 20
        echo "Mount status:"
        mount | grep lustre || true
        echo "LNet status:"
        sudo lctl list_nids || true
    fi
}

trap cleanup EXIT

is_mounted() {
    sudo mountpoint -q "$1"
    return $?
}

check_already_mounted() {
    if is_mounted "$MOUNT_POINT"; then
        if sudo grep -qs "${FSX_DNS_NAME}@tcp:/${FSX_MOUNTNAME}" /proc/mounts; then
            echo "FSx Lustre already mounted to $MOUNT_POINT. Exiting."
            exit 0
        else
            echo "Warning: $MOUNT_POINT is mounted with different filesystem:"
            sudo grep "$MOUNT_POINT" /proc/mounts
            exit 1
        fi
    fi
}

is_fsx_reachable() {
    echo "Checking FSx reachability..."
    if sudo lctl ping "$FSX_DNS_NAME"; then
        echo "FSx is reachable"
        return 0
    else
        echo "FSx is not reachable. Will try mounting anyway."
        return 1
    fi
}

add_to_fstab() {
    echo "Adding mount entry to /etc/fstab..."
    # Backup existing fstab
    sudo cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove any existing entries for this mount point
    sudo sed -i "\|${MOUNT_POINT}|d" /etc/fstab
    
    # Add new entry
    echo "$FSX_DNS_NAME@tcp:/$FSX_MOUNTNAME $MOUNT_POINT lustre defaults,noatime,flock,_netdev 0 0" | sudo tee -a /etc/fstab
}

mount_fs() {
    echo "Preparing to mount FSx..."
    
    if [[ ! -d $MOUNT_POINT ]]; then
        sudo mkdir -p "$MOUNT_POINT" || { echo "Failed to create mount point"; exit 1; }
        sudo chmod 755 "$MOUNT_POINT"
    fi

    echo "Attempting to mount FSx..."
    if sudo mount -t lustre -o noatime,flock "${FSX_DNS_NAME}@tcp:/${FSX_MOUNTNAME}" "$MOUNT_POINT"; then
        if is_mounted "$MOUNT_POINT"; then
            echo "Mount successful:"
            df -h "$MOUNT_POINT"
            return 0
        else
            echo "Error: Mount command succeeded but mountpoint check failed"
            sudo dmesg | tail -n 10
            exit 1
        fi
    else
        echo "Error: Mount failed"
        sudo dmesg | tail -n 10
        exit 1
    fi
}

load_lnet_modules() {
    echo "Loading kernel modules..."
    sudo modprobe lustre || echo "Warning: loading lustre module failed"
    sudo modprobe lnet || { echo "Error: Failed to load LNet module"; exit 1; }
    sudo lctl network up || { echo "Error: Failed to bring up LNet network"; exit 1; }
}

install_remount_service() {
    echo "Installing remount service..."
    if [[ ! -d /opt/ml/scripts ]]; then
        sudo mkdir -p /opt/ml/scripts
        sudo chmod 755 /opt/ml/scripts
    fi

    CHECK_MOUNT_FILE=/opt/ml/scripts/check_mount_${FSX_MOUNTNAME//\//_}.sh

    sudo tee "$CHECK_MOUNT_FILE" > /dev/null << EOF
#!/bin/bash
MOUNT_POINT=$MOUNT_POINT

if ! grep -qs "\$MOUNT_POINT" /proc/mounts; then
    modprobe lustre
    modprobe lnet
    lctl network up
    mount -t lustre -o noatime,flock "$FSX_DNS_NAME@tcp:/$FSX_MOUNTNAME" "\$MOUNT_POINT"
    echo "Mounted FSx to \$MOUNT_POINT"
else
    echo "FSx Lustre already mounted to \$MOUNT_POINT"
fi
EOF

    sudo chmod +x "$CHECK_MOUNT_FILE"

    sudo tee "/etc/systemd/system/check_fsx_mount_${FSX_MOUNTNAME//\//_}.service" > /dev/null << EOF
[Unit]
Description=Check and remount FSx Lustre filesystems if necessary
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$CHECK_MOUNT_FILE
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo tee "/etc/systemd/system/check_fsx_mount_${FSX_MOUNTNAME//\//_}.timer" > /dev/null << EOF
[Unit]
Description=Run check_fsx_mount_${FSX_MOUNTNAME//\//_}.service every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now "check_fsx_mount_${FSX_MOUNTNAME//\//_}.timer"
}

main() {
    echo "Starting FSx mount process..."
    echo "Parameters:"
    echo "  FSX_DNS_NAME: $FSX_DNS_NAME"
    echo "  FSX_MOUNTNAME: $FSX_MOUNTNAME"
    echo "  MOUNT_POINT: $MOUNT_POINT"
    
    load_lnet_modules
    check_already_mounted
    is_fsx_reachable
    add_to_fstab
    mount_fs
    install_remount_service
    
    echo "FSx Lustre mount process completed successfully"
    df -h "$MOUNT_POINT"
}

main "$@"
