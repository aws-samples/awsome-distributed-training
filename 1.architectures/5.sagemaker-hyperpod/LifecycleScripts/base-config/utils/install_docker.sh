#!/bin/bash

set -exo pipefail

# If docker is alrady installed, skip installing again
if command -v docker &> /dev/null; then
    echo "Docker is already installed and in the PATH."
    exit 0
fi

echo "
###################################
# BEGIN: install docker
###################################
"

apt-get -y -o DPkg::Lock::Timeout=120 update
apt-get -y -o DPkg::Lock::Timeout=120 install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get -y -o DPkg::Lock::Timeout=120 update
apt-get -y -o DPkg::Lock::Timeout=120 install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
chgrp docker $(which docker)
chmod g+s $(which docker)
systemctl enable docker.service
systemctl start docker.service

# install nvidia docker toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get install -y -o DPkg::Lock::Timeout=120 nvidia-container-toolkit

# add user to docker group
sudo usermod -aG docker ubuntu


# Opportunistically use /opt/sagemaker or /opt/dlami/nvme if present. Let's be extra careful in the probe.
# See: https://github.com/aws-samples/awsome-distributed-training/issues/127
#
# Docker workdir doesn't like Lustre. Tried with storage driver overlay2, fuse-overlayfs, & vfs.
if [[ $(mount | grep /opt/sagemaker) ]]; then
    cat <<EOL >> /etc/docker/daemon.json
{
    "data-root": "/opt/sagemaker/docker/data-root"
}
EOL

    sed -i \
        's|^\[Service\]$|[Service]\nEnvironment="DOCKER_TMPDIR=/opt/sagemaker/docker/tmp"|' \
        /usr/lib/systemd/system/docker.service
elif [[ $(mount | grep /opt/dlami/nvme) ]]; then
    cat <<EOL >> /etc/docker/daemon.json
{
    "data-root": "/opt/dlami/nvme/docker/data-root"
}
EOL

    sed -i \
        's|^\[Service\]$|[Service]\nEnvironment="DOCKER_TMPDIR=/opt/dlami/nvme/docker/tmp"|' \
        /usr/lib/systemd/system/docker.service
fi

systemctl daemon-reload
systemctl restart docker
