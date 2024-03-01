#!/bin/bash

# Credits: Sean Smith, Ben Snyder, Shubham Arora

# Consistent times across cluster is crucial for distributed workload. For example, torchrun fails
# fast when it detects 5 seconds (or more) time differences among workers.
#
# Check the time of all compute nodes as follows:
#
#     srun -N <NUM_OF_NODES> bash -c 'echo "$(hostname): $(date)"' | sort -k2,3
#
#
# To avoid time drifts, enable time synchornization (ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/set-time.html).

set -exuo pipefail

FILE=/etc/chrony/chrony.conf

line='server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4'
grep "^${line}$" $FILE &> /dev/null \
    && echo Line \"${line}\" already exists in $FILE \
    || sed -i \
    "/\# See http:\/\/www.pool.ntp.org\/join.html for more information./a ${line}" \
    $FILE

line='pool time.aws.com iburst'
grep "^${line}$" $FILE &> /dev/null \
    && echo Line \"${line}\" already exists in $FILE \
    || sed -i \
    "/^server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4$/a ${line}" \
    $FILE

systemctl enable --now chrony
