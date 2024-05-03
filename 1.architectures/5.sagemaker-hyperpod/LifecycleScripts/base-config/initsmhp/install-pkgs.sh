#!/bin/bash

set -exuo pipefail

# https://askubuntu.com/a/1431746
export NEEDRESTART_MODE=a
export DEBIAN_FRONTEND=noninteractive

add-apt-repository ppa:git-core/ppa -y
apt -o DPkg::Lock::Timeout=120 update

declare -a PKG=(git unzip tree most fio dstat dos2unix tig jq ncdu inxi mediainfo git-lfs nvme-cli aria2 ripgrep bat python3-venv python3-pip)
[[ $(apt-cache search ^duf$) ]] && PKG+=(duf)

apt-get -y -o DPkg::Lock::Timeout=120 install "${PKG[@]}"
[[ -e /usr/bin/batcat ]] && ln -s /usr/bin/batcat /usr/bin/bat
echo -e '\nexport DSTAT_OPTS="-cdngym"' >> /etc/profile.d/z99-initsmhp.sh

# VSCode: https://code.visualstudio.com/docs/setup/linux#_visual-studio-code-is-unable-to-watch-for-file-changes-in-this-large-workspace-error-enospc
echo -e '\nfs.inotify.max_user_watches=524288' | tee -a /etc/sysctl.conf
sysctl -p
