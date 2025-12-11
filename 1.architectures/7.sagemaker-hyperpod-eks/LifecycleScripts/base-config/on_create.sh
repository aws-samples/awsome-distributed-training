#!/bin/bash

set -ex

LOG_FILE="/var/log/provision/provisioning.log"
mkdir -p "/var/log/provision"
touch "$LOG_FILE"

logger() {
  echo "$@" | tee -a "$LOG_FILE"
}

logger "[start] on_create.sh"

if ! bash ./on_create_main.sh >> "$LOG_FILE" 2>&1; then
  logger "[error] on_create_main.sh failed, waiting 60 seconds before exit"
  sync
  sleep 60
  logger "[stop] on_create.sh with error"
  exit 1
fi

logger "[stop] on_create.sh"
