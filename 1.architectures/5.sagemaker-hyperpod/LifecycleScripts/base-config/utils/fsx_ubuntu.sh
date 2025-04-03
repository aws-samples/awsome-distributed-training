#!/bin/bash

# Check if OpenZFS is mounted
if df -h | grep -q "/home"; then
    echo "OpenZFS is mounted at /home"
    if [ -d "/home" ]; then
        # Set home directory to /home/ubuntu
        sudo usermod -m -d /home/ubuntu ubuntu
        echo "Home directory set to /home/ubuntu"

        # Maintain access to /fsx/ubuntu
        sudo mkdir -p /fsx/ubuntu
        sudo chown ubuntu:ubuntu /fsx/ubuntu
    fi
else
    echo "OpenZFS is not mounted. Using FSxL file system"
    if [ -d "/fsx/ubuntu" ]; then
        sudo usermod -d /fsx/ubuntu ubuntu
    elif [ -d "/fsx" ]; then
        sudo usermod -m -d /fsx/ubuntu ubuntu
    fi
fi


# move the ubuntu user to the shared /fsx filesystem
# if [ -d "/fsx/ubuntu" ]; then
#     sudo usermod -d /fsx/ubuntu ubuntu
# elif [ -d "/fsx" ]; then
#     sudo usermod -m -d /fsx/ubuntu ubuntu
# fi