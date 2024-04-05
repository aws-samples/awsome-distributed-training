#!/bin/bash

set -exuo pipefail

DRV_VERSION=$(modinfo -F version nvidia)
DRV_VERSION_MAJOR=${DRV_VERSION%%.*}
MOCK_PKG=libnvidia-compute-${DRV_VERSION_MAJOR}

#apt-get -y -o DPkg::Lock::Timeout=120 update   # Most likely this has been been done by another script.
apt-get -y -o DPkg::Lock::Timeout=120 install equivs

apt-cache show ${MOCK_PKG}=${DRV_VERSION}-0ubuntu1 \
    | egrep '^Package|^Version|^Provides' \
    &> ${MOCK_PKG}

equivs-build ${MOCK_PKG}
apt install -y -o DPkg::Lock::Timeout=120 ./${MOCK_PKG}_*.deb

dpkg_hold_with_retry() {
    # Retry when dpkg frontend is locked
    for (( i=0; i<=20; i++ )); do
        echo "$1 hold" | sudo dpkg --set-selections && break || { echo To retry... ; sleep 6 ; }
    done
}
dpkg_hold_with_retry ${MOCK_PKG}

