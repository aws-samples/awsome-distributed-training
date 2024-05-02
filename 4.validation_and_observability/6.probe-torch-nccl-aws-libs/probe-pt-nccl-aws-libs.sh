#!/bin/bash

set -uo pipefail
## NOTE: you must activate the python environment, or make sure the right python is in PATH

# Call PyTorch collective on a single GPU, to force load libnccl.
strace_output=$( strace -e trace=open,openat -e status=successful python ./all_reduce_single_gpu.py 2>&1 )
retval="$?"
[[ "retval" -eq 0 ]] || { echo "$strace_output" ; exit "$retval" ; }

set -e

## strace output expected to contain these lines:
#openat(AT_FDCWD, "/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/nccl/lib/libnccl.so.2", O_RDONLY|O_CLOEXEC) = 3
#openat(AT_FDCWD, "/opt/aws-ofi-nccl/lib/libnccl-net.so", O_RDONLY|O_CLOEXEC) = 85
declare -a OPENED_LIB=( $(echo "$strace_output" | egrep 'libnccl.so|libnccl-net.so' | cut -d',' -f 2 | tr -d '"' ) )

set +o pipefail
NCCL_VERSION=$(strings "${OPENED_LIB[0]}" | grep -m1 '^NCCL version' | cut -d' ' -f3 | cut -d'+' -f1)
[[ ! "$NCCL_VERSION" == "" ]] || NCCL_VERSION="not found"
echo "NCCL version :" "$NCCL_VERSION"
echo "NCCL path    :" "$(realpath ${OPENED_LIB[0]})"

AWS_OFI_NCCL_VERSION=$(strings "${OPENED_LIB[1]}" | grep -m1 '^NET/OFI Initializing aws-ofi-nccl ' | cut -d' ' -f4 | cut -d'-' -f1)
[[ ! "$AWS_OFI_NCCL_VERSION" == "" ]] || AWS_OFI_NCCL_VERSION="not found"
echo "aws-ofi-nccl version :" "$AWS_OFI_NCCL_VERSION"
echo "aws-ofi-nccl path    :" "$(realpath ${OPENED_LIB[1]})"
