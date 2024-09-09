#!/bin/bash

set -ex

LOG_FILE="/var/log/provision/provisioning.log"
mkdir -p "/var/log/provision"
touch $LOG_FILE

# Function to log messages
logger() {
  echo "$@" | tee -a $LOG_FILE
}

logger "[start] on_create.sh"
logger "no more steps to run"
logger "[stop] on_create.sh"