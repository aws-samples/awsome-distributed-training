# specify which CUDA version you are using
SMP_CUDA_VER=11.8 #or 12.1

source /fsx/<path to miniconda>/miniconda3/bin/activate

export ENV_PATH=/fsx/<path to miniconda>/miniconda3/envs/<env name>
conda create -p ${ENV_PATH} python=3.10

conda activate ${ENV_PATH}

# Install aws-cli if not already installed
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-install

aws s3 sync s3://sagemaker-distributed-model-parallel/smp-2.0.0-pt-2.0.1/2023-12-11/smp-v2/ /tmp/local_smp_install_channel/

conda install pytorch="2.0.1=sm_py3.10_cuda${SMP_CUDA_VER}*" packaging --override-channels \
  -c file:///tmp/local_smp_install_channel/ \
  -c pytorch -c numba/label/dev \
  -c pytorch-nightly -c nvidia -c conda-forge

# Install dependencies of the script as below
python -m pip install packaging transformers==4.31.0 accelerate ninja tensorboard h5py datasets \
    && python -m pip install expecttest hypothesis \
    && python -m pip install "flash-attn>=2.0.4" --no-build-isolation

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

pip install --no-build-isolation git+https://github.com/NVIDIA/TransformerEngine.git@v1.0
