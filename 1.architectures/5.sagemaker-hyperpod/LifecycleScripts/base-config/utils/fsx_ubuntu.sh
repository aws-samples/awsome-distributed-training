#!/bin/bash

# RETRY CONFIG
ATTEMPTS=6
WAIT=10
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

# Check if OpenZFS is mounted
if wait_for_mount "$FSX_OPENZFS_DNS_NAME"; then
    echo "OpenZFS is mounted at $FSX_OPENZFS_DNS_NAME"
    if [ -d "$FSX_OPENZFS_DNS_NAME" ]; then
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
    echo "OpenZFS is not mounted. Using FSxL file system as home"
    if ! wait_for_mount "$FSX_L_DNS_NAME"; then
        echo "Warning: FSx mount not available. Exiting."
        exit 1
    fi
    if [ -d "$FSX_L_DNS_NAME/ubuntu" ]; then
        sudo usermod -d "$FSX_L_DNS_NAME/ubuntu" ubuntu
    elif [ -d "$FSX_L_DNS_NAME" ]; then
        sudo usermod -m -d "$FSX_L_DNS_NAME/ubuntu" ubuntu
    fi
fi