#!/bin/bash
# Creates/Deletes users from `shared_users.txt` file
# each line in the `shared_users.txt` file should be of the format:
# ```
# username1,uid1,/fsx/username1
# username2,uid2,/fsx/username2
# ```
# 
# The script should be run as root user
# see `shared_users_sample.txt` for an example

set -e
set -x

SHARED_USER_FILE="shared_users.txt"


delete_user() {
  local username=$1
  local uid=$2
  local fsx_home=$3

# Determine home directory based on OpenZFS filesystem availability
  if df -h | grep -q "/home"; then
    echo "OpenZFS is mounted at /home"
    local home="/home/$username"

    # Create user with OpenZFS home
    if userdel -r "$username"; then
      echo "Deleted user $username."

      # Make sure fsxl directory still exists and is accessible
      sudo rf -rf  $fsx_home
    else
      echo "Failed to delete user $username with uid $uid"
    fi
  else
    echo "OpenZFS is not mounted. Using FSxL file system"
    # delete user with uid and directory
    if userdel -r "$username"; then
      echo "Deleted user $username with uid $uid and home $home."
    else
      echo "Failed to delete user $username with uid $uid"
    fi
  fi
}



main() {
  if [[ ! -f $SHARED_USER_FILE ]]; then
    echo "Shared user file $SHARED_USER_FILE does not exist. Skipping adding users."
    exit 0
  fi

  if [[ ! -s $SHARED_USER_FILE ]]; then
    echo "Shared user file $SHARED_USER_FILE is empty. Skipping adding users."
    exit 0
  fi

  while IFS="," read -r username uid home; do
    echo "Requested create user: $username with uid: $uid and home directory: $home"
    delete_user "$username" "$uid" "$home"
  done < $SHARED_USER_FILE
}

main "$@"

