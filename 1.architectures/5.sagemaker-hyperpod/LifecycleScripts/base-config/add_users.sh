#!/bin/bash
# Creates users from `shared_users.txt` file
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

# takes in username and uid as parameters
# if user with username and uid does not exists,
# creates user with uid and creates a directory for user at /home/$username
create_user() {
  local username=$1
  local uid=$2
  local home=$3

  # check if username already exists
  if id -u "$username"  >/dev/null 2>&1; then
    echo "User $username already exists. Skipping..."
    return
  fi

  # check if uid already exists
  if getent passwd "$uid" >/dev/null 2>&1; then
    echo "UID $uid is already in use. Skipping adding user: $username..."
    return
  fi
  
  # create user with uid and home directory
  if useradd -m $username --uid $uid -d "${home}"; then
    echo "Created user $username with uid $uid and home $home."
  else
    echo "Failed to create user $username with uid $uid"
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

  while IFS="," read -r username uid; do
    echo "Requested create user: $username with uid: $uid"
    create_user "$username" "$uid"
  done < $SHARED_USER_FILE
}

main "$@"

