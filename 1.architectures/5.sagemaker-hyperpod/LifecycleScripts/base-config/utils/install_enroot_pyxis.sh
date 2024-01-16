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
