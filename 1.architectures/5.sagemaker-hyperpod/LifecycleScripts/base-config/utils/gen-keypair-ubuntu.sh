#!/bin/bash

set -exuo pipefail

FSX_DIR="/fsx/ubuntu"
FSX_OZFS_DIR="/home/ubuntu"

mkdir -p $FSX_DIR/.ssh

# Creating symlink between /fsx/ubuntu/.ssh and /home/ubuntu/.ssh
if [ -d "$FSX_OZFS_DIR" ]; then
    if [ -L "$FSX_OZFS_DIR/.ssh" ]; then
        echo "$FSX_OZFS_DIR/.ssh is already a symbolic link"
    elif [ -e "$FSX_OZFS_DIR/.ssh" ]; then
        echo "Removing existing $FSX_OZFS_DIR/.ssh and creating symbolic link..."
        rm -rf "$FSX_OZFS_DIR/.ssh"
        ansible localhost -b -m ansible.builtin.file -a "src='$FSX_DIR/.ssh' dest='$FSX_OZFS_DIR/.ssh' state=link"
    else
        echo "Linking $FSX_DIR/.ssh to $FSX_OZFS_DIR/.ssh..."
        ansible localhost -b -m ansible.builtin.file -a "src='$FSX_DIR/.ssh' dest='$FSX_OZFS_DIR/.ssh' state=link"
    fi
fi

cd $FSX_DIR/.ssh

# Check if id_rsa exists
if [ ! -f id_rsa ]; then
    GENERATE_KEYPAIR=1
else
    GENERATE_KEYPAIR=0
    # Check if id_rsa.pub exists in authorized_keys
    if ! grep -qF "$(cat id_rsa.pub)" authorized_keys 2>/dev/null; then
        # If not, add the public key to authorized_keys
        cat id_rsa.pub >> authorized_keys
    fi
fi
if [[ $GENERATE_KEYPAIR == 1 ]]; then
    echo Generate a new keypair...
    ssh-keygen -t rsa -b 4096 -q -f id_rsa -N "" 2>/dev/null || true
    cat id_rsa.pub >> authorized_keys
else
    echo Use existing keypair...
fi

# (diff: do this regardless of if new kp is generated to ensure consistent permissions)
# Set permissions for the ssh keypair 
chmod 600 id_rsa
chmod 644 id_rsa.pub
# Set permissions for authorized_keys
touch authorized_keys
chmod 600 authorized_keys
# Set permissions for the .ssh directory
chmod 700 $FSX_DIR/.ssh
# Change ownership to the ubuntu user
chown ubuntu:ubuntu id_rsa id_rsa.pub authorized_keys
