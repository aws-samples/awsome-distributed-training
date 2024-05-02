#!/bin/bash

set -uo pipefail
## NOTE: you must activate the python environment, or make sure the right python is in PATH

# Call PyTorch collective on a single GPU, to force load libnccl.
strace_output=$( strace -e trace=open,openat -e status=successful python ./all_reduce_single_gpu.py 2>&1 )
retval="$?"
[[ "retval" -eq 0 ]] || { echo "$strace_output" ; exit "$retval" ; }

set -e

## strace output expected to contain these lines:
#openat(AT_FDCWD, "/path/to/libxxx.so.*", O_xxx) = <FD>
get_lib() {
    echo "$strace_output" | grep "$1" | cut -d'"' -f 2
}

set +o pipefail

LIB_PATH="$(get_lib libnccl.so)"
LIB_VERSION=$(strings "${LIB_PATH}" | grep -m1 '^NCCL version' | cut -d' ' -f3 | cut -d'+' -f1)
LIB_NAME=NCCL
[[ ! "$LIB_VERSION" == "" ]] || LIB_VERSION="not found"
echo "${LIB_NAME} version :" "$LIB_VERSION"
echo "${LIB_NAME} path    :" "$(realpath ${LIB_PATH})"

LIB_PATH=$(get_lib libnccl-net.so)
LIB_VERSION=$(strings "${LIB_PATH}" | grep -m1 '^NET/OFI Initializing aws-ofi-nccl ' | cut -d' ' -f4 | cut -d'-' -f1)
LIB_NAME=aws-ofi-nccl
[[ ! "$LIB_VERSION" == "" ]] || LIB_VERSION="not found"
echo "${LIB_NAME} version :" "$LIB_VERSION"
echo "${LIB_NAME} path    :" "$(realpath ${LIB_PATH})"

LIB_PATH=$(get_lib libfabric.so)
LIB_VERSION=$(strings "${LIB_PATH}" | grep -m1 'amzn')
LIB_NAME=libfabric
[[ ! "$LIB_VERSION" == "" ]] || LIB_VERSION="not found"
echo "${LIB_NAME} version :" "$LIB_VERSION"
echo "${LIB_NAME} path    :" "$(realpath ${LIB_PATH})"

echo "efa kernel module :" $(modinfo -F version efa 2> /dev/null)

echo
echo "cat /opt/amazon/efa_installed_packages:"
cat /opt/amazon/efa_installed_packages
echo
