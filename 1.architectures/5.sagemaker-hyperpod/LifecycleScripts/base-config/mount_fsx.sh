#!/bin/bash

# must be run as sudo

set -eux 

# FSx Lustre Endpoints
FSX_DNS_NAME="$1"
FSX_MOUNTNAME="$2"
MOUNT_POINT="$3"

# Function for error handling
handle_error()
{
    local exit_code=$?
    echo "Error occurred in command: $BASH_COMMAND"
    echo "Exit code: $exit_code"
    echo "Exit logs:"
    sudo dmesg | tail -n 20
    echo "Mount status:"
    mount | grep lustre || true
    echo "LNet status:"
    sudo lctl list_nids || true
    exit $exit_code
}

trap handle_error ERR

# DEBUG: Verify parameters are set
verify_parameters()
{
    if [ -z "$FSX_DNS_NAME" ] || [ -z "$FSX_MOUNTNAME" ] || [ -z "$MOUNT_POINT" ]; then
        echo "Usage: $0 <fsx_dns_name> <fsx_mountname> <mount_point>"
        exit 1
    fi
}

# Print Lustre client version
print_lustre_version()
{
    echo "Lustre client version:"
    modinfo lustre | grep 'version:' | head -n 1 | awk '{print $2}'
}

# Load lnet modules
load_lnet_modules()
{
  ansible localhost -b -m ansible.builtin.modprobe -a "name=lnet state=present"
  ansible localhost -b -m ansible.builtin.modprobe -a "name=lustre state=present"
  lctl network up || { echo "Error: Failed to bring up LNet network"; exit 1; }     # Simplifying: Instead of using ansible.builtin.shell
}

# Mount the FSx Lustre file system using Ansible
mount_fs() {
    local max_attempts=5
    local attempt=1
    local delay=5

    echo "[INFO] Ensuring $MOUNT_POINT directory exists..."
    ansible localhost -b -m ansible.builtin.file -a "path=$MOUNT_POINT state=directory" || true

    echo "[INFO] Mounting FSx Lustre on $MOUNT_POINT..."

    while (( attempt <= max_attempts )); do
        echo "============================"
        echo "[INFO] Attempt $attempt of $max_attempts"
        echo "============================"

        echo "[STEP] Mounting FSx..."
        if ! ansible localhost -b -m ansible.posix.mount -a \
            "path=$MOUNT_POINT src=$FSX_DNS_NAME@tcp:/$FSX_MOUNTNAME fstype=lustre opts=noatime,flock,_netdev,x-systemd.automount,x-systemd.requires=network-online.target dump=0 passno=0 state=mounted"; then
            echo "[WARN] Mount command failed — retrying in $delay seconds"
            sleep "$delay"; ((attempt++)); continue
        fi

        echo "[STEP] Verifying mountpoint..."
        if ! ansible localhost -b -m ansible.builtin.command -a "mountpoint $MOUNT_POINT"; then            
            echo "[WARN] Mountpoint verification failed — retrying in $delay seconds"
            sleep "$delay"; ((attempt++)); continue
        fi
        echo "[STEP] Triggering automount..."
        ls -la "$MOUNT_POINT" >/dev/null 2>&1 || true

        echo "[STEP] Testing file access (touch)..."
        if ! ansible localhost -b -m ansible.builtin.file -a "path=$MOUNT_POINT/test_file state=touch"; then
            echo "[WARN] Touch failed — retrying in $delay seconds"
            sleep "$delay"; ((attempt++)); continue
        fi

        echo "[STEP] Testing file access (delete)..."
        if ! ansible localhost -b -m ansible.builtin.file -a "path=$MOUNT_POINT/test_file state=absent"; then
            echo "[WARN] Delete failed — retrying in $delay seconds"
            sleep "$delay"; ((attempt++)); continue
        fi

        echo "[SUCCESS] FSx mount succeeded on attempt $attempt"
        return 0
    done

    echo "[ERROR] FSx mount failed after $max_attempts attempts"
    return 1
}



restart_daemon()
{
  ansible localhost -b -m ansible.builtin.systemd -a "daemon_reload=yes"
  ansible localhost -b -m ansible.builtin.systemd -a "name=remote-fs.target state=restarted"
  # Readable status check
  echo "Check status of fsx automount service..."
  systemctl status fsx.automount
}

main() 
{
    verify_parameters
    echo "Mount_fsx called with fsx_dns_name: $FSX_DNS_NAME, fsx_mountname: $FSX_MOUNTNAME"
    echo "Using mount_point: $MOUNT_POINT"
    echo "LUSTRE CLIENT CONFIGURATION $(print_lustre_version)"
    load_lnet_modules
    mount_fs || exit 1
    restart_daemon
    echo "FSx Lustre mounted successfully to $MOUNT_POINT"
}

main "$@"