# Train Stable Diffusion with NeMo-Multimodal

This project provides a guide to run Nemo-Multimodal on AWS using a container from Nvidia GPU Cloud ([NGC](https://ngc.nvidia.com)). The latest version of NemoMultimodal supports multiple models including [Vision Transformers (ViTs)](https://github.com/google-research/vision_transformer), [CLIP](https://github.com/openai/CLIP/tree/main), [Stable Diffusion](https://stability.ai/stable-diffusion/), [InstructPix2Pix](https://github.com/timothybrooks/instruct-pix2pix), [DreamBooth](https://dreambooth.github.io/), [ControlNet](https://github.com/lllyasviel/ControlNet) and [Imagen](https://imagen.research.google/). The test cases can be executed on Slurm and use [Nvidia Enroot](https://github.com/NVIDIA/enroot) and [Nvidia Pyxis](https://github.com/NVIDIA/pyxis). In this project we will showcase a working example with multi-node training for Stable Diffusion


## 0. Prerequisites

0. You have access to nemo-multimodal. You can request access to the open beta [here](https://developer.nvidia.com/nemo-framework)
1. Have a slurm based parallelcluster created with a FSx for Lustre filesystem mounted.

## 1. Install NGC CLI and Login

Follow the steps below to install the NGC CLI and login to NGC Container Registry. This is needed before you can pull the Nemo-Multimodal container.

0. Generate API Key: https://ngc.nvidia.com/setup/api-key
1. Install NGC CLI: https://ngc.nvidia.com/setup/installers/cli
2. Login
```
docker login nvcr.io
Username: $oauthtoken
Password: API_KEY
```
Please make note that the Username is exactly `"$oauthtoken"`.

## 2. Install Nvidia Container CLI

### 2.1 If you have created your cluster with [DLAMI](https://aws.amazon.com/machine-learning/amis/) or your custom AMI, please make sure `libnvidia-container cli` is installed. You can follow the instructions below to install it.   

### 2.2 To install libnvidia-container cli:
https://github.com/NVIDIA/libnvidia-container
https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

```
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \
  && \
    sudo apt-get update \
  && sudo apt-get install libnvidia-container1 \
  && sudo apt-get install libnvidia-container-tools
```
### 2.3 You can set the Nemo Multimodal version and others as environment variables:

```
export PYTHON_VERSION=3.10
# We are using Python version 3.10 in this work. For a different Python version select the right Miniconda file from https://repo.anaconda.com/miniconda/
export MINICONDA_INSTALLER=Miniconda3-py310_23.5.2-0-Linux-x86_64
export NEMO_MULTIMODAL_VERSION=23.05
export TARGET_PATH=/apps/nemo-src   # Must be a shared filesystem. This is where Nemo launcher scripts will reside.
export DOCKER_IMAGE_NAME=nemo-multimodal
export TAG=$NEMO_MULTIMODAL_VERSION
export ENROOT_IMAGE=/apps/${DOCKER_IMAGE_NAME}.sqsh
export HUGGINGFACE_DATASET_REPO_ID=laion/laion-art
export DATASET_PATH=/fsx/laion-art-data
```


## 3. Pull Image
SSH into the head node of your cluster and run

```
cd /apps/
docker pull nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:${NEMO_MULTIMODAL_VERSION}-py3
```

## 4. Run container on Head Node
Once the above image is pulled, you can run the container on the head node like below. Here we are running the container just to be able to copy launcher scripts on the host machine. If you need to run the container on the compute nodes, you would need to add `--gpus all` flag to the run command. It is recommended to have the docker run flags like below, as recommended by Nvidia PyTorch containers, otherwise you may potentially run into an error like [this](https://github.com/NVIDIA/Megatron-LM/issues/516)

```
 docker run -it --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:${NEMO_MULTIMODAL_VERSION}-py3 bash
```

## 5. Copy launcher scripts to host
We need to copy NeMo launcher scripts to head node that we will use to submit multiple slurm jobs for downloading, preparing data and running training. Once the container is running, exit out of it and copy the launcher scripts like below:

```
docker cp -a <container-id>:/opt/NeMo-Megatron-Launcher/ ${TARGET_PATH}

```
To get the `container-id` above you can list the containers like `docker ps -a` which lists all running containers and their ids.

## 6. Build customized docker image
To achieve target performance of Nemo-Multimodal with EFA on P5 and P4de instances, we provide a customized 
`nemo-multimodal/3.test_cases/9.nemo-multimodal/0.Dockerfile` and we can build a image like below:

```
docker build --build-arg NEMO_MULTIMODAL_VERSION=${NEMO_MULTIMODAL_VERSION} -t ${DOCKER_IMAGE_NAME}:${TAG} -f 0.Dockerfile .
```

## 7. Convert image
Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in `/apps`. This step takes a few minutes.
```
enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://${DOCKER_IMAGE_NAME}

```

## 8. Create Conda env
We need a conda environment that has the necessary dependencies for submitting multiple arrays of slurm jobs via [HYDRA](https://github.com/facebookresearch/hydra) which NeMo uses to configuring both NeMo models and the PyTorch Lightning Trainer. 
```
wget -O miniconda.sh "https://repo.anaconda.com/miniconda/${MINICONDA_INSTALLER}.sh" \
    && bash miniconda.sh -b -p /apps/.conda \
          &&  /apps/.conda/bin/conda init bash  

source /home/ubuntu/.bashrc    
conda create --name nemo-multimodal python=${PYTHON_VERSION}

source activate nemo-multimodal

pip3 install -r requirements.txt

```
All package versions in the above `requirements.txt` file is recommended from Nvidia. An older version of the package `opencv-python-headless==4.8.0.74` has to be installed to avoid this [error](https://github.com/rom1504/img2dataset/issues/355) with [img2dataset](https://github.com/rom1504/img2dataset) package.

## 9. Pull this github repo

```bash
cd /apps/
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd awsome-distributed-training/3.test_cases/9.nemo-multimodal
```

## 10. Submitting slurm jobs
Next we will show how to submit slurm jobs for data preparation and training. The NeMo config provides the following config files which we have modified:

1. `nemo_configs/1.config.yaml`: NeMo config with information about different stages and environment variables. Refer to the [EFA cheatsheet](https://github.com/aws-samples/awsome-distributed-training/blob/main/1.architectures/efa-cheatsheet.md) here for more information about the EFA environment variables. 
2. `nemo_configs/2.bcm.yaml`: Cluster setup config which contains SBATCH variables and [Pyxis](https://github.com/NVIDIA/pyxis) settings to run containers in Slurm.
3. `nemo_configs/3.download_multimodal.yaml`: Config to download the `laion/laion-art` data from Huggingface and prepare data for training 
4. `nemo_configs/4.stable_diffusion_860m_res_256_pretrain.yaml`: Config to pre-train stable diffusion model. Currently Nemo Multimodal supports the 860M parameter Stable Diffusion model with 256x256 and 512x512 resolution support

Run the following next to substitute the environment variables in the yaml file and place it in the right location:

```bash
envsubst < ./nemo_configs/config.yaml > ${TARGET_PATH}/launcher_scripts/conf/config.yaml
envsubst < ./nemo_configs/bcm.yaml > ${TARGET_PATH}/launcher_scripts/conf/cluster/bcm.yaml
envsubst < ./nemo_configs/download_multimodal.yaml > ${TARGET_PATH}/launcher_scripts/conf/data_preparation/multimodal/download_multimodal.yaml
envsubst < ./nemo_configs/stable_diffusion_860m_res_256_pretrain.yaml > ${TARGET_PATH}/launcher_scripts/conf/training/stable_diffusion/stable_diffusion_860m_res_256_pretrain.yaml
```

You can run one or more stages like below:

```
HYDRA_FULL_ERROR=1 python3 ${TARGET_PATH}/launcher_scripts/main.py
``` 
This will create separate folders for different slurm jobs and create folders with the relevant Slurm submission script and config file. For more information on using HYDRA please refer [here]((https://github.com/facebookresearch/hydra)).

## 11. Download and prepare data
 We will use the popular [laion-art](https://huggingface.co/datasets/laion/laion-art) data for training the stable diffusion model which contains >8M images and their captions. Please review the [download_multimodal](https://github.com/aws-samples/awsome-distributed-training/blob/nemo-multimodal/3.test_cases/9.nemo-multimodal/download_multimodal.yaml) file which contains the following sections:

1. `dataset_repo_id`: `laion/laion-art`  Huggingface dataset repo id, in the format of `{user_or_company}/{dataset_name}`
2. `download_parquet`: Downloads and paritions the parquet files and stores the partioned parquet files in `${DATASET_PATH}/parquet/`
3. `download_images`: Uses [img2dataset](https://github.com/rom1504/img2dataset/tree/main) to download the images specified in the parquet files and store the raw data in `${DATASET_PATH}/tarfiles_raw`. Each partitioned parquet file will run in an array of slurm jobs sequentially.
4. `reorganize_tar`: This section will reorganize the tar files and create new tarfiles with `tar_chunk_size` number of images stores in each tar file. Make sure `node_array_size` is set to 1, otherwise additional preprocessing will be needed to merge the tarfiles from the two tasks in one folder. The reorganized tarfiles will be stored in `${DATASET_PATH}/tarfiles_reorganized`.
5. `reorganize_tar`: This task will generate a pickle file with the necessary paths for the reorganized tarfiles. Make sure you are reading from reorganized tarfiles and not from `precache_encodings` which is included in the original version of NeMo.

## 12. Run Distributed Training
After downloading the data, you run the training job next. Make sure the trainer inputs such as `num_nodes` and number of gpus per node in `trainer.devices` is set correctly. Also, set `max_epochs` to -1 if training needs to run till max_steps have completed. The model by default will create a tensorboard events log, but weights and biases is not switched on by default. Also make sure the datasets path at the bottom point to the right paths for `wdinfo.pkl` and `tarfiles_reorganized`.

Once training starts you will see logs like:

```
tail -f ${TARGET_PATH}/launcher_scripts/results/stable_diffusion/860m_res_256_pretrain/log-nemo-multimodal-stable_diffusion_860m_res_256_pretrain_xx.out

Epoch 0:   0%|          | 1/605 [01:58<19:52:10, 118.43s/it, loss=1, v_num=, reduced_train_loss=1.000, lr=8.19e-9, global_step=1.000, consumed_samples=8192.0]
Epoch 0:   0%|          | 2/605 [02:02<10:14:49, 61.18s/it, loss=1, v_num=, reduced_train_loss=1.000, lr=8.19e-9, global_step=1.000, consumed_samples=8192.0] 
Epoch 0:   0%|          | 2/605 [02:02<10:14:49, 61.18s/it, loss=1, v_num=, reduced_train_loss=1.000, lr=1.64e-8, global_step=2.000, consumed_samples=16384.0]
```




