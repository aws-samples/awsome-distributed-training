#!/bin/bash

# must be run as sudo

set -x
set -e

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
    modprobe -v lnet
}

# Mount the FSx Lustre file system using Ansible
mount_fs()
{
    ansible localhost -b -m ansible.posix.mount -a "path=$MOUNT_POINT src=$FSX_DNS_NAME@tcp:/$FSX_MOUNTNAME fstype=lustre opts=noatime,flock,_netdev,x-systemd.automount,x-systemd.requires=network-online.target dump=0 passno=0 state=mounted"
}

main() 
{
    verify_parameters
    echo "Mount_fsx called with fsx_dns_name: $FSX_DNS_NAME, fsx_mountname: $FSX_MOUNTNAME"
    echo "Using mount_point: $MOUNT_POINT"
    echo "LUSTRE CLIENT CONFIGURATION $(print_lustre_version)"
    load_lnet_modules
    mount_fs
    echo "FSx Lustre mounted successfully to $MOUNT_POINT"
}

main "$@"