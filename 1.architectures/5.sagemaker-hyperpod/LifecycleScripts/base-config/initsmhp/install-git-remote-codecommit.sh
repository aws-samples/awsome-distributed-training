#!/bin/bash

set -exuo pipefail

apt install -y -o DPkg::Lock::Timeout=120 python3-jmespath
/usr/bin/pip3 install git-remote-codecommit
