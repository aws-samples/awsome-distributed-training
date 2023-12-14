#!/bin/bash
# Creates users from `shared_users.txt` file
# each line in the `shared_users.txt` file should be of the format:
# ```
# username1,uid1,homepath
# username2,uid2,homepath
# ```
#
# The script should be run as root user
# see `shared_users_sample.txt` for an example

set -e
set -x

SHARED_USER_FILE="shared_users.txt"

# takes in username, uid and the homepath as parameters
# if user with username and uid does not exists,
# creates user with uid and creates a directory for user at homepath
create_user() {
  local username=$1
  local uid=$2
  local homepath=$3

  # check if username already exists
  if id -u "$username" >/dev/null 2>&1; then
    echo "User $username already exists. Skipping..."
    return
  fi

  # check if uid already exists
  if getent passwd "$uid" >/dev/null 2>&1; then
    echo "UID $uid is already in use. Skipping adding user: $username..."
    return
  fi

  bash_path=$(which bash)
  useradd -m "$username" --uid "$uid" -d "$homepath" --shell "$bash_path" || (echo "Failed to create user $username with uid $uid" && return)

  usermod -aG sudo "$username"

  if getent group ubuntu >/dev/null; then
    echo "Group ubuntu exists."
    usermod -aG ubuntu "$username"
  else
    echo "Group ubuntu does not exist."
  fi

  if getent group docker >/dev/null; then
    echo "Group docker exists."
    usermod -aG docker "$username"
  else
    echo "Group docker does not exist."
  fi

  if test ! -e "$homepath/.ssh/id_rsa"; then
    echo "No ssh keygen, creating a new one"
    mkdir -p "$homepath/.ssh/"

    ssh-keygen -t rsa -q -f "$homepath/.ssh/id_rsa" -N ""
    cat "$homepath/.ssh/id_rsa.pub" >> "$homepath/.ssh/authorized_keys"
    chown -R "$username" "$homepath/.ssh"
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

  while IFS="," read -r username uid homepath; do
    echo "Requested create user: $username with uid '$uid' and '$homepath'"
    create_user "$username" "$uid" "$homepath"
  done <$SHARED_USER_FILE
}

main "$@"
