#!/bin/bash

####################################################################################################
# [20240308] DEPRECATION NOTE: HP DLAMI has setup chrony automatically, hence this script is no
# longer needed for LCC. It's left here as hotfix for older cluster.
####################################################################################################

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


################################################################################
# 000: Probe the DLAMI capability (to aid troubleshooting). This section can be
# commented out entirely.
################################################################################
if systemctl is-active --quiet chrony \
    && ! systemctl show chrony | grep '^NetworkNamespacePath=/var/run/netns/sagemaker_agent_namespace$' &> /dev/null; then
  echo "Cap checks: DLAMI starts chrony without network namespace..."
  exit 0
elif systemctl is-active --quiet chrony \
    && systemctl show chrony | grep '^NetworkNamespacePath=/var/run/netns/sagemaker_agent_namespace$' &> /dev/null; then
  echo "Cap checks: DLAMI starts chrony with network namespace..."
else
  echo 'Cap checks: DLAMI does not start chrony. To apply full customizations...'
fi


################################################################################
# 010: Apply whatever missing fixes. And always restart chrony in the end.
################################################################################
# Try to add aws local time endpoint to chrony
FILE=/etc/chrony/chrony.conf
line='server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4'
grep "^${line}$" $FILE &> /dev/null \
    && echo Line \"${line}\" already exists in $FILE \
    || sed -i \
    "/\# See http:\/\/www.pool.ntp.org\/join.html for more information./a ${line}" \
    $FILE

# Try to disable network namespace to chrony
sed -i \
  's|^\(NetworkNamespacePath=/var/run/netns/sagemaker_agent_namespace\)$|## Network namespace disabled by LCC setup_timesync.sh\n# \1|g' \
  /lib/systemd/system/chrony.service

systemctl daemon-reload
systemctl enable chrony
systemctl restart chrony

systemctl is-active chrony \
  || { echo chrony still not started, exiting... ; exit -1 ; }

! systemctl show chrony | grep '^NetworkNamespacePath=/var/run/netns/sagemaker_agent_namespace$' \
  || { echo chrony still has network namespace, exiting... ; exit -2 ; }

# Show final states
echo ; systemctl status --no-pager chrony
echo ; cat /lib/systemd/system/chrony.service
echo ; cat /etc/chrony/chrony.conf
