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

conda create -p ${ENV_PATH} python=3.10

conda activate ${ENV_PATH}


# Install OFI nccl 
conda install "aws-ofi-nccl==1.8.1-aws" packaging --override-channels \
  -c https://aws-ml-conda.s3.us-west-2.amazonaws.com \
  -c pytorch -c numba/label/dev \
  -c nvidia \
  -c conda-forge \

conda install -c conda-forge mkl=2023.1.0
conda install "requests==2.28.2"
conda install "filelock==3.9.0"
conda install "sympy==1.12"

# Install SMP V2 pytorch. We will install SMP with pytorch 2.2
conda install pytorch="2.2.0=sm_py3.10_cuda12.1*smp_2.3.1*" --override-channels \
  -c https://sagemaker-distributed-model-parallel.s3.us-west-2.amazonaws.com/smp-v2/ \
  -c pytorch -c numba/label/dev \
  -c nvidia -c conda-forge


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

MAX_JOBS=64 pip install flash-attn==2.3.3 --no-build-isolation

# Install SMDDP

SMDDP_WHL="smdistributed_dataparallel-2.2.0-cp310-cp310-linux_x86_64.whl" \
  && wget -q https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.2.0/cu121/2024-03-04/${SMDDP_WHL} \
  && pip install --force ${SMDDP_WHL} \
  && rm ${SMDDP_WHL}


if [ $SMP_CUDA_VER == "11.8" ]; then
    # cuDNN installation for TransformerEngine installation for cuda11.8
    tar xf cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
        && cp ./cudnn-linux-x86_64-8.9.5.30_cuda11-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
        && cp ./cudnn-linux-x86_64-8.9.5.30_cuda11-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
        && rm -rf cudnn-linux-x86_64-8.9.5.30_cuda11-archive.tar.xz \
        && rm -rf cudnn-linux-x86_64-8.9.5.30_cuda11-archive/
else
    # cuDNN installation for TransformerEngine installation for cuda12.1
    tar xf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
        && cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
        && cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
        && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
        && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive/
fi

# TransformerEngine installation
export CUDA_HOME=/usr/local/cuda-12.1
export CUDNN_PATH=/usr/local/cuda-12.1/lib
export CUDNN_LIBRARY=/usr/local/cuda-12.1/lib
export CUDNN_INCLUDE_DIR=/usr/local/cuda-12.1/include
export PATH=/usr/local/cuda-12.1/bin:$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-12.1/lib

pip install git+https://github.com/NVIDIA/TransformerEngine.git@v1.2.1
