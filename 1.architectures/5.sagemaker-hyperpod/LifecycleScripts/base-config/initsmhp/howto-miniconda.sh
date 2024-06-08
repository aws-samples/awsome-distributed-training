#!/bin/bash

set -exuo pipefail

cat << 'EOF' > /etc/skel/HOWTO-install-miniconda.md
# How to install miniconda

**Pre-requisite:** home directory is located on the shared `/fsx` filesystem. If this is not the
case, please contact your sysadmins.

```bash
cd ~
curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod 755 Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f
~/miniconda3/bin/conda init

# For conda command to become available, close and re-open your current shell.
exit
# ... then reconnect back, and now you should see shell prompts start with (base).

# Example based on https://pytorch.org/get-started/locally/
conda create -y -n pt220-p312 python=3.12
conda activate pt220-p312
# Make sure your shell prompts start with (pt220-p312).
conda install pytorch torchvision torchaudio pytorch-cuda=12.1 -c pytorch -c nvidia -y
```
EOF

runuser -u ubuntu -- cp /etc/skel/HOWTO-install-miniconda.md ~ubuntu/
