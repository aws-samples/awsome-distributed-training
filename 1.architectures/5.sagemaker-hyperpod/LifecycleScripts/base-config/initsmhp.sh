#!/bin/bash

[[ "$1" == "" ]] && NODE_TYPE=other || NODE_TYPE="$1"

set -exuo pipefail

BIN_DIR=$(dirname $(realpath ${BASH_SOURCE[@]}))
chmod ugo+x $BIN_DIR/initsmhp/*.sh

declare -a PKGS_SCRIPTS=(
    install-pkgs.sh
    install-mount-s3.sh
    install-git-remote-codecommit.sh
)
mkdir /var/log/initsmhp
for i in "${PKGS_SCRIPTS[@]}"; do
    bash -x $BIN_DIR/initsmhp/$i &> /var/log/initsmhp/$i.txt \
        && echo "SUCCESS: $i" >> /var/log/initsmhp/initsmhp.txt \
        || echo "FAIL: $i" >> /var/log/initsmhp/initsmhp.txt
done

bash -x $BIN_DIR/initsmhp/fix-profile.sh
bash -x $BIN_DIR/initsmhp/ssh-to-compute.sh

# /opt/ml/config/resource_config.json is not world-readable, so take only the part that later-on
# used for ssh-keygen comment.
cat /opt/ml/config/resource_config.json | jq '.ClusterConfig' > /opt/initsmhp-cluster_config.json

if [[ "${NODE_TYPE}" == "controller" ]]; then
    runuser -l ubuntu $BIN_DIR/initsmhp/gen-keypair-ubuntu.sh
    bash -x $BIN_DIR/initsmhp/howto-miniconda.sh
fi
