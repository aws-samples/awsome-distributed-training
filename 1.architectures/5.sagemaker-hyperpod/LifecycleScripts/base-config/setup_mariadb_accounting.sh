#!/bin/bash

set -ex

SLURM_ACCOUNTING_CONFIG_FILE=/opt/slurm/etc/accounting.conf
SLURMDB_CONFIG_FILE=/opt/slurm/etc/slurmdbd.conf
SLURMDB_SERVICE_FILE=/etc/systemd/system/slurmdbd.service

LOG_DIR=/var/log/provision
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR"
fi

# Setup MariaDB using secure_installation and default password.
# Use expect to for the interactive shell.
setup_mariadb() {
  echo "Running mysql_secure_installation"
  SECURE_MYSQL=$(expect -c "
  set timeout 10
  log_file /var/log/provision/secure_mysql.log
  spawn mysql_secure_installation
  expect \"Enter current password for root (enter for none):\"
  send \"\r\"
  expect \"Change the root password?\"
  send \"n\r\"
  expect \"Remove anonymous users?\"
  send \"y\r\"
  expect \"Disallow root login remotely?\"
  send \"y\r\"
  expect \"Remove test database and access to it?\"
  send \"y\r\"
  expect \"Reload privilege tables now?\"
  send \"y\r\"
  expect eof
  ")
}

# Create the default database for SLURM accounting
create_slurm_database() {
  echo "Creating accounting database"
  SETUP_MYSQL=$(expect -c "
  set timeout 15
  log_file /var/log/provision/setup_mysql.log
  match_max 10000
  spawn sudo mysql -u root -p
  expect \"Enter password:\"
  send \"\r\"
  sleep 1
  expect \"*]>\"
  send \"grant all on slurm_acct_db.* TO 'slurm'@'localhost' identified by 'some_pass' with grant option;\r\"
  sleep 1
  expect \"*]>\"
  send \"create database slurm_acct_db;\r\"
  sleep 1
  expect \"*]>\"
  send \"exit\r\"
  expect eof
  ")
}

# Setup the configuration for slurmdbd to use MariaDB.
create_slurmdbd_config() {
  SLURM_DB_USER=slurm SLURM_DB_PASSWORD=some_pass envsubst < "$SLURMDB_CONFIG_FILE.template" > $SLURMDB_CONFIG_FILE
  chown slurm:slurm $SLURMDB_CONFIG_FILE
  chmod 600 $SLURMDB_CONFIG_FILE
}

# Append the accounting settings to accounting.conf, this file is empty by default and included into
# slurm.conf. This is required for Slurm to enable accounting.
add_accounting_to_slurm_config() {
  cat >> $SLURM_ACCOUNTING_CONFIG_FILE << EOL
# ACCOUNTING
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
AccountingStoragePort=6819
EOL
}

main() {
  echo "[INFO]: Start configuration for SLURM accounting."

  # Start mariadb and check status
  systemctl start mariadb
  systemctl status mariadb

  setup_mariadb
  create_slurm_database

  create_slurmdbd_config
  add_accounting_to_slurm_config

  systemctl enable --now slurmdbd

  # validate_slurm_accounting
  echo "[INFO]: Completed configuration for SLURM accounting."
}

main "$@"
