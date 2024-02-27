#!/bin/bash

# move the ubuntu user to the shared /fsx filesystem
if [ -d "/fsx/ubuntu" ]; then
    sudo usermod -d /fsx/ubuntu ubuntu
elif [ -d "/fsx" ]; then
    sudo usermod -m -d /fsx/ubuntu ubuntu
fi