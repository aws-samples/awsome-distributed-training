#!/bin/bash

# This script only installs the mount-s3 package. Users must mount the S3 themselves as part of
# their cluster usage.

set -exuo pipefail
cd /tmp
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.deb
apt-get install -y -o DPkg::Lock::Timeout=120 ./mount-s3.deb
