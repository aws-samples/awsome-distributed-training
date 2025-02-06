#!/bin/bash

if [ -f /etc/os-release ]; then
	echo ""
	echo "OS info:"
	cat /etc/os-release | head -n 4
fi

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
	NVIDIA_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader --id=0 | grep '[0-9].*')
	CUDA_VERSION_SUPPORT=$(nvidia-smi --version | grep CUDA | cut -d ':' -f 2 | xargs)
	CUDA_VERSION_CURRENT=$(nvcc --version | sed -n 's/^.*release \([0-9]\+\.[0-9]\+\).*$/\1/p' | grep '[0-9].*')
        CUDA_DEFAULT_PATH=$(ls -alh /usr/local | awk '{print $9 $10 $11}' | grep cuda | grep \>)
	echo "Driver version                     : $NVIDIA_DRIVER"
	echo "CUDA version support               : $CUDA_VERSION_SUPPORT"
	echo "CUDA version                       : $CUDA_VERSION_CURRENT"
	echo "CUDA default path                  : /usr/local/$CUDA_DEFAULT_PATH"


	CUDA_VERSIONS=$(ls -alh /usr/local | awk '{print $9 $10 $11}' | grep cuda | grep -v \>)
	for v in $CUDA_VERSIONS ; do
        	NCCL_LIB=$(ls /usr/local/$v/lib/libnccl.so.*.*.* 2>/dev/null)
		search="so."
		NCCL_VERSION=${NCCL_LIB#*$search}
		echo "NCCL version (for $v)       : $NCCL_VERSION"
	done

	OFI_NCCL_LIB=$(strings /opt/aws-ofi-nccl/lib/libnccl-net.so | grep "Initializing aws-ofi-nccl")
	OFI_NCCL_VERSION=$(echo $OFI_NCCL_LIB | cut -d ' ' -f 4)
	echo "AWS OFI NCCL version               : $OFI_NCCL_VERSION"

	if [ -f /usr/local/cuda/gds/tools/gdscheck ]; then
		echo ""
		echo "NVIDIA GDS:"
		/usr/local/cuda/gds/tools/gdscheck -v
	fi
else
	echo "not present"
fi

echo ""
LUSTRE_CLIENT_VERSIONS_INSTALLED="not found"
which yum
if [ "$?" == "0" ]; then
	LUSTRE_CLIENT_VERSIONS_INSTALLED=$(yum list lustre-client | grep lustre-client | awk '{print $2}')
else
	LUSTRE_CLIENT_VERSIONS_INSTALLED=$(apt list lustre-client | grep lustre-client | cut -d ' ' -f 2)
fi
LUSTRE_CLIENT_VERSION_LOADED=$(modinfo lustre | grep 'version:' | head -n 1 | awk '{print $2}')
echo "Lustre client versions installed: "
echo "$LUSTRE_CLIENT_VERSIONS_INSTALLED"
echo "Lustre client version loaded       : $LUSTRE_CLIENT_VERSION_LOADED"

echo ""
if [ -f /opt/amazon/efa_installed_packages ]; then
	EFA_LIBS=($(cat /opt/amazon/efa_installed_packages))
	EFA_INSTALLER_VERSION=${EFA_LIBS[-1]}
	echo "EFA version                        : $EFA_INSTALLER_VERSION"

	LIBFABRIC_VERSION=$(/opt/amazon/efa/bin/fi_info --version | grep libfabric: | cut -d ' ' -f 2)
	echo "Libfabric version                  : $LIBFABRIC_VERSION"

else
	echo "EFA Installer not found"
fi

echo ""
