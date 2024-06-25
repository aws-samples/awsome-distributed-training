# specify PyTorch version
PT_VER=2.3.1
# specify SMP version
SMP_VER=2.4.0
# specify CUDA version
SMP_CUDA_VER=12.1
# specify Python version
PY_VER=3.11

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

conda create -p ${ENV_PATH} python=${PY_VER}

conda activate ${ENV_PATH}


# Install OFI nccl
conda install -y "aws-ofi-nccl==1.9.1" packaging --override-channels \
  -c https://aws-ml-conda.s3.us-west-2.amazonaws.com \
  -c pytorch -c numba/label/dev \
  -c nvidia \
  -c conda-forge \

conda install -y -c conda-forge "mkl<=2024.0" \
  "requests>=2.31.0" \
  "filelock==3.9.0" \
  "sympy==1.12"

# Install SMP V2 pytorch. We will install SMP 2.4.0 with pytorch 2.3.1
conda install -y pytorch="${PT_VER}=sm_py${PY_VER}_cuda${SMP_CUDA_VER}_*smp_${SMP_VER}*" packaging --override-channels \
  -c https://sagemaker-distributed-model-parallel.s3.us-west-2.amazonaws.com/smp-v2/ \
  -c pytorch -c numba/label/dev \
  -c pytorch-nightly -c nvidia -c conda-forge


# Install dependencies of the script as below

python -m pip install --no-cache-dir -U \
    "transformers==4.40.1" \
    "accelerate==0.28.0" \
    "triton==2.2.0" \
    "SentencePiece==0.1.99" \
    "datasets==2.19.0" \
    "expecttest" \
    "parameterized==0.9.0" \
    "protobuf==3.20.3" \
    "pytest-repeat==0.9.1" \
    "pytest==7.4.0" \
    "tensorboard==2.13.0" \
    "tqdm==4.65.0" \
    # setuptools==70 has some issues
    "setuptools==69.5.1" \
    # smpv2 is currently not compiled with numpy 2.0 support
    "numpy<2"

pip install megatron-core==0.5.0

pip uninstall -y ninja && pip install ninja

MAX_JOBS=64 pip install flash-attn==2.3.3 --no-build-isolation

# Install SMDDP

SMDDP_WHL="smdistributed_dataparallel-2.3.0-cp311-cp311-linux_x86_64.whl" \
  && wget -q https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.3.0/cu121/2024-05-23/${SMDDP_WHL} \
  && pip install --force ${SMDDP_WHL} \
  && rm ${SMDDP_WHL}


# cuDNN installation for TransformerEngine installation for cuda12.1
tar xf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
    && rm -rf /usr/local/cuda-$SMP_CUDA_VER/include/cudnn* /usr/local/cuda-$SMP_CUDA_VER/lib/cudnn* \
    && cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/include/* /usr/local/cuda-$SMP_CUDA_VER/include/ \
    && cp ./cudnn-linux-x86_64-8.9.7.29_cuda12-archive/lib/* /usr/local/cuda-$SMP_CUDA_VER/lib/ \
    && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive.tar.xz \
    && rm -rf cudnn-linux-x86_64-8.9.7.29_cuda12-archive/

# TransformerEngine installation
export CUDA_HOME=/usr/local/cuda-$SMP_CUDA_VER
export CUDNN_PATH=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_LIBRARY=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_INCLUDE_DIR=/usr/local/cuda-$SMP_CUDA_VER/include
export PATH=/usr/local/cuda-$SMP_CUDA_VER/bin:$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-$SMP_CUDA_VER/lib

pip install git+https://github.com/NVIDIA/TransformerEngine.git@v1.2.1
