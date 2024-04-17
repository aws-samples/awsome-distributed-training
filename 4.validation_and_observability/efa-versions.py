#!/usr/bin/python

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import subprocess
import re
from prettytable import PrettyTable

def get_efa_installer_version():
    try:
        version = subprocess.check_output(['cat', '/opt/amazon/efa_installed_packages'])
        version = version.decode('utf-8')
        version = re.search(r'# EFA installer version: (\d+\.\d+\.\d+)', version).group(1)
        return version
    except Exception as e:
        print(f'Error: {e}')
        return None
    
def get_nccl_version():
    try:
        version = subprocess.check_output(['locate', 'nccl'])
        version = version.decode('utf-8')
        version = re.search(r'/usr/local/cuda-12.2/lib/libnccl.so.(\d+\.\d+\.\d+)', version).group(1)
        return version
    except Exception as e:
        print(f'Error: {e}')
        return None
    
def get_aws_ofi_nccl_version():
    try:
        version = subprocess.check_output(['strings', '/opt/aws-ofi-nccl/lib/libnccl-net.so'])
        version = version.decode('utf-8')
        version = re.search(r'NET/OFI Initializing aws-ofi-nccl (\d+\.\d+\.\d+-aws)', version).group(1)
        return version
    except Exception as e:
        print(f'Error: {e}')
        return None
    
def get_cuda_driver_version():
    try:
        version = subprocess.check_output(['nvidia-smi', '--query-gpu=driver_version', '--format=csv,noheader'])
        version = version.decode('utf-8')
        version = re.search(r'(\d+\.\d+\.\d+)', version).group(1)
        return version
    except Exception as e:
        print(f'Error: {e}')
        return None

    
if __name__ == '__main__':
    efa_installer_version = get_efa_installer_version()
    nccl_version = get_nccl_version()
    aws_ofi_nccl_version = get_aws_ofi_nccl_version()
    cuda_driver_version = get_cuda_driver_version()

    table = PrettyTable(["Package", "Version"])

    table.add_row(["EFA installer version:", efa_installer_version])
    table.add_row(['NCCL Version', nccl_version])
    table.add_row(["AWS OFI NCCL version:", aws_ofi_nccl_version])
    table.add_row(["CUDA Driver:", cuda_driver_version])
    
    table.align = "l"  # Align the columns to the left
    table.padding_width = 2  # Set the padding width for each cell
    table.hrules = 1  # Add horizontal rules between rows

    print(table)