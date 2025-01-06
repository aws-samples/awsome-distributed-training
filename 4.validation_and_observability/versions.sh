#!/bin/bash

echo ""
echo "Versions:"

echo ""
echo "Linux family:"
uname

echo ""
echo "Linux Kernel version:"
uname -r

echo ""
echo "nvidia-smi:"
which nvidia-smi
if [ "$?" == "0" ]; then
	echo ""
	echo "NVIDIA versions:"
	nvidia-smi --version | grep DRIVER
	nvidia-smi --version | grep CUDA

        NCCL_LIB=$(ls /usr/local/cuda/lib/libnccl.so.*.*.*)
	search="so."
	NCCL_VERSION=${NCCL_LIB#*$search}
	echo "NCCL version: $NCCL_VERSION"

	OFI_NCCL_LIB=$(strings /opt/aws-ofi-nccl/lib/libnccl-net.so | grep "Initializing aws-ofi-nccl")
	OFI_NCCL_VERSION=$(echo $OFI_NCCL_LIB | cut -d ' ' -f 4)
	echo "AWS OFI NCCL version: $OFI_NCCL_VERSION"
else
	echo "not present"
fi

echo ""
echo "Lustre client version:"
LUSTRE_CLIENT_VERSION="not found"
which yum
if [ "$?" == "0" ]; then
	LUSTRE_CLIENT_VERSION=$(yum list lustre-client | grep lustre-client | awk '{print $2}')
else
	LUSTRE_CLIENT_VERSION=$(apt list lustre-client | grep lustre-client | cut -d ' ' -f 2)
fi
echo $LUSTRE_CLIENT_VERSION

echo ""
if [ -f /opt/amazon/efa_installed_packages ]; then
	echo "EFA Installer version:"
	EFA_LIBS=($(cat /opt/amazon/efa_installed_package))
	EFA_INSTALLER_VERSION=${EFA_LIBS[-1]}
	echo $EFA_INSTALLER_VERSION

	echo ""
	echo "Libfabric version:"
	LIBFABRIC_VERSION=$(/opt/amazon/efa/bin/fi_info --version | grep libfabric: | cut -d ' ' -f 2)
	echo $LIBFABRIC_VERSION

else
	echo "EFA Installer not found"
fi	

echo ""
