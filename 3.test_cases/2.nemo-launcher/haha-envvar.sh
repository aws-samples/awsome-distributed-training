export NEMO_VERSION=23.11
export REPO=aws-nemo-megatron
export TAG=$NEMO_VERSION
export TARGET_PATH=/fsx/nemo-launcher-$NEMO_VERSION   # must be a shared filesystem
export TEST_CASE_PATH=/fsx/awsome-distributed-training/3.test_cases/2.nemo-launcher  # where you copy the test case or set to your test case path
export ENROOT_IMAGE=/fsx/${REPO}_${TAG}.sqsh
export BMK_MODE=1
env | egrep 'NEMO_VERSION|REPO|TAG|TARGET_PATH|TEST_CASE_PATH|ENROOT_IMAGE|BMK_MODE'
