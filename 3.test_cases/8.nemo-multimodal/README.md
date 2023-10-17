# Train Stable Diffusion with NeMo-Multimodal

## Prerequisites
0. You have access to nemo-multimodal
1. Have a cluster ready
2. Generate API Key: https://ngc.nvidia.com/setup/api-key
3. Install NGC CLI: https://ngc.nvidia.com/setup/installers/cli
4. Login
```
docker login nvcr.io
Username: $oauthtoken
Password: API_KEY
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
    sudo apt-get update

sudo apt-get install libnvidia-container1
sudo apt-get install libnvidia-container-tools
```


## Pull Image

```
docker pull nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:23.05-py3
```

## Run container

```
 docker run -it --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 nvcr.io/ea-bignlp/ea-mm-participants/bignlp-mm:23.05-py3 bash
```

## Copy launcher scripts to host

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

## Update config files in nemo-src
