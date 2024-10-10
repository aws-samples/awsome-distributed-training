# specify which CUDA version you are using
SMP_CUDA_VER=12.1

directory="$(pwd)/miniconda3"

if [ ! -d "$directory" ]; then
    echo "Miniconda does not exist.Downloading......"
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    chmod +x Miniconda3-latest-Linux-x86_64.sh
    ./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3
else
    echo "Miniconda exists...."
fi

source ./miniconda3/bin/activate

export ENV_PATH=./miniconda3/envs/smpv2

conda create -p ${ENV_PATH} -y python=3.10 -c conda-forge

conda activate ${ENV_PATH}

conda install -p ${ENV_PATH} -y \
    ./bin/aws-ofi-nccl-1.7.4-aws_0.tar.bz2 \
    ./bin/hwloc-2.9.2-h2bc3f7f_0.tar.bz2

# Install SMP V2 pytorch. We will install SMP with pytorch 2.2
conda install -p ${ENV_PATH} -y mkl=2023.1.0 "requests==2.28.2" "filelock==3.9.0" "sympy==1.12" \
  pytorch="2.2.0=sm_py3.10_cuda12.1_cudnn8.9.5_nccl_pt_2.2_tsm_2.3_cuda12.1_0" packaging --override-channels \
  -c https://sagemaker-distributed-model-parallel.s3.us-west-2.amazonaws.com/smp-v2/ \
  -c pytorch -c numba/label/dev \
  -c pytorch-nightly -c nvidia -c conda-forge

# Install dependencies of the script as below
python -m pip install --no-cache-dir -U \
    "transformers==4.37.1" \
    "accelerate==0.28.0" \
    "triton==2.2.0" \
    "SentencePiece==0.1.99" \
    "datasets==2.16.1" \
    "expecttest" \
    "parameterized==0.9.0" \
    "protobuf==3.20.3" \
    "pytest-repeat==0.9.1" \
    "pytest==7.4.0" \
    "tensorboard==2.13.0" \
    "tqdm==4.65.0"

pip install megatron-core==0.5.0

pip uninstall -y ninja && pip install ninja

MAX_JOBS=$(nproc) pip install flash-attn==2.3.3 --no-build-isolation

# Install SMDDP

SMDDP_WHL="smdistributed_dataparallel-2.2.0-cp310-cp310-linux_x86_64.whl" \
  && wget -q https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.2.0/cu121/2024-03-04/${SMDDP_WHL} \
  && pip install --force ${SMDDP_WHL} \
  && rm ${SMDDP_WHL}


if [ $SMP_CUDA_VER == "11.8" ]; then
    # cuDNN installation for TransformerEngine installation for cuda11.8
    wget https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && tar xf cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && sudo rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
        && sudo cp ./cudnn-linux-x86_64-8.9.5.30_cuda11-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
        && sudo cp ./cudnn-linux-x86_64-8.9.5.30_cuda11-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
        && rm -rf cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && rm -rf cudnn-linux-x86_64-8.9.5.30_cuda11-archive/
else
    # cuDNN installation for TransformerEngine installation for cuda12.1
    wget https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && tar xf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && sudo rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
        && sudo cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
        && sudo cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
        && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive/
fi

# TransformerEngine installation
export CUDA_HOME=/usr/local/cuda-$SMP_CUDA_VER
export CUDNN_PATH=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_LIBRARY=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_INCLUDE_DIR=/usr/local/cuda-$SMP_CUDA_VER/include
export PATH=/usr/local/cuda-$SMP_CUDA_VER/bin:$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-$SMP_CUDA_VER/lib

pip install git+https://github.com/NVIDIA/TransformerEngine.git@v1.2.1
