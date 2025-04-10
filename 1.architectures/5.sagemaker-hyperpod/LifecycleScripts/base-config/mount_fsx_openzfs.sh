#!/bin/bash

# must be run as sudo

set -x
set -e

# FSx OpenZFS Endpoints and versions
FSX_OPENZFS_DNS_NAME="$1"
OPENZFS_MOUNT_POINT="$2"
NFS_VERSION=4.2

# Ansible Version
ANSIBLE_VERSION="6.7.0"

# Function for error handling
handle_error()
{
    local exit_code=$?
    echo "Error occured in command: $BASH_COMMAND"
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

# Install Ansible and collections: Move to higher LCS once others start using Ansible too.
install_ansible()
{
    apt-get update
    # apt-get install -y ansible=$ANSIBLE_VERSION
    apt-get install -y python3-pip
    python3 -m pip install "ansible==${ANSIBLE_VERSION}"
    ansible-galaxy collection install ansible.posix
}

# Install NFS Client based on OS
install_nfs_client()
{
    if [ -f /etc/lsb-release ]; then
        # Ubuntu
        ansible localhost -b -m ansible.builtin.apt -a "name=nfs-common state=present update_cache=yes"
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        ansible localhost -b -m ansible.builtin.yum -a "name=nfs-utils state=present"
    fi
}

# Mount the FSx OpenZFS file system
mount_fs()
{
    ansible localhost -b -m ansible.posix.mount -a "path=$OPENZFS_MOUNT_POINT src=$FSX_OPENZFS_DNS_NAME:/fsx fstype=nfs opts=nfsvers=$NFS_VERSION,_netdev,nconnect=16,x-systemd.automount,x-systemd.requires=network-online.target dump=0 passno=0 state=mounted"
}

main() 
{
    echo "Mount_fsx_openzfs called with fsx_openzfs_dns_name: $FSX_OPENZFS_DNS_NAME"
    echo "Using openzfs_mount_point: $OPENZFS_MOUNT_POINT"
    verify_parameters
    install_ansible
    install_nfs_client
    mount_fs
    echo "FSx OpenZFS mounted successfully to $OPENZFS_MOUNT_POINT"
}

main "$@"