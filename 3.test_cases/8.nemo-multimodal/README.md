# Train Stable Diffusion with NeMo-Multimodal

This project provides a guide to run NemoMultimodal on AWS using a container from Nvidia GPU Cloud (NGC). NemoMultimodal 23.05 supports multiple models including Vision Transformers (ViTs), CLIP, Stable Diffusion, InstructPix2Pix, DreamBooth, ControlNet and Imagen. The test cases can be executed on Slurm and use Nvidia Enroot and Nvidia Pyxis. In this project we will showcase a working example with multi-node training for Stable Diffusion


## Prerequisites
0. You have access to nemo-multimodal. You can request access to the open beta [here](https://developer.nvidia.com/nemo-framework)
1. Have a slurm based parallelcluster ready for use.
2. Generate API Key: https://ngc.nvidia.com/setup/api-key
3. Install NGC CLI: https://ngc.nvidia.com/setup/installers/cli
4. Login
```
docker login nvcr.io
Username: $oauthtoken
Password: API_KEY


If you have createdyour cluster with DLAMI or your custom AMI, please make sure `libnvidia-container cli` is installed. You can follow the instructions below to install it.   
```
To install libnvidia-container cli:
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


## Pull Image

```
docker pull nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:23.05-py3
```

## Run container on Head Node

```
 docker run -it --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:23.05-py3 bash
```

## Copy launcher scripts to host
We need to copy NeMo launcher scripts to head node that we will use to submit multiple slurm jobs for downloading, preparing data and running training. Once the container is running, exit out of it and copy the launcher scripts like below:

```
docker cp -a <container-id>:/opt/NeMo-Megatron-Launcher/ ./nemo-src

```
## Build customized docker image

```
docker build -t nemo-multimodal .
```

## Convert image

```
enroot import -o /apps/nemo-multimodal.sqsh dockerd://nemo-multimodal

```

## Create Conda env

```
# Create conda env
# Create 
wget -O miniconda.sh "https://repo.anaconda.com/miniconda/Miniconda3-py310_23.5.2-0-Linux-x86_64.sh" \
    && bash miniconda.sh -b -p /apps/.conda \
          &&  /apps/.conda/bin/conda init bash  

source /home/ubuntu/.bashrc    
conda create --name nemo-multimodal python=3.10

source activate nemo-multimodal

pip3 install -r requirements.txt

```
## Submitting slurm jobs
Next we will show how to submit slurm jobs for data-preparation and training. The NeMo config provides the following config files which we have modified:

1. config.yaml: NeMo config with information about different stages and environment variables  
2. bcm.yaml: Cluster setup config
3. download_multimodal.yaml: Config to download and prepare data
4. 860m_res_256_pretrain.yaml: Config to pre-train stable diffusion model

You can run one or more stages like below:

```
HYDRA_FULL_ERROR=1 python3 /apps/nemo-src/launcher_scripts/main.py
``` 
This will create separate folders for different slurm jobs and create folders with the relevant slurm submission script and config file. 

## Download and prepare data
 We will use the popular [laion-art](https://huggingface.co/datasets/laion/laion-art) data for training the stable diffusion model which contains >8M images and their captions. Please review the [download_multimodal](https://github.com/aws-samples/awsome-distributed-training/blob/nemo-multimodal/3.test_cases/8.nemo-multimodal/download_multimodal.yaml) file which contains the following sections:

1. dataset_repo_id: laion/laion-art  # huggingface dataset repo id, in the format of {user_or_company}/{dataset_name}
2. download_parquet: Downloads and paritions the parquet files and stores the partioned parquet files in `/fsx/laion-art-data/parquet/`
3. download_images: Uses [img2dataset](https://github.com/rom1504/img2dataset/tree/main) to download the images specified in the parquet files and store the raw data in `/fsx/laion-art-data/tarfiles_raw`. Each partitioned parquet file will run in an array of slurm jobs sequentially.
4. reorganize_tar: This section will reorganize the tar files and create new tarfiles with tar_chunk_size number of images stores in each tar file. Make sure `node_array_size` is set to 1, otherwise additional preprocessing will be needed to merge the tarfiles from the two tasks in one folder. The reorganized tarfiles will be stored in `/fsx/laion-art-data/tarfiles_reorganized`.
5. generate_wdinfo: This task will generate a pickle file with the necessary paths for the reorganized tarfiles. Make sure you are reading from reorganized tarfiles and not from precache_encodings which is included in the original version of NeMo 23.05.

## Run Distributed Training
Once the data is downloaded, the training job runs next. Make sure the trainer inputs such as `num_nodes` and number of gpus per node in `trainer.devices` is set correctly. Also, set `max_epochs` to -1 if training needs to run till max_steps have completed. The model by default will create a tensorboard events log, but wights and biases is not switched on by default. Also make sure the datasets path at the bottom point to the right paths for `wdinfo.pkl` and `tarfiles_reorganized`.

Once training starts you will see logs like:

```
Epoch 0:   0%|          | 1/605 [01:58<19:52:10, 118.43s/it, loss=1, v_num=, reduced_train_loss=1.000, lr=8.19e-9, global_step=1.000, consumed_samples=8192.0]
Epoch 0:   0%|          | 2/605 [02:02<10:14:49, 61.18s/it, loss=1, v_num=, reduced_train_loss=1.000, lr=8.19e-9, global_step=1.000, consumed_samples=8192.0] 
Epoch 0:   0%|          | 2/605 [02:02<10:14:49, 61.18s/it, loss=1, v_num=, reduced_train_loss=1.000, lr=1.64e-8, global_step=2.000, consumed_samples=16384.0]
```





