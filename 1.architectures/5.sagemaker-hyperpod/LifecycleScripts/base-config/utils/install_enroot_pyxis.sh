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

PYXIS_VERSION=v0.16.1
ENROOT_VERSION=3.4.1
arch=$(dpkg --print-architecture)
cd $PYXIS_TMP_DIR
curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot_${ENROOT_VERSION}-1_${arch}.deb
curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot+caps_${ENROOT_VERSION}-1_${arch}.deb # optional
apt install -y ./enroot_${ENROOT_VERSION}-1_${arch}.deb
apt install -y ./enroot+caps_${ENROOT_VERSION}-1_${arch}.deb
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


# Opportunistically use /opt/dlami/nvme if present. Let's be extra careful in the probe.
#
# Note: ENROOT_TEMP_PATH on Lustre throws "Unrecognised xattr prefix lustre.lov".
# See: https://github.com/aws-samples/awsome-distributed-training/issues/127
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

    #mkdir -p /opt/dlami/nvme/tmp/enroot/data/
    #chmod 1777 /opt/dlami/nvme/tmp/enroot/data/

    # mkdir -p /opt/dlami/nvme/enroot
    # chmod 1777 /opt/dlami/nvme/enroot

fi

# Use /fsx for enroot cache, if available. Let's be extra careful in the probe.
if [[ $(mount | grep /fsx) ]]; then
    sed -i -e 's|^\(ENROOT_CACHE_PATH  *\).*$|\1/fsx/enroot|' /etc/enroot/enroot.conf
    mkdir -p /fsx/enroot
    chmod 1777 /fsx/enroot
fi
