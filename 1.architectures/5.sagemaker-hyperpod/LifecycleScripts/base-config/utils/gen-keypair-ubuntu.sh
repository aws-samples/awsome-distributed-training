#!/bin/bash

set -exuo pipefail

mkdir -p /fsx/ubuntu/.ssh
cd /fsx/ubuntu/.ssh

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
    ssh-keygen -t rsa  -b 4096 -q -f id_rsa -N ""
    cat id_rsa.pub >> authorized_keys
    # Set permissions for the ssh keypair
    chmod 600 id_rsa
    chmod 644 id_rsa.pub
    # Set permissions for the .ssh directory
    chmod 700 /fsx/ubuntu/.ssh
    # Change ownership to the ubuntu user
    chown ubuntu:ubuntu id_rsa id_rsa.pub authorized_keys
    chown ubuntu:ubuntu /fsx/ubuntu/.ssh
else
    echo Use existing keypair...
fi
