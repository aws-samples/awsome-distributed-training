#!/bin/bash

set -exuo pipefail

mkdir -p ~/.ssh
cd ~/.ssh
{ test -f id_rsa && grep "^$(cat id_rsa.pub)$" authorized_keys &> /dev/null ; } && GENERATE_KEYPAIR=0 || GENERATE_KEYPAIR=1
if [[ $GENERATE_KEYPAIR == 1 ]]; then
    echo Generate a new keypair...
    SSH_KEYGEN_ARGS=""
    if [[ -f /opt/initsmhp-cluster_config.json ]]; then
        CLUSTER_ARN=$(jq -r ".ClusterArn" /opt/initsmhp-cluster_config.json)
        CLUSTER_NAME=$(jq -r ".ClusterName" /opt/initsmhp-cluster_config.json)
        SSH_KEYGEN_ARGS="-C $(whoami)@$(hostname)__${CLUSTER_NAME}__${CLUSTER_ARN}"
    fi

    ssh-keygen -t rsa -q -f id_rsa -N "" ${SSH_KEYGEN_ARGS}
    cat id_rsa.pub >> authorized_keys
else
    echo Use existing keypair...
fi
