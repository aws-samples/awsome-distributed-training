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

    mv /etc/systemd/system/slurmd{,_DO_NOT_START_ON_CONTROLLER}.service \
        || { echo "Failed to mask slurmd, perhaps the AMI already masked it?" ; }
  elif [[ $1 == "compute" ]] || [[ $1 == "login" ]]; then
    echo "[INFO] Running on $1 node. Start slurm daemon..."

    # Login nodes must still restart slurmd to fetch slurm.conf to /var/spool/slurmd/, however
    # slurmd won't run because slurm.conf does not contain login nodes.
    SLURMD_OPTIONS="--conf-server $CONTROLLER_IP_VALUES" envsubst < /etc/systemd/system/slurmd.service > slurmd.service
    mv slurmd.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now slurmd

    mv /etc/systemd/system/slurmctld{,_DO_NOT_START_ON_CONTROLLER}.service \
        || { echo "Failed to mask slurmctldd, perhaps the AMI already masked it?" ; }
  fi

  echo "[INFO] Start Slurm Script completed"
}

main "$@"
