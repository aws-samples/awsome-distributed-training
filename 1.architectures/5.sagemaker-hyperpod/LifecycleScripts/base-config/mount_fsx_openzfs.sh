#!/bin/bash

# must be run as sudo

set -x
set -e

# FSx OpenZFS Endpoints and versions
FSX_OPENZFS_DNS_NAME="$1"
OPENZFS_MOUNT_POINT="$2"
NFS_VERSION=4.2

# Ansible Version
ANSIBLE_VERSION="10.7.0"

# Retry settings
MAX_ATTEMPTS=5
INITIAL_BACKOFF=1

# Function for exponential backoff
retry_with_backoff() {
    local max_attempts=$1
    local initial_backoff=$2
    local cmd="${@:3}"
    local attempt=1
    local backoff=$initial_backoff

    while [ $attempt -le $max_attempts ]; do
        if eval "$cmd"; then
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo "Failed after $attempt attempts"
            return 1
        fi
        
        echo "Attempt $attempt failed. Retrying in $backoff seconds..."
        sleep $backoff
        
        # Exponential backoff with jitter
        backoff=$(( backoff * 2 + (RANDOM % 3) ))
        attempt=$((attempt + 1))
    done
}

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
    if [ -z "$FSX_OPENZFS_DNS_NAME" ] || [ -z "$OPENZFS_MOUNT_POINT" ]; then
        echo "Usage: $0 <fsx_dns_name> <mount_point>"
        exit 1
    fi
}

# Install Ansible and collections
install_ansible()
{
    retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "apt-get update"
    retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "apt-get install -y python3-pip"
    retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "python3 -m pip install 'ansible==${ANSIBLE_VERSION}'"
    retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "ansible-galaxy collection install ansible.posix"
}

# Install NFS Client based on OS
install_nfs_client()
{
    if [ -f /etc/lsb-release ]; then
        # Ubuntu
        retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "ansible ********* -b -m ansible.builtin.apt -a 'name=nfs-common state=present update_cache=yes'"
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "ansible ********* -b -m ansible.builtin.yum -a 'name=nfs-utils state=present'"
    fi
}

# Mount the FSx OpenZFS file system
mount_fs()
{
    # Create mount point directory if it doesn't exist
    if [ ! -d "$OPENZFS_MOUNT_POINT" ]; then
        mkdir -p "$OPENZFS_MOUNT_POINT"
    fi

    retry_with_backoff $MAX_ATTEMPTS $INITIAL_BACKOFF "ansible ********* -b -m ansible.posix.mount -a \"path=$OPENZFS_MOUNT_POINT src=$FSX_OPENZFS_DNS_NAME:/fsx fstype=nfs opts=nfsvers=$NFS_VERSION,_netdev,nconnect=16,x-systemd.automount,x-systemd.requires=network-online.target dump=0 passno=0 state=mounted\""
}

# Verify mount was successful
verify_mount()
{
    if ! mountpoint -q "$OPENZFS_MOUNT_POINT"; then
        echo "Failed to verify mount point $OPENZFS_MOUNT_POINT"
        exit 1
    fi
}

main() 
{
    echo "Mount_fsx_openzfs called with fsx_openzfs_dns_name: $FSX_OPENZFS_DNS_NAME"
    echo "Using openzfs_mount_point: $OPENZFS_MOUNT_POINT"
    verify_parameters
    install_ansible
    install_nfs_client
    mount_fs
    verify_mount
    echo "FSx OpenZFS mounted successfully to $OPENZFS_MOUNT_POINT"
}

main "$@"