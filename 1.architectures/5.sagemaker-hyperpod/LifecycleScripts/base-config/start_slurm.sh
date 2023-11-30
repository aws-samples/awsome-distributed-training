#!/bin/bash

# must be run as sudo
# USAGE: start_slurm.sh <NODE_TYPE> [<CONTOLLER_ADDRESSES>]
# - Where NODE_TYPE is one of follow values: controller, compute, login

set -ex

LOG_FILE="/var/log/provision/provisioning.log"
CONTROLLER_IP_VALUES=($2)

main() {
  echo "[INFO] START: Starting Slurm daemons"

  if [[ $1 == "controller" ]]; then
      echo "[INFO] This is a Controller node. Start slurm controller daemon..."

      systemctl enable --now slurmctld
  fi

  if [[ $1 == "compute" ]] || [[ $1 == "login" ]]; then
    echo "[INFO] Running on $1 node. Start slurm daemon..."

    SLURMD_OPTIONS="--conf-server $CONTROLLER_IP_VALUES" envsubst < /etc/systemd/system/slurmd.service > slurmd.service
    mv slurmd.service /etc/systemd/system/

    systemctl daemon-reload
    systemctl enable slurmd
    systemctl restart slurmd
  fi

  echo "[INFO] Start Slurm Script completed"
}

main "$@"
