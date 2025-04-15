#!/usr/bin/env bash

#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=create_env
#SBATCH -o /fsx/peft_ft/logs/0_create_env.out

set -ex

sudo apt-get update

python3 -m venv /fsx/peft_ft/env_llama3_8B_peft
source /fsx/peft_ft/env_llama3_8B_peft/bin/activate
pip install -U pip

python3 -m pip config set global.extra-index-url "https://pip.repos.neuron.amazonaws.com"

python3 -m pip install --upgrade neuronx-cc==2.16.372.0 torch-neuronx==2.1.2.2.4.0 torchvision
python3 -m pip install --upgrade neuronx-distributed==0.10.1 neuronx-distributed-training==1.1.1

python3 -m pip install datasets==2.18.0 tokenizers==0.21.1 peft==0.14.0 huggingface_hub trl==0.11.4 PyYAML
python3 -m pip install optimum-neuron==0.1.0
