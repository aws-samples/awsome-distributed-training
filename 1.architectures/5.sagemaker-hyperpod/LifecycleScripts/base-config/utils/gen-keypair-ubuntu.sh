#!/bin/bash

set -exuo pipefail

mkdir -p /fsx/ubuntu/.ssh
cd /fsx/ubuntu/.ssh
{ test -f id_rsa && grep "^$(cat id_rsa.pub)$" authorized_keys &> /dev/null ; } && GENERATE_KEYPAIR=0 || GENERATE_KEYPAIR=1
if [[ $GENERATE_KEYPAIR == 1 ]]; then
    echo Generate a new keypair...
    ssh-keygen -t rsa -q -f id_rsa -N ""
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