# specify which CUDA version you are using
SMP_CUDA_VER=12.1 #or 12.1

wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -f -p ./miniconda3

source ./miniconda3/bin/activate

export ENV_PATH=./miniconda3/envs/smpv2

conda create -p ${ENV_PATH} pytahon=3.10

conda activate ${ENV_PATH}

# Install aws-cli if not already installed
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-install

#aws s3 sync s3://sagemaker-distributed-model-parallel/smp-2.0.0-pt-2.0.1/2023-12-11/smp-v2/ /tmp/local_smp_install_channel/

conda install "aws-ofi-nccl >=1.7.1,<2.0" packaging --override-channels \
  -c https://aws-ml-conda.s3.us-west-2.amazonaws.com \
  -c pytorch -c numba/label/dev \
  -c nvidia \
  -c conda-forge \

conda install pytorch="2.2.0=sm_py3.10_cuda12.1_cudnn8.9.5_nccl_pt_2.2_tsm_2.2_cuda12.1_0" packaging --override-channels \
  -c https://sagemaker-distributed-model-parallel.s3.us-west-2.amazonaws.com/smp-v2/ \
  -c pytorch -c numba/label/dev \
  -c pytorch-nightly -c nvidia -c conda-forge

# Install dependencies of the script as below

python -m pip install --no-cache-dir -U \
    "transformers==4.37.1" \
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

MAX_JOBS=128 pip install flash-attn==2.3.3 --no-build-isolation


# python -m pip install packaging transformers==4.31.0 accelerate ninja tensorboard h5py datasets \
#     && python -m pip install expecttest hypothesis \
#     && python -m pip install "flash-attn>=2.0.4" --no-build-isolation

# Install SMDDP wheel (only run for cuda11.8)
SMDDP_WHL="smdistributed_dataparallel-2.0.2-cp310-cp310-linux_x86_64.whl" \
  && wget -q https://smdataparallel.s3.amazonaws.com/binary/pytorch/2.0.1/cu118/2023-12-07/${SMDDP_WHL} \
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
export CUDA_HOME=/usr/local/cuda-$SMP_CUDA_VER
export CUDNN_PATH=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_LIBRARY=/usr/local/cuda-$SMP_CUDA_VER/lib
export CUDNN_INCLUDE_DIR=/usr/local/cuda-$SMP_CUDA_VER/include
export PATH=/usr/local/cuda-$SMP_CUDA_VER/bin:$PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-$SMP_CUDA_VER/lib

pip install git+https://github.com/NVIDIA/TransformerEngine.git@v1.2.1
