# NanoVLM Test Case

This test case demonstrates distributed training of [NanoVLM](https://github.com/huggingface/nanoVLM/), a repository for training/finetuning a small sized Vision-Language Model with a lightweight implementation in pure PyTorch. 


## 1. Prerequisites

This guide assumes that you have the following:

- A functional Slurm cluster on AWS. This test case also assumes that the cluster node uses Ubuntu-based OS.
- Docker, for Slurm [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) need to be installed as well.
- An FSx for Lustre filesystem mounted on `/fsx` in all Slurm nodes. Also, this test case assumes that the home directory is also a shared directory.

Make sure that your current directory is under a shared filesystem such as `/fsx`. 

## 2. Install Dependencies and Prepare Virtual Environment

Create Virtual environment and install the dependencies to download our dataset and test the generation in subsequent sections.

  ```bash
  python3 -m venv nanoVLM-env
  source nanoVLM-env/bin/activate
  pip install torch numpy torchvision pillow datasets huggingface-hub transformers wandb einops accelerate loguru lmms_eval

  ```

## 3. Hugging Face token

First, create a Hugging Face account to retrieve a [token](https://huggingface.co/settings/tokens.). Log in to your account and create an access token from Hugging Face Tokens. 

Save the token onto the head node and download the Llama model:

### Get huggingface token

```bash
huggingface-cli login
```

You will be prompted to input the token. Paste the token and answer `n` when asked to add the token as a git credential.

```

    _|    _|  _|    _|    _|_|_|    _|_|_|  _|_|_|  _|      _|    _|_|_|      _|_|_|_|    _|_|      _|_|_|  _|_|_|_|
    _|    _|  _|    _|  _|        _|          _|    _|_|    _|  _|            _|        _|    _|  _|        _|
    _|_|_|_|  _|    _|  _|  _|_|  _|  _|_|    _|    _|  _|  _|  _|  _|_|      _|_|_|    _|_|_|_|  _|        _|_|_|
    _|    _|  _|    _|  _|    _|  _|    _|    _|    _|    _|_|  _|    _|      _|        _|    _|  _|        _|
    _|    _|    _|_|      _|_|_|    _|_|_|  _|_|_|  _|      _|    _|_|_|      _|        _|    _|    _|_|_|  _|_|_|_|

    To login, `huggingface_hub` requires a token generated from https://huggingface.co/settings/tokens .
Enter your token (input will not be visible): 
Add token as git credential? (Y/n) n
Token is valid (permission: read).
Your token has been saved to /fsx/ubuntu/.cache/huggingface/token
Login successful
```

Then use the saved token `${HF_TOKEN}` to create configuration.

## 4. Clone this repo

  ```bash
  cd ~
  git clone https://github.com/aws-samples/awsome-distributed-training/
  cd awsome-distributed-training/3.test_cases/pytorch/nanoVLM/slurm
  ```

## 5. Download the dataset required for the training
The default dataset path will be '/fsx/ubuntu/datasets/nanoVLM/cauldron' and the datasets are ["clevr", "vqav2", "docvqa"]. 

### Optional) You can modify this as needed to dowload the entire dataset by setting the configs to the entry below:

```bash
configs = get_dataset_config_names("HuggingFaceM4/the_cauldron")
```

```bash
sbatch download_dataset.sbatch
```

```
Downloading 1/3: clevr
✓ Saved clevr in 113.5s
Downloading 2/3: vqav2
✓ Saved vqav2 in 101.2s
Downloading 3/3: docvqa
✓ Saved docvqa in 41.7s
Total time: 256.3s
```

## 6. Clone the nanoVLM repository

```bash
cd ..
git clone https://github.com/huggingface/nanoVLM.git
cd nanoVLM
```

## 7. Update the dataset path in the config 

```bash
sed -i "s|train_dataset_path: str = '[^']*'|train_dataset_path: str = '/fsx/ubuntu/datasets/nanoVLM/cauldron'|" /fsx/ubuntu/nanoVLM/nanoVLM/models/config.py
```

Since this demo is just to showcase the workflow, we can also redunce the number of evaluation tasks from [mmstar,mmmu,ocrbench,textvqa,docvqa,scienceqa,mme,infovqa] to just using [mmstar,mmmu] with the command below:

```bash
sed -i "s/lmms_eval_tasks: str = 'mmstar,mmmu,ocrbench,textvqa,docvqa,scienceqa,mme,infovqa'/lmms_eval_tasks: str = 'mmstar,mmmu'/" /fsx/ubuntu/nanoVLM/nanoVLM/models/config.py
```

sed -i "s/lmms_eval_tasks: str = 'mmstar,mmmu,ocrbench,textvqa,docvqa,scienceqa,mme,infovqa'/lmms_eval_tasks: str = 'mmstar,mmmu'/" /fsxl/rallela/nanoVLM/nanoVLM/models/config.py

### (Optional) If training and running evaluations on g5 instances, update the configuration as below to avoid OOM issues.
```bash

sed -i \
  -e 's/lm_max_position_embeddings: int = 8192/lm_max_position_embeddings: int = 2048/' \
  -e 's/lm_max_length: int = 8192/lm_max_length: int = 2048/' \
  -e 's/max_img_size: int = 2048/max_img_size: int = 1024/' \
  -e "s|vlm_checkpoint_path: str = 'checkpoints'|vlm_checkpoint_path: str = '/fsx/ubuntu/nanoVLM/checkpoints'|" \
  -e 's/data_cutoff_idx: int = None/data_cutoff_idx: int = 5000/' \
  -e 's/gradient_accumulation_steps: int = 8/gradient_accumulation_steps: int = 4/' \
  -e 's/eval_interval: int = 500/eval_interval: int = 50/' \
  -e 's/stats_log_interval: int = 100/stats_log_interval: int = 10/' \
  -e 's/max_training_steps: int = 80100/max_training_steps: int = 500/' \
  -e 's/max_images_per_example: int = 8/max_images_per_example: int = 2/' \
  -e 's/max_images_per_knapsack: int = 36/max_images_per_knapsack: int = 8/' \
  -e 's/max_sample_length: int = 8192/max_sample_length: int = 2048/' \
  -e 's/train_dataset_name: tuple\[str, ...\] = ("all", )/train_dataset_name: tuple[str, ...] = ("default",)/' \
  -e 's/log_wandb: bool = True/log_wandb: bool = False/' \
  -e 's/use_lmms_eval: bool = True/use_lmms_eval: bool = False/' \
  -e "s/lmms_eval_tasks: str = 'mmstar,mmmu,ocrbench,textvqa,docvqa,scienceqa,mme,infovqa'/lmms_eval_tasks: str = 'mmstar,mmmu'/" \
  /fsx/ubuntu/nanoVLM/nanoVLM/models/config.py
```

## 8. Build and Configure the NaNoVLM Job Container
The provided Dockerfile (`nanoVLM.Dockerfile`) will set up the environment with all required dependencies:

```bash
cd ..
docker build -t nanovlm:latest -f nanovlm.Dockerfile .
enroot import -o nanovlm.sqsh  dockerd://nanovlm:latest


```
## 9. Launch Training

```bash
cd 
sbatch launch_training.sbatch
```
Note the path where the checkpoints will be generated from the slurm.out log file as this will be used in the subsequent sections for evaluation and generation

For example:

```
/fsx/ubuntu/nanoVLM/checkpoints/nanoVLM_siglip2-base-patch16-512_1024_mp4_SmolLM2-360M-Instruct_2xGPU_5000samples_bs8_500_lr_vision_5e-05-language_5e-05-0.00512_0923-230408/step_450
```

## 10. Run evaluation
Update the checkpoint directory in launch_evaluation.sh to the checkpoint we generated above

```
export CHECKPOINT_DIR="your-checkpoint-directory"
```

```bash
cd 
sbatch launch_evaluation.sbatch
```

## 11. Test generation
Export the checkpoint directory in your terminal

```
export CHECKPOINT_DIR="your-checkpoint-directory"
```

```bash
cd ..
python generate.py --checkpoint $CHECKPOINT_DIR

```
