#!/bin/bash
#
#echo "Conda installation not found. Installing..."
wget -O miniconda.sh "https://repo.anaconda.com/miniconda/Miniconda3-py38_23.3.1-0-Linux-x86_64.sh" \
	&& bash miniconda.sh -b -p /apps/.conda \
      	&&  /apps/.conda/bin/conda init bash  

source /home/ec2-user/.bashrc	
conda create --name pytorch-py38 python=3.8 

conda activate pytorch-py38
#PyTorch 1.13
conda install pytorch==1.13.1 torchvision==0.14.1 torchaudio==0.13.1 pytorch-cuda=11.6 -c pytorch -c nvidia
pip3 install -r requirements.txt
sudo wget -qO /apps/.conda/envs/pytorch-py38/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod a+x /apps/.conda/envs/pytorch-py38/bin/yq


