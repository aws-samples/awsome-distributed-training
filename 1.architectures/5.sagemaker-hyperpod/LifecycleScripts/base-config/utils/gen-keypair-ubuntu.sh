#!/bin/bash

set -exuo pipefail

SHARED_USER_FILE="shared_users.txt"

# Function to setup SSH keys for a single user
setup_user_ssh() {
    local username=$1
    local fsx_home=$2
    
    echo "Setting up SSH keys for user: $username"
    
    local FSX_DIR="$fsx_home"
    local FSX_OZFS_DIR="/home/$username"
    
    # Create .ssh directory on FSx
    mkdir -p "$FSX_DIR/.ssh"
    
    # Creating symlink between /fsx/username/.ssh and /home/username/.ssh (if OpenZFS is mounted)
    if [ -d "$FSX_OZFS_DIR" ]; then
        if [ -L "$FSX_OZFS_DIR/.ssh" ]; then
            echo "$FSX_OZFS_DIR/.ssh is already a symbolic link"
        elif [ -e "$FSX_OZFS_DIR/.ssh" ]; then
            echo "Removing existing $FSX_OZFS_DIR/.ssh and creating symbolic link..."
            rm -rf "$FSX_OZFS_DIR/.ssh"
            ansible localhost -b -m ansible.builtin.file -a "src='$FSX_DIR/.ssh' dest='$FSX_OZFS_DIR/.ssh' state=link force=yes"
        else
            echo "Linking $FSX_DIR/.ssh to $FSX_OZFS_DIR/.ssh..."
            ansible localhost -b -m ansible.builtin.file -a "src='$FSX_DIR/.ssh' dest='$FSX_OZFS_DIR/.ssh' state=link force=yes"
        fi
    fi
    
    cd "$FSX_DIR/.ssh"
    
    # Check if id_rsa exists
    if [ ! -f id_rsa ]; then
        GENERATE_KEYPAIR=1
    else
        GENERATE_KEYPAIR=0
        # Check if id_rsa.pub exists in authorized_keys
        if ! grep -qF "$(cat id_rsa.pub)" authorized_keys 2>/dev/null; then
            # If not, add the public key to authorized_keys
            cat id_rsa.pub >> authorized_keys
        fi
    fi
    
    if [[ $GENERATE_KEYPAIR == 1 ]]; then
        echo "Generate a new keypair for $username..."
        ssh-keygen -t rsa -b 4096 -q -f id_rsa -N "" 2>/dev/null || true
        cat id_rsa.pub >> authorized_keys
    else
        echo "Use existing keypair for $username..."
    fi
    
    # Set permissions for the ssh keypair
    ansible localhost -m ansible.builtin.file -a "path=$FSX_DIR/.ssh/authorized_keys state=touch"
    ansible localhost -b -m ansible.builtin.file -a "path='$FSX_DIR/.ssh/id_rsa' owner=$username group=$username mode=0600"
    ansible localhost -b -m ansible.builtin.file -a "path='$FSX_DIR/.ssh/id_rsa.pub' owner=$username group=$username mode=0644"
    ansible localhost -b -m ansible.builtin.file -a "path='$FSX_DIR/.ssh/authorized_keys' owner=$username group=$username mode=0600"
    
    # Set permissions for the .ssh directory
    chmod 700 "$FSX_DIR/.ssh"
    
    # Change ownership to the user
    chown -R "$username:$username" "$FSX_DIR/.ssh"
    
    echo "SSH setup completed for user: $username"
}

# Always setup ubuntu user first
echo "Setting up SSH keys for default ubuntu user..."
setup_user_ssh "ubuntu" "/fsx/ubuntu"

# Process additional users from shared_users.txt if it exists
if [[ -f $SHARED_USER_FILE ]]; then
    echo "Found $SHARED_USER_FILE, processing additional users..."
    
    while IFS="," read -r username uid home; do
        # Skip empty lines
        if [[ -z "$username" ]]; then
            continue
        fi
        
        echo "Processing user: $username with home: $home"
        setup_user_ssh "$username" "$home"
    done < "$SHARED_USER_FILE"
    
    echo "All users from $SHARED_USER_FILE processed successfully"
else
    echo "No $SHARED_USER_FILE found, only ubuntu user configured"
fi

echo "SSH key generation completed for all users"