#!/bin/bash

# Wait for FSx to be properly mounted (timeout after 60 seconds)
ATTEMPTS=6
WAIT=10
for ((i=1; i<=ATTEMPTS; i++)); do
    if mountpoint -q "/fsx" && touch /fsx/.test_write 2>/dev/null; then
        rm -f /fsx/.test_write
        break
    fi
    if [ $i -eq $ATTEMPTS ]; then
        echo "FSx mount not ready after $((ATTEMPTS * WAIT)) seconds"
        exit 1
    fi
    sleep $WAIT
done

# move the ubuntu user to the shared /fsx filesystem
if [ -d "/fsx/ubuntu" ]; then
    sudo usermod -d /fsx/ubuntu ubuntu
elif [ -d "/fsx" ]; then
    sudo usermod -m -d /fsx/ubuntu ubuntu
fi
