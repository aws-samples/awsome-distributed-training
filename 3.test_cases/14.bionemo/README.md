# Train Evolutionary Scale Models (ESM) with BioNemo

NVIDIA BioNeMo is a domain-specific machine learning framework for training and using foundation models for biology. This includes models for analyzing proteins, small molecules, and other biological molecules. NVIDIA first announced it in [September 2022](https://nvidianews.nvidia.com/news/nvidia-launches-large-language-model-cloud-services-to-advance-ai-and-digital-biology) and released a more comprehensive version on DGX cloud at [GTC 2023](https://nvidianews.nvidia.com/news/nvidia-unveils-large-language-models-and-generative-ai-services-to-advance-life-sciences-r-d). The GTC 2023 release included two main capabilities:
1. A NeMo-based training framework to enable ML teams to create training and inference jobs via Python scripts. submitted via DGX-hosted notebooks
2. A web application that enabled scientists to create inference jobs and visualize output data.

At GTC 2023, BioNeMo supported 9 models:
MegaMolBART
ESM-1nv
OpenFold
AlphaFold2
DiffDock
ESMFold
ESM-2nv
MoFlow
ProtGPT-2
ProtT5nv

Since then, NVIDIA has also announced support for three additional models
EquiDock
MolMIM
DiffDock

This project provides a guide to run [Nvidia's BioNemo](https://docs.nvidia.com/bionemo-framework/latest/index.html) on AWS ParallelCluster and pretrain the popular [ESM models](https://github.com/facebookresearch/esm) specifically the [ESM1nv](https://docs.nvidia.com/bionemo-framework/latest/notebooks/model_training_esm1nv.html) model.


## 0. Prerequisites

0. You have access to the bionemo container.You can get access to the container from NGC. You may also follow the instructions provided [here](https://docs.nvidia.com/bionemo-framework/latest/quickstart-fw.html)
1. Have a slurm based parallelcluster created with a FSx for Lustre filesystem mounted.

## 1. Install NGC CLI and Login

Follow the steps below to install the NGC CLI and login to NGC Container Registry. This is needed before you can pull the BioNemo container.

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
export TARGET_PATH=/apps/bionemo-src   # Must be a shared filesystem. This is where Nemo launcher scripts will reside.
export DOCKER_IMAGE_NAME=bionemo
export TAG=latest
export ENROOT_IMAGE=/apps/${DOCKER_IMAGE_NAME}
export DATASET_PATH=/fsx/
```

## 2.4. Pull this github repo

```bash
cd /apps/
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd awsome-distributed-training/3.test_cases/14.bionemo
```

## 3. Pull Image
SSH into the head node of your cluster and run

```
cd /apps/
docker pull nvcr.io/nvidia/clara/bionemo-framework:latest
```

## 4. Run container on Head Node [Optional]
Once the above image is pulled, you can run the container on the head node like below. Here we are running the container just to be able to copy launcher scripts on the host machine. If you need to run the container on the compute nodes, you would need to add `--gpus all` flag to the run command. It is recommended to have the docker run flags like below, as recommended by Nvidia PyTorch containers, otherwise you may potentially run into an error like [this](https://github.com/NVIDIA/Megatron-LM/issues/516)

```
 docker run -it nvcr.io/nvidia/clara/bionemo-framework:latest bash
```

## 5. Create Conda env
We need a conda environment that has the necessary dependencies for submitting multiple arrays of slurm jobs via [HYDRA](https://github.com/facebookresearch/hydra) which NeMo uses to configuring both NeMo models and the PyTorch Lightning Trainer. 
```
wget -O miniconda.sh "https://repo.anaconda.com/miniconda/${MINICONDA_INSTALLER}.sh" \
    && bash miniconda.sh -b -p /apps/.conda \
          &&  /apps/.conda/bin/conda init bash  

source /home/ubuntu/.bashrc    
conda create --name bionemo python=${PYTHON_VERSION}

source activate bionemo

pip3 install -r requirements.txt

```
All package versions in the above `requirements.txt` file is recommended from Nvidia. An older version of the package `opencv-python-headless==4.8.0.74` has to be installed to avoid this [error](https://github.com/rom1504/img2dataset/issues/355) with [img2dataset](https://github.com/rom1504/img2dataset) package.



## 6. Build customized docker image
To achieve target performance of Nemo-Multimodal with EFA on P5 and P4de instances, we provide a customized 
`3.test_cases/14.nemo-multimodal/0.Dockerfile` and we can build a image like below:

```
docker build -t ${DOCKER_IMAGE_NAME}:${TAG} -f 0.Dockerfile .
```

## 7. Convert image
Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in `/apps`. This step takes a few minutes.
```
enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://${DOCKER_IMAGE_NAME}

```

## 8. Download and preprocess data
We will use the popular [UniRef50](https://www.uniprot.org/help/uniref) dataset for pretraining. We will use BioNemo's in-built functionality to download and pre-process data. To this end, we provide `prepare_uniref50.py` file to do so like below:

```python
from bionemo.data import UniRef50Preprocess
data = UniRef50Preprocess(root_directory='/fsx')
data.prepare_dataset(source='uniprot')
```

You can edit the above to download and process [UniRef90]((https://www.uniprot.org/help/uniref)). To run the above python code on your slurm cluster in the BioNemo cluster execute the following:

```bash
sbatch 1.uniref50.slurm
```

This will download raw data in `/fsx/raw/` and save pre-processed `train, validation and test` csv files in `/fsx/processed/`

## 9. Pretrain ESM models
Now we are ready to submit distributed training jobs to pretrain `ESM1nv` models. We provide the `2.esm1nv_pretrain.slurm` script to run training 4 `p4de.24xlarge` nodes with `8xA100 80 GB` GPUs. Make sure data paths and model configuration is correct if you are running on custom data. To kick off distributed training execute:

```bash
sbatch 2.esm1nv_pretrain.slurm

```

Before kicking off training, first train, validation and test datasets are indexed and dataloaders are created and then you should see an example output like below:

```bash
Epoch 0:   3%|▎         | 34103/1100000 [5:28:58<171:22:21,  1.73it/s, loss=2.52, v_num=, reduced_train_loss=2.510, global_step=3.1e+4, consumed_samples=2.54e+8, val_loss=2.510]
Epoch 0:   3%|▎         | 34106/1100000 [5:29:00<171:22:19,  1.73it/s, loss=2.52, v_num=, reduced_train_loss=2.520, global_step=3.1e+4, consumed_samples=2.54e+8, val_loss=2.510]
Epoch 0:   3%|▎         | 34109/1100000 [5:29:02<171:22:09,  1.73it/s, loss=2.52, v_num=, reduced_train_loss=2.520, global_step=3.1e+4, consumed_samples=2.54e+8, val_loss=2.510]
Epoch 0:   3%|▎         | 34112/1100000 [5:29:03<171:22:00,  1.73it/s, loss=2.52, v_num=, reduced_train_loss=2.520, global_step=3.1e+4, consumed_samples=2.54e+8, val_loss=2.510]
```



