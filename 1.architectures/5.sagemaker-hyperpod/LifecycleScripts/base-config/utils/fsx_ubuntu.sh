#!/bin/bash

# RETRY CONFIG
ATTEMPTS=6
WAIT=10
FSX_OZFS_EXISTS=$1
FSX_OPENZFS_DNS_NAME="/home"
FSX_L_DNS_NAME="/fsx"

# Function to check mount
check_mount()
{
    local mount_point="$1"
    if mountpoint -q "$mount_point" && touch "$mount_point/.test_write" 2>/dev/null; then
        rm -f "$mount_point/.test_write"
        return 0
    fi
    return 1
}

# Wait for mount (both OpenZFS and FSxL)
wait_for_mount()
{
    local mount_point="$1"
    for ((i=1; i<=$ATTEMPTS; i++)); do
        if check_mount "$mount_point"; then
            echo "Successfully verified mount at $mount_point"
            return 0
        fi
        if [ $i -eq $ATTEMPTS ]; then
            echo "Mount not ready after $((ATTEMPTS * WAIT)) seconds"
            return 1
        fi
        echo "Waiting for FSx mount: $mount_point to be ready... (attempt $i/$ATTEMPTS)"
        sleep $WAIT
    done
}

if [ -z "$FSX_OZFS_EXISTS" ]; then
    echo "Error: Missing parameter. Usage: $0 <1|0> (1 if OpenZFS exists, 0 otherwise)"
    exit 1
fi

# Check if OpenZFS is mounted
if [ $FSX_OZFS_EXISTS -eq 1 ]; then 
    echo "OpenZFS is mounted. Looping to ensure FSxOZFS is mounted."

    if wait_for_mount "$FSX_OPENZFS_DNS_NAME"; then
        ansible localhost -b -m ansible.builtin.file -a "path='$FSX_OPENZFS_DNS_NAME/ubuntu' state=directory owner=ubuntu group=ubuntu mode=0755"

        echo "OpenZFS is mounted at $FSX_OPENZFS_DNS_NAME"
        # Set home directory to /home/ubuntu
        sudo usermod -m -d "$FSX_OPENZFS_DNS_NAME/ubuntu" ubuntu
        echo "Home directory set to $FSX_OPENZFS_DNS_NAME/ubuntu"

        # Maintain access to /fsx/ubuntu
        if wait_for_mount "$FSX_L_DNS_NAME"; then
            sudo mkdir -p "$FSX_L_DNS_NAME/ubuntu"
            sudo chown ubuntu:ubuntu "$FSX_L_DNS_NAME/ubuntu"
        else
            echo "Warning: FSx mount not available, skipping $FSX_L_DNS_NAME/ubuntu setup"
        fi
    fi
else
    echo "OpenZFS is not mounted. Skipped OZFS check loop, and looping for FSxL only."
    echo "Using FSxL file system as home..."

    if ! wait_for_mount "$FSX_L_DNS_NAME"; then
        echo "Warning: FSx mount not available. Exiting."
        exit 1
    fi
    if [ -d "$FSX_L_DNS_NAME/ubuntu" ]; then
        sudo usermod -d "$FSX_L_DNS_NAME/ubuntu" ubuntu
    elif [ -d "$FSX_L_DNS_NAME" ]; then
        # Create the directory (race condition: if it doesn't get detected)
        sudo mkdir -p "$FSX_L_DNS_NAME/ubuntu"
        sudo chown ubuntu:ubuntu "$FSX_L_DNS_NAME/ubuntu"

        # Try to change home directory with move (race condition)
        if ! sudo usermod -m -d "$FSX_L_DNS_NAME/ubuntu" ubuntu; then
            echo "Warning: Could not move home directory. Setting home without moving files."

            sudo rsync -a /home/ubuntu/ "$FSX_L_DNS_NAME/ubuntu/"
            sudo chown -R ubuntu:ubuntu "$FSX_L_DNS_NAME/ubuntu"

            sudo usermod -d "$FSX_L_DNS_NAME/ubuntu" ubuntu
        else
            echo "Home directory moved successfully to $FSX_L_DNS_NAME/ubuntu"
        fi
    fi
fi