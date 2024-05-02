# Runtime sanity checks: which NCCL is loaded by PyTorch

The scripts in this folder disambiguate the exact NCCL libraries that a PyTorch application actually
uses, in the presence of potentially multiple installed versions.

## 1. Motivation

Knowing the precise NCCL version is important for performance tuning. The exact NCCL library used by
PyTorch depends on how the PyTorch was installed. On DLAMI which pre-installs several different
versions of NCCL, it is misleading to assume that PyTorch will use one of these libraries.

Suppose your EC2 instance runs DLAMI `Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 20.04)
20240314`. This AMI provides `libnccl.so` version 2.18.5 under `/usr/lib/cuda` ([Section
3.1](#31-system-wide-nccl-provided-by-dlami)). You then install PyTorch to a conda or a regular
Python virtual environment, using the [prebuilt PyTorch
installer](https://pytorch.org/get-started/locally/) from the pytorch
[channel](https://anaconda.org/pytorch/repo) or [PyPI](https://pypi.org/project/torch/),
respectively. We can easily observe that our PyTorch installs its own NCCL and CUDA runtime.

```console
$ conda list | egrep 'torch|nvidia'
nvidia-cublas-cu12        12.1.3.1                 pypi_0    pypi
nvidia-cuda-cupti-cu12    12.1.105                 pypi_0    pypi
nvidia-cuda-nvrtc-cu12    12.1.105                 pypi_0    pypi
nvidia-cuda-runtime-cu12  12.1.105                 pypi_0    pypi
nvidia-cudnn-cu12         8.9.2.26                 pypi_0    pypi
nvidia-cufft-cu12         11.0.2.54                pypi_0    pypi
nvidia-curand-cu12        10.3.2.106               pypi_0    pypi
nvidia-cusolver-cu12      11.4.5.107               pypi_0    pypi
nvidia-cusparse-cu12      12.1.0.106               pypi_0    pypi
nvidia-nccl-cu12          2.19.3                   pypi_0    pypi
nvidia-nvjitlink-cu12     12.4.99                  pypi_0    pypi
nvidia-nvtx-cu12          12.1.105                 pypi_0    pypi
torch                     2.2.1                    pypi_0    pypi
torchaudio                2.2.1                    pypi_0    pypi
torchvision               0.17.1                   pypi_0    pypi
```

We can verify that our PyTorch indeed loads its NCCL version `(2, 19, 3)` from the conda
environment, instead of the system-wide version `2.18.5`.

```console
# Library search paths, without conda environment
$ env | grep ^LD
LD_LIBRARY_PATH=/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:/usr/local/cuda-12.1/lib:/usr/local/cuda-12.1/lib64:/usr/local/cuda-12.1:/usr/local/cuda-12.1/targets/x86_64-linux/lib/:/usr/local/cuda-12.1/extras/CUPTI/lib64:/usr/local/lib:/usr/lib

# Print version of the system-wide NCCL, pre-installed with DLAMI
$ strings /usr/local/cuda/lib/libnccl.so | grep -m1 -i '^NCCL version .*\+cuda.*$'
NCCL version 2.18.5+cuda12.2

# Activate the conda environment where PyTorch is located.
$ source miniconda3/bin/activate ./conda_env_pytorch/

# Conda environment does not change the library search paths.
(conda_env_name) $ env | grep ^LD
LD_LIBRARY_PATH=/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:/usr/local/cuda-12.1/lib:/usr/local/cuda-12.1/lib64:/usr/local/cuda-12.1:/usr/local/cuda-12.1/targets/x86_64-linux/lib/:/usr/local/cuda-12.1/extras/CUPTI/lib64:/usr/local/lib:/usr/lib

# Query the nccl version to PyTorch
(conda_env_pytorch) $ python -c 'import torch; print(f"{torch.cuda.nccl.version()=}")'
torch.cuda.nccl.version()=(2, 19, 3)

# Similar to above, but also pinpoint the exact `libnccl.so` file.
(conda_env_name) $ LD_DEBUG=libs python -c 'import torch; print(f"{torch.cuda.nccl.version()=}")' 2>&1 | egrep 'torch.cuda.nccl.version|libnccl.so'
     47352:     find library=libnccl.so.2 [0]; searching
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cublas/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cuda_cupti/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cuda_nvrtc/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cuda_runtime/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cudnn/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cufft/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/curand/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cusolver/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/cusparse/lib/libnccl.so.2
     47352:       trying file=/fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/nccl/lib/libnccl.so.2
     47352:     calling init: /fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/nccl/lib/libnccl.so.2
torch.cuda.nccl.version()=(2, 19, 3)
     47352:     calling fini: /fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/torch/lib/../../nvidia/nccl/lib/libnccl.so.2 [0]
```

By now, hopefully you're convinced on the need for a runtime probe to pinpoint the version of NCCL
loaded by PyTorch.

## 2. Howto

Pre-requisites:

- one GPU.
- the command `python` will invoke the binary from your PyTorch environment. Typically, you must
  activate your environment (conda, virtual env, etc.).

Direct invocation: `./probe-pt-nccl-aws-libs.sh`

Via Slurm: `srun -l -N1 ./probe-pt-nccl-aws-libs.sh`

```console
$ srun -l -N1 ./probe-pt-nccl-aws-libs.sh
0: NCCL version : 2.19.3
0: NCCL path    : /fsx/marcverd/awsome-distributed-training/3.test_cases/10.FSDP/conda_env_pytorch/lib/python3.10/site-packages/nvidia/nccl/lib/libnccl.so.2
0: aws-ofi-nccl version : 1.7.4
0: aws-ofi-nccl path    : /opt/aws-ofi-nccl/lib/libnccl-net.so.0.0.0
```

## 3. Appendix

### 3.1. System-wide NCCL provided by DLAMI

See the [DLAMI release
notes](https://aws.amazon.com/releasenotes/aws-deep-learning-base-gpu-ami-ubuntu-20-04/) for the
versions of pre-installed [CUDA runtime](https://docs.nvidia.com/cuda/),
[NCCL](https://github.com/NVIDIA/nccl), and [aws-ofi-nccl](https://github.com/aws/aws-ofi-nccl).

Optionally, follow below steps to validate the versions on a live EC2 instance.

```console
# DLAMI provides multiple versions of CUDA runtime
$ ls -ald /usr/local/cuda-*/ /usr/local/cuda
lrwxrwxrwx  1 root root   21 Mar 14 22:22 /usr/local/cuda -> /usr/local/cuda-12.1/
drwxr-xr-x 17 root root 4096 Mar 14 22:01 /usr/local/cuda-11.7/
drwxr-xr-x 19 root root 4096 Mar 14 22:19 /usr/local/cuda-11.8/
drwxr-xr-x 19 root root 4096 Mar 14 22:13 /usr/local/cuda-12.0/
drwxr-xr-x 19 root root 4096 Mar 14 22:25 /usr/local/cuda-12.1/
drwxr-xr-x 19 root root 4096 Mar 14 22:07 /usr/local/cuda-12.2/

# Each CUDA version brings its own NCCL library
$ find /usr/local/cuda-* -name 'libnccl.so'
/usr/local/cuda-11.7/lib/libnccl.so
/usr/local/cuda-11.8/lib/libnccl.so
/usr/local/cuda-12.0/lib/libnccl.so
/usr/local/cuda-12.1/lib/libnccl.so
/usr/local/cuda-12.2/lib/libnccl.so

# Print NCCL versions
$ find /usr/local/cuda-* -name 'libnccl.so' | xargs -n1 -I{} bash -c  "echo -n {} '=> ' ; strings {} | grep '^NCCL version' -m1"
/usr/local/cuda-11.7/lib/libnccl.so => NCCL version 2.16.2+cuda11.8
/usr/local/cuda-11.8/lib/libnccl.so => NCCL version 2.16.2+cuda11.8
/usr/local/cuda-12.0/lib/libnccl.so => NCCL version 2.18.5+cuda12.2
/usr/local/cuda-12.1/lib/libnccl.so => NCCL version 2.18.5+cuda12.2
/usr/local/cuda-12.2/lib/libnccl.so => NCCL version 2.18.5+cuda12.2

# Print aws-ofi-nccl version
$ strings /opt/aws-ofi-nccl/lib/libnccl-net.so | grep '^NET/OFI Initializing aws-ofi-nccl .*-aws'
NET/OFI Initializing aws-ofi-nccl 1.7.4-aws
```

### 3.2. Check other library versions

Please refer to `4.validation_and_observability/1.pytorch-env-validation` to probe additional
library versions used by PyTorch.
