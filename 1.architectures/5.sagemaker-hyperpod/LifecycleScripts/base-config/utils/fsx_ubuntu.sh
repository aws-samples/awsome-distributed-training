#!/bin/bash

# RETRY CONFIG
ATTEMPTS=6
WAIT=10
FSX_OZFS_EXISTS=$1
FSX_OPENZFS_DNS_NAME="/home"
FSX_L_DNS_NAME="/fsx"
SHARED_USER_FILE="shared_users.txt"

# Function to check mount
check_mount()
{
    local mount_point="$1"
    if mountpoint -q "$mount_point" && touch "$mount_point/.test_write" 2>/dev/null; then
        rm -f "$mount_point/.test_write"
        return 0
    fi
    return 1
}

# Wait for mount (both OpenZFS and FSxL)
wait_for_mount()
{
    local mount_point="$1"
    for ((i=1; i<=$ATTEMPTS; i++)); do
        if check_mount "$mount_point"; then
            echo "Successfully verified mount at $mount_point"
            return 0
        fi
        if [ $i -eq $ATTEMPTS ]; then
            echo "Mount not ready after $((ATTEMPTS * WAIT)) seconds"
            return 1
        fi
        echo "Waiting for FSx mount: $mount_point to be ready... (attempt $i/$ATTEMPTS)"
        sleep $WAIT
    done
}

# Function to setup home directory for a user with OpenZFS
setup_user_home_openzfs()
{
    local username=$1
    
    echo "Setting up OpenZFS home directory for user: $username"
    
    # Create user directory on OpenZFS
    ansible localhost -b -m ansible.builtin.file -a "path='$FSX_OPENZFS_DNS_NAME/$username' state=directory owner=$username group=$username mode=0755"
    
    # Set home directory to /home/username
    ansible localhost -b -m ansible.builtin.user -a "name=$username home='$FSX_OPENZFS_DNS_NAME/$username' move_home=yes"
    echo "Home directory set to $FSX_OPENZFS_DNS_NAME/$username"
    
    # Maintain access to /fsx/username
    if wait_for_mount "$FSX_L_DNS_NAME"; then
        sudo mkdir -p "$FSX_L_DNS_NAME/$username"
        sudo chown "$username:$username" "$FSX_L_DNS_NAME/$username"
    else
        echo "Warning: FSx Lustre mount not available, skipping $FSX_L_DNS_NAME/$username setup"
    fi
}

# Function to setup home directory for a user with FSx Lustre only
setup_user_home_fsx_lustre()
{
    local username=$1
    local fsx_home=$2
    
    echo "Setting up FSx Lustre home directory for user: $username at $fsx_home"
    
    if [ -d "$fsx_home" ]; then
        sudo usermod -d "$fsx_home" "$username"
    elif [ -d "$FSX_L_DNS_NAME" ]; then
        # Create the directory
        sudo mkdir -p "$fsx_home"
        sudo chown "$username:$username" "$fsx_home"
        
        # Try to change home directory with move
        if ! sudo usermod -m -d "$fsx_home" "$username"; then
            echo "Warning: Could not move home directory for $username. Setting home without moving files."
            
            # If user has existing home, copy contents
            if [ -d "/home/$username" ]; then
                sudo rsync -a "/home/$username/" "$fsx_home/"
            fi
            sudo chown -R "$username:$username" "$fsx_home"
            
            sudo usermod -d "$fsx_home" "$username"
        else
            echo "Home directory moved successfully to $fsx_home"
        fi
    fi
}

if [ -z "$FSX_OZFS_EXISTS" ]; then
    echo "Error: Missing parameter. Usage: $0 <1|0> (1 if OpenZFS exists, 0 otherwise)"
    exit 1
fi

# Check if OpenZFS is mounted
if [ $FSX_OZFS_EXISTS -eq 1 ]; then 
    echo "OpenZFS is mounted. Setting up home directories on OpenZFS."
    
    if wait_for_mount "$FSX_OPENZFS_DNS_NAME"; then
        # Setup ubuntu user first
        echo "Setting up home directory for default ubuntu user..."
        setup_user_home_openzfs "ubuntu"
        
        # Process additional users from shared_users.txt if it exists
        if [[ -f $SHARED_USER_FILE ]]; then
            echo "Found $SHARED_USER_FILE, processing additional users..."
            
            while IFS="," read -r username uid home; do
                # Skip empty lines
                if [[ -z "$username" ]]; then
                    continue
                fi
                
                echo "Processing home directory for user: $username"
                setup_user_home_openzfs "$username"
            done < "$SHARED_USER_FILE"
            
            echo "All users from $SHARED_USER_FILE processed successfully"
        else
            echo "No $SHARED_USER_FILE found, only ubuntu user configured"
        fi
    fi
else
    echo "OpenZFS is not mounted. Using FSx Lustre file system as home..."
    
    if ! wait_for_mount "$FSX_L_DNS_NAME"; then
        echo "Warning: FSx mount not available. Exiting."
        exit 1
    fi
    
    # Setup ubuntu user first
    echo "Setting up home directory for default ubuntu user..."
    setup_user_home_fsx_lustre "ubuntu" "$FSX_L_DNS_NAME/ubuntu"
    
    # Process additional users from shared_users.txt if it exists
    if [[ -f $SHARED_USER_FILE ]]; then
        echo "Found $SHARED_USER_FILE, processing additional users..."
        
        while IFS="," read -r username uid home; do
            # Skip empty lines
            if [[ -z "$username" ]]; then
                continue
            fi
            
            echo "Processing home directory for user: $username at $home"
            setup_user_home_fsx_lustre "$username" "$home"
        done < "$SHARED_USER_FILE"
        
        echo "All users from $SHARED_USER_FILE processed successfully"
    else
        echo "No $SHARED_USER_FILE found, only ubuntu user configured"
    fi
fi

echo "Home directory setup completed for all users"