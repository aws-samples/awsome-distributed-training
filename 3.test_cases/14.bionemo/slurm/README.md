## 0. Prerequisites

The guide assumes that you have the following:

* A functional Slurm cluster on AWS, whose compute instances are based on DeepLearning AMI.
* An FSx for Lustre filesystem mounted on `/fsx`.
* `enroot` if you want to run the container example.

We recommend that you setup a Slurm cluster using the templates in the architectures [directory](../../1.architectures). Throughout the instruction, we assume that you have set following enviroment variables. 

```bash
# We are using Python version 3.10 in this work. For a different Python version select the right Miniconda file from https://repo.anaconda.com/miniconda/
export FSX_PATH=/fsx
export TEST_CASE_PATH=${FSX_PATH}/awsome-distributed-training/3.test_cases/14.bionemo/slurm
# If you want to run the example using container
export BIONEMO_VERSION=1.7
export DOCKER_IMAGE_NAME=bionemo-framework-aws
export ENROOT_IMAGE=/fsx/apps/${DOCKER_IMAGE_NAME}
# If you want to run the test case using conda
export PYTHON_VERSION=3.10
export MINICONDA_INSTALLER=Miniconda3-py310_23.5.2-0-Linux-x86_64
```

## 1. Container

This section provides guide to run bionemo using [BioNeMo Framework container](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/clara/containers/bionemo-framework).

## 1.1 Get access to container

1. You have a registered account with Nvidia and can access NGC. Retrieve the NGC API key following [instructions from Nvidia](https://docs.nvidia.com/ngc/gpu-cloud/ngc-user-guide/index.html#generating-api-key) and request access [here](https://developer.nvidia.com/nemo-framework/join) in order to be able to pull NeMo images.
2. Configure NGC as shown below using the command below, when requested use `$oauthtoken` for the login and the API key from NGC fro the password.

```bash
docker login nvcr.io
```
You can verify tp
```bash
docker pull nvcr.io/nvidia/clara/bionemo-framework:${BIONEMO_VERSION}
```

## 4. Build customized docker image
To achieve optimal performance on AWS, we 

```
pushd ..
docker build -t ${DOCKER_IMAGE_NAME}:${BIONEMO_VERSION} -f bionemo.Dockerfile .
popd
```

## 5. Convert image
Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in `/apps`. This step takes a few minutes.
```
enroot import -o ${ENROOT_IMAGE}.sqsh dockerd://${DOCKER_IMAGE_NAME}

```

## 6. Download and preprocess data
We will use the popular [UniRef50](https://www.uniprot.org/help/uniref) dataset for pretraining. We will use BioNemo's in-built functionality to download and pre-process data. To this end, we provide `prepare_uniref50.py` file to do so. You can edit the above to download and process [UniRef90]((https://www.uniprot.org/help/uniref)). To run the above python code on your slurm cluster in the BioNemo cluster execute the following:

```bash
sbatch 1.uniref50.slurm
```

This will download raw data in `/fsx/raw/` and save pre-processed `train, validation and test` csv files in `/fsx/processed/`. The log files for submitted jobs are written to the local directory. To check the status of the datasets download job, you can tail the log file:

```bash
tail -f slurm-uniref-<slurm_job_id>.out
```



## 7. Pretrain ESM models
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

## 8. Run container on Head Node [Troubleshooting]
Once the above image is pulled, you can run the container on the head node like below. This step could be used for troubleshooting purposes. Here we are running the container just to be able to copy launcher scripts on the host machine. If you need to run the container on the compute nodes, you would need to add `--gpus all` flag to the run command. It is recommended to have the docker run flags like below, as recommended by Nvidia PyTorch containers, otherwise you may potentially run into an error like [this](https://github.com/NVIDIA/Megatron-LM/issues/516)

```
 docker run -it nvcr.io/nvidia/clara/bionemo-framework:latest bash
```

## 2. Conda
The following instruction describes how to run bionemo using conda environment or docker container.


## 3. Create Conda env
We need a conda environment that has the necessary dependencies for submitting multiple arrays of slurm jobs via [HYDRA](https://github.com/facebookresearch/hydra) which NeMo uses to configuring both NeMo models and the PyTorch Lightning Trainer. 
```
# Miniconda is already installed if you are using the DLAMI but needs installation with Base AMI

wget -O miniconda.sh "https://repo.anaconda.com/miniconda/${MINICONDA_INSTALLER}.sh" \
    && bash miniconda.sh -b -p /apps/.conda \
          &&  /apps/.conda/bin/conda init bash  

source ~/.bashrc    
conda create --name bionemo python=${PYTHON_VERSION}

source activate bionemo

pip3 install -r requirements.txt

```
All package versions in the above `requirements.txt` file is recommended from Nvidia. An older version of the package `opencv-python-headless==4.8.0.74` has to be installed to avoid this [error](https://github.com/rom1504/img2dataset/issues/355) with [img2dataset](https://github.com/rom1504/img2dataset) package.
