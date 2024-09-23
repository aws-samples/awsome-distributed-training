#!/bin/bash

set -e

BIN_DIR=$(dirname $(readlink -e ${BASH_SOURCE[0]}))

################################################################################
# Install enroot & pyxis
################################################################################
# Modify cgroup.conf to avoid runtime error due to incorrect GPU ID mapping
# https://github.com/NVIDIA/pyxis/issues/47#issuecomment-842065289
if [[ -f /opt/slurm/etc/cgroup.conf ]]; then
  grep ^ConstrainDevices /opt/slurm/etc/cgroup.conf &> /dev/null \
	  || echo "ConstrainDevices=yes" >> /opt/slurm/etc/cgroup.conf
fi

apt-get -y -o DPkg::Lock::Timeout=120 install squashfs-tools parallel libnvidia-container-tools

## These are needed for `enroot start xxx.sqsh`, but on SMHP, `enroot start xxx.sqsh` hangs, hence
## not needed.
##
## The hang behavior may be the same as https://github.com/NVIDIA/enroot/issues/130 and the solution
## is to `enroot create xxx.sqsh ; enroot start xxx ; enroot remove xxx`.
#apt-get -y -o DPkg::Lock::Timeout=120 install fuse-overlayfs squashfuse

SLURM_INSTALL_DIR='/opt/slurm'
PYXIS_TMP_DIR='/tmp/pyxis'

if [ ! -d $SLURM_INSTALL_DIR ]; then
  echo "Slurm installation not found. Skipping pyxis and enroot installation.\n"
  exit 1
fi

rm -fr $SLURM_INSTALL_DIR/pyxis
mkdir -p $SLURM_INSTALL_DIR/enroot/ $SLURM_INSTALL_DIR/pyxis/ $PYXIS_TMP_DIR

PYXIS_VERSION=v0.19.0
ENROOT_VERSION=3.4.1
arch=$(dpkg --print-architecture)
cd $PYXIS_TMP_DIR
curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot_${ENROOT_VERSION}-1_${arch}.deb
curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot+caps_${ENROOT_VERSION}-1_${arch}.deb # optional
apt install -y -o DPkg::Lock::Timeout=120 ./enroot_${ENROOT_VERSION}-1_${arch}.deb
apt install -y -o DPkg::Lock::Timeout=120 ./enroot+caps_${ENROOT_VERSION}-1_${arch}.deb
cp $BIN_DIR/enroot.conf /etc/enroot/enroot.conf

git clone --depth 1 --branch $PYXIS_VERSION https://github.com/NVIDIA/pyxis.git $SLURM_INSTALL_DIR/pyxis
cd $SLURM_INSTALL_DIR/pyxis/
CPPFLAGS='-I /opt/slurm/include/' make -j $(nproc)
CPPFLAGS='-I /opt/slurm/include/' make install
mkdir -p $SLURM_INSTALL_DIR/etc/plugstack.conf.d/
echo -e "include $SLURM_INSTALL_DIR/etc/plugstack.conf.d/*" >> $SLURM_INSTALL_DIR/etc/plugstack.conf
ln -fs /usr/local/share/pyxis/pyxis.conf $SLURM_INSTALL_DIR/etc/plugstack.conf.d/pyxis.conf

mkdir -p /run/pyxis/ /tmp/enroot/data /opt/enroot/
chmod 777 -R /tmp/enroot /opt/enroot
################################################################################
# Below while loop instituted to combat race condition when mapping enroot path to /opt/dlami/nvme described in https://github.com/aws-samples/awsome-distributed-training/issues/427
# Maximum time to wait in seconds (2 minutes = 120 seconds)
MAX_WAIT_TIME=120

# Initialize the elapsed time
ELAPSED_TIME=0

# Interval to wait between each check (in seconds)
CHECK_INTERVAL=5

