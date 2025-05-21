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
export NVIDIA_CONTAINER_TLK_VERSION="1.17.6-1"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt-get install -y -o DPkg::Lock::Timeout=120 nvidia-container-toolkit=${NVIDIA_CONTAINER_TLK_VERSION} nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TLK_VERSION} libnvidia-container-tools=${NVIDIA_CONTAINER_TLK_VERSION} libnvidia-container1=${NVIDIA_CONTAINER_TLK_VERSION}
# Lock nvidia-container-toolkit version
sudo apt-mark hold nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1

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




#!/bin/bash

set -exo pipefail

# Define exponential backoff function
function retry_with_backoff() {
    local max_attempts=$1
    local initial_wait=$2
    local max_wait=$3
    local command="${@:4}"
    local attempt=1
    local wait_time=$initial_wait

    while true; do
        echo "Attempt $attempt of $max_attempts: $command"
        if eval "$command"; then
            return 0
        fi

        if (( attempt == max_attempts )); then
            echo "Command failed after $max_attempts attempts: $command"
            return 1
        fi

        echo "Command failed. Retrying in $wait_time seconds..."
        sleep $wait_time

        attempt=$(( attempt + 1 ))
        wait_time=$(( wait_time * 2 ))
        if (( wait_time > max_wait )); then
            wait_time=$max_wait
        fi
    done
}

# If docker is already installed, skip installing again
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

# Docker GPG key download with retry
retry_with_backoff 5 5 60 "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get -y -o DPkg::Lock::Timeout=120 update
apt-get -y -o DPkg::Lock::Timeout=120 install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
chgrp docker $(which docker)
chmod g+s $(which docker)
systemctl enable docker.service
systemctl start docker.service

# Install nvidia docker toolkit with retry
retry_with_backoff 5 5 60 "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
retry_with_backoff 5 5 60 "curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"
sudo apt-get install -y -o DPkg::Lock::Timeout=120 nvidia-container-toolkit

# add user to docker group
sudo usermod -aG docker ubuntu

# Opportunistically use /opt/sagemaker or /opt/dlami/nvme if present
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