while true; do
    # Check the ActiveState of the lib/systemd/system/dlami-nvme.service
    ACTIVE_STATE=$(systemctl show dlami-nvme | grep "ActiveState" | cut -d '=' -f 2)
    # Check the ExecMainStatus of the lib/systemd/system/dlami-nvme.service
    RESULT_STATE=$(systemctl show dlami-nvme | grep "ExecMainStatus" | cut -d '=' -f 2)

    # Print the current states of /lib/systemd/system/dlami-nvme.service (for debugging purposes)
    echo "dlami-nvme.service ActiveState: $ACTIVE_STATE"
    echo "dlami-nvme.service ExecMainStatus: $RESULT_STATE"

    # Break the loop if service == active and ExecMainStatus == 0 (which means success)
    if [[ "$ACTIVE_STATE" == "active" && "$RESULT_STATE" == "0" ]]; then
        echo "dlami-nvme.service is active and successful. Proceeding with Enroot configuration on /opt/dlami/nvme if available"
        break
    fi

    # Increment the elapsed time
    ELAPSED_TIME=$((ELAPSED_TIME + CHECK_INTERVAL))

    # Break the loop if the elapsed time exceeds the maximum wait time
    if [[ $ELAPSED_TIME -ge $MAX_WAIT_TIME ]]; then
        echo "WARN: Timeout reached: dlami-nvme.service did not become active and successful, it is possible enroot default path is /opt/sagemaker. When training larger models, dragons be here. See https://github.com/aws-samples/awsome-distributed-training/issues/427 for corrective actions"
        break
    fi

    # Wait for the specified interval before checking again
    sleep $CHECK_INTERVAL
done

####################################################################################################

# Opportunistically use /opt/dlami/nvme (takes precedent) or /opt/sagemaker (secondary) if present. Let's be extra careful in the probe.
if [[ $(mount | grep /opt/dlami/nvme) ]]; then
    sed -i \
        -e 's|^\(ENROOT_RUNTIME_PATH  *\).*$|\1/opt/dlami/nvme/tmp/enroot/user-$(id -u)|' \
        -e 's|^\(ENROOT_CACHE_PATH  *\).*$|\1/opt/dlami/nvme/enroot|' \
        -e 's|^\(ENROOT_DATA_PATH  *\).*$|\1/opt/dlami/nvme/tmp/enroot/data/user-$(id -u)|' \
        -e 's|^#\(ENROOT_TEMP_PATH  *\).*$|\1/opt/dlami/nvme/tmp|' \
        /etc/enroot/enroot.conf

    mkdir -p /opt/dlami/nvme/tmp/enroot/
    chmod 1777 /opt/dlami/nvme/tmp
    chmod 1777 /opt/dlami/nvme/tmp/enroot/

    mkdir -p /opt/dlami/nvme/tmp/enroot/data/
    chmod 1777 /opt/dlami/nvme/tmp/enroot/data/

     mkdir -p /opt/dlami/nvme/enroot
     chmod 1777 /opt/dlami/nvme/enroot

elif [[ $(mount | grep /opt/sagemaker) ]]; then
    sed -i \
        -e 's|^\(ENROOT_RUNTIME_PATH  *\).*$|\1/opt/sagemaker/tmp/enroot/user-$(id -u)|' \
        -e 's|^\(ENROOT_CACHE_PATH  *\).*$|\1/opt/sagemaker/enroot|' \
        -e 's|^\(ENROOT_DATA_PATH  *\).*$|\1/opt/sagemaker/tmp/enroot/data/user-$(id -u)|' \
        -e 's|^#\(ENROOT_TEMP_PATH  *\).*$|\1/opt/sagemaker/tmp|' \
        /etc/enroot/enroot.conf

    mkdir -p /opt/sagemaker/tmp/enroot/
    chmod 1777 /opt/sagemaker/tmp
    chmod 1777 /opt/sagemaker/tmp/enroot/

    mkdir -p /opt/sagemaker/tmp/enroot/data/
    chmod 1777 /opt/sagemaker/tmp/enroot/data/

     mkdir -p /opt/sagemaker/enroot
     chmod 1777 /opt/sagemaker/enroot
     
fi

# Use /fsx for enroot cache, if available. Let's be extra careful in the probe.
if [[ $(mount | grep /fsx) ]]; then
    sed -i -e 's|^\(ENROOT_CACHE_PATH  *\).*$|\1/fsx/enroot|' /etc/enroot/enroot.conf
    mkdir -p /fsx/enroot
    chmod 1777 /fsx/enroot
fi

systemctl is-active --quiet slurmctld && systemctl restart slurmctld || echo "This instance does not run slurmctld"
systemctl is-active --quiet slurmd    && systemctl restart slurmd    || echo "This instance does not run slurmd"
