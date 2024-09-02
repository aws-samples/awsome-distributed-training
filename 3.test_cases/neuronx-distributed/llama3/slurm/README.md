# How to run continual pretraining of Llama3 using Amazon Trainium on Slurm

## Prerequisits 

This guide assumes that you have following:
* Slurm cluster using 16 [trn1.32xlarge](https://aws.amazon.com/ec2/instance-types/trn1/) instances with a shared parallel filesystem such as [Amazon FSx for Lustre](https://docs.aws.amazon.com/fsx/latest/LustreGuide/getting-started.html). 


The subsequent sections presume that you are operating from the home directory of this head node as the `ubuntu` user.


### Setting up software stack

In this step, you will prepare the software stack and scripts needed for the next stage. Specifically, you wil:

1. Create a Python virtual environment, including Neuron Distributed, used for the pretraining task.
2. Fetch scripts used for the Llama3-70B model training.

#### Python virtual environment preparation

First, we create python virtual environment installing `torch-neuronx` and `neuronx-distributed` .

```bash
# Install Python
sudo apt-get install -y python3.8 python3.8-venv
# Create Python venv
python3.8 -m venv /fsx/ubuntu/aws_neuron_venv_pytorch 

# Activate Python venv 
source /fsx/ubuntu/aws_neuron_venv_pytorch/bin/activate 
python -m pip install -U pip 

# Install wget, awscli, and huggingface-cli
python -m pip install wget awscli huggingface_hub

# Set pip repository pointing to the Neuron repository 
python -m pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com
# Install Neuron Compiler and Framework
python -m pip install torch-neuronx=="1.13.1.1.15.0" neuronx-cc=="2.14.213.0" neuronx_distributed=="0.8.0" torchvision
```

This test case tested with  Neuron SDK 2.19.1 which includes the following software stack:

```bash
$ srun -N1 dpkg -l | grep neuron # This command runs on a compute instance (trn1.32xlarge)
aws-neuronx-collectives 2.21.46.0-69b77134b amd64 neuron_ccom built using CMake
aws-neuronx-dkms 2.17.17.0 amd64 aws-neuronx driver in DKMS format.
aws-neuronx-oci-hook 2.4.4.0 amd64 neuron_oci_hook built using CMake
aws-neuronx-runtime-lib 2.21.41.0-fb1705f5f amd64 neuron_runtime built using CMake
aws-neuronx-tools 2.18.3.0 amd64 Neuron profile and debug tools
```


#### **Clone NxD repository and install additional dependencies**

In this last step of this section, we will fetch llama3 test case from  `neuronx-distributed` . The test case is included in the official repository, so first clone the repository under home directory.

```bash
git clone https://github.com/aws-neuron/neuronx-distributed.git \
          /fsx/ubuntu/neuronx-distributed
```

then copy the llama3 test case under home directory, then move to the directory:

```bash
cp -r /fsx/ubuntu/neuronx-distributed/examples/training/llama /fsx/ubuntu/llama
cp /fsx/ubuntu/neuronx-distributed/examples/training/checkpoint_converter.py /fsx/ubuntu/llama
cd /fsx/ubuntu/llama
```

finally, install additional dependencies using pip

```bash
source /fsx/ubuntu/aws_neuron_venv_pytorch/bin/activate
python -m pip install -r requirements.txt
```

## Llama3 continual pretraining 

In this section, we will conduct Llama3 continual pretraining with Neuron Distributed. To scale the training process, we use 3D parallelism.  3D parallelism integrates data, model, and pipeline parallelism into a cohesive framework, creating a three-dimensional mesh of devices. Each axis of this mesh corresponds to one of the parallelism strategies:

* Data Parallelism Axis: Distributes the training data across devices.
* Pipeline Parallelism Axis: Distributes the model's layers across devices.
* Tensor Parallelism Axis: Parallelizes the individual layers across devices.

This combination allows for efficient scaling and utilization of hardware resources. For instance, tensor parallelism requires the highest communication bandwidth and is best suited for Trainium chips within the same Trn1 node with strong NeuronLink interconnect. Pipeline parallelism, which has lower communication requirements, can be used across nodes. Data parallelism, which requires the least communication, can span across multiple nodes. 
This section consists of the following three steps:

* **Step 1: Download llama3 model and tokenizer**
    In this step, we will download llama3 model checkpoints and tokenizer.  Subsequently, we will convert the checkpoints based on the distributed training configuration.
* **Step 2: Download and preprocess wiki-corpus dataset**
    In this step, you will learn how to retrieve and tokenize pretraining dataset take  `wiki-corpus` as an example. 
* **Step 3: Run continual pretraining job with Neuron Distributed**
    In this last step, we will learn how to scale Llama3 pretraining process 

This section assumes that you have completed the previous section and activated the virtual environment

```bash
# On the headnode
cd /fsx/ubuntu/llama
source /fsx/ubuntu/aws_neuron_venv_pytorch/bin/activate
```

### Step1: Download llama3 model and tokenizer

First, create a Hugging Face account to retrieve a [token](https://huggingface.co/settings/tokens.). Log in to your account and create an access token from Hugging Face Tokens. Then apply for Llama3 weight access from [Meta-Llama-3-70B](https://huggingface.co/meta-llama/Meta-Llama-3-70B) page.

Save the token onto the head node and download the Llama model:

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

Now you are ready to grab llama3 model weights:


```bash
huggingface-cli download meta-llama/Meta-Llama-3-70B --local-dir /fsx/ubuntu/Meta-Llama-3-70B
```

Once the download process is completed, you will see the following structure:

```bash
/fsx/ubuntu/Meta-Llama-3-70B/
├── LICENSE
├── README.md
├── USE_POLICY.md
├── config.json
├── generation_config.json
├── model-00001-of-00030.safetensors
...
├── model-00030-of-00030.safetensors
├── model.safetensors.index.json
├── original
│   ├── consolidated.00.pth
....
│   ├── consolidated.07.pth
│   ├── params.json
│   └── tokenizer.model
├── special_tokens_map.json
├── tokenizer.json
└── tokenizer_config.json
```

Copy tokenizer configs under the test case repository.

```bash
cp /fsx/ubuntu/Meta-Llama-3-70B/tokenizer* /fsx/ubuntu/llama
```

#### Convert Llama3 model weighs

Neuron Distributed requires its checkpoints to be pre-sharded based on the parallel processing configuration (tensor parallel degree and pipeline parallel degree). This preprocessing involves two main steps:

* Save original checkpoint into single binary file. This file will be used in the next step.
* Shard the checkpoints using the `convert_checkpoints.py` utility script.

First, we need to save the original checkpoint into a single binary file. Below is a small script named `save-llama3-70B-model.py` to accomplish this:

```
cat <<EOF > save-llama3-70B-model.py
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch

model = AutoModelForCausalLM.from_pretrained("/fsx/ubuntu/Meta-Llama-3-70B")
torch.save(model.state_dict(), '/fsx/ubuntu/llama-3-70b.pt')
EOF
```

Submit the job with the following command to run the process on a compute node (`trn1.32xlarge`) which has sufficient memory to load the model:

```bash
sbatch --job-name=save-checkpoints --output=logs/save-checkpoints.out \
       --wrap "srun python save-llama3-70B-model.py"
```

Next, we use the `convert_checkpoints.py` script to shard the checkpoints. Execute the following command to shards based on the distributed training setting we are going to use in the next step:

```bash
mkdir -p /fsx/ubuntu/llama3_70B/pretrained_weight
sbatch --job-name=convert-checkpoint --output=logs/convert-checkpoint.out \
       --wrap "\
              srun python convert_checkpoints.py \
              --tp_size 32 --pp_size 8 --n_layers 80 \
              --save_xser 1 \
              --kv_size_multiplier 4 \
              --qkv_linear 1 \
              --input_dir /fsx/ubuntu/llama-3-70b.pt \
              --output_dir /fsx/ubuntu/llama3_70B/pretrained_weight \
              --config /fsx/ubuntu/Meta-Llama-3-70B/config.json \
              --convert_from_full_state"
```

You can track the progress with

```bash
tail -f logs/convert-checkpoint.out
```

During the sharding process, you will see outputs like:

```bash
Saving to /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_00_tp_rank_00_pp_rank_00.pt
Saving to /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_00_tp_rank_00_pp_rank_01.pt
Saving to /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_00_tp_rank_00_pp_rank_02.pt
Saving to /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_00_tp_rank_00_pp_rank_03.pt
Saving to /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_00_tp_rank_00_pp_rank_04.pt
Saving to /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_00_tp_rank_00_pp_rank_05.pt
...
```

This process will shard the model per tensor parallel and pipeline parallel dimensions. In this case, we have `32x8=256` checkpoints.
Verify the number of checkpoints with:

```bash
ls /fsx/ubuntu/llama3_70B/pretrained_weight/model/dp_rank_*_tp_rank_*_pp_rank_*.pt | wc -l
256
```

As mentioned in the introduction of this section, the sharding ought to take hardware and cluster setup into account. Specifically, in our example, we have 16 trn1.32xlarge instances deployed on the HyperPod cluster. Each trn1.32xlarge instance has 16 Trainium Neuron Devices, each with 2 NeuronCore-v2, totaling 32 NeuronCore-v2 per instance, and 512 NeuronCore-v2 in the entire cluster.
We divide the Llama3-70B model’s 80 layers into different stages, each containing the first 10 layers, second 10 layers, ..., 8th 10 layers, and assign them to 8 Trn1 instances. Each stage is further split with Tensor Parallelism, dividing the stage’s parameters across 32 NeuronCore-v2. Since we will have two replicas of the sharded models, we employ data parallelism with a degree of two to speed up the training process.
The resultant checkpoints will be used in the next continual pretraining stage. 

### **Step 2: Download and preprocess wiki-corpus datasets**

Next, we will download `wiki-corpus` dataset and tokenize it for later training with `get_dataset.py` script inside the `llama` directory. We use `sbatch`  command to submit the data processing job to the cluster:

```bash
sbatch --job-name=get_dataset --output=logs/get_dataset.out \
       --wrap="srun python get_dataset.py"
```

It will create a job named `get_dataset`  and dump outputs into `logs/get_dataset.out` . You can track the progress with the following command:

```bash
tail -f logs/get_dataset.out 
```

The example output is as follows:

```bash
Downloading data: 100%|██████████| 1.35G/1.35G [02:49<00:00, 7.94MB/s] 
Generating train split: 100%|██████████| 1359146/1359146 [01:11<00:00, 19139.43 examples/s]
Running tokenizer on dataset: 100%|██████████| 1359146/1359146 [07:13<00:00, 3132.18 examples/s]
Grouping texts in chunks of 8192: 100%|██████████| 1359146/1359146 [10:19<00:00, 2194.09 examples/s]
94025
Saving the dataset (21/21 shards): 100%|██████████| 94025/94025 [00:18<00:00, 5139.19 examples/s]
```

and resultant data will be saved under `examples_datasets` directory.

```bash
/fsx/ubuntu/examples_datasets/wikicorpus_llama3_tokenized_8k/
├── data-00000-of-00021.arrow
...
├── data-00020-of-00021.arrow
├── dataset_info.json
└── state.json
```

### Section 3: Run continual pretraining job with Neuron Distributed

Now that we have preprocessed data and checkpoints and ready to submit continual pretraining job.  We have two subdirectories under `/fsx/ubuntu/llama`, `tp_pp_llama_hf_pretrain`,  and `tp_zero1_llama_hf_pretrain`. In this test case, we use the former. Copy the relevant files into the current directory:

```bash
mv tp_pp_llama_hf_pretrain/* .
```

Notice that you have template scripts per model inside the directory: 

```bash
$ ls /fsx/ubuntu/llama
13B_config_llama2  __pycache__               convert_checkpoints.py  llama3-70B-save.py  lr.py                  requirements_ptl.txt     run_llama2_70B_tp_pp.sh  save-llama3-70B-model.py  tp_pp_llama_hf_pretrain
70B_config_llama2  activation_checkpoint.py  get_dataset.py          logger.py           modeling_llama_nxd.py  results.json             run_llama3_70B_tp_pp.sh  tokenizer.json            tp_zero1_llama_hf_pretrain
70B_config_llama3  checkpoint_converter.py   lightning               logs                requirements.txt       run_llama2_13B_tp_pp.sh  run_llama_nxd.py         tokenizer_config.json     training_utils.py
```

We need to modify few lines in this script to run continual training with Llama3 70B model using the weights and data you have processed in the previous steps.
**Modification 1:**
Contrary to the cluster setup, the script assumes the shared directory to be `/shared`. Modify them to `/fsx/ubuntu`  (our home directory) as follows:

```bash
sed -i 's/\/shared/\/fsx\/ubuntu/g' run_llama3_70B_tp_pp.sh
```

**Modification 2:**
Before submitting the job, we need to modify a few arguments in `torchrun`  in `run_llama3_70B_tp_pp.sh` to minimize human intervention:

1. **Enable Pretrained Weights**: Neuron Distributed default initiates training without using pretrained weights. To enable the use of pretrained weights, set the value of the  `--pretrained_weight` argument to `1`.
2. **Change Checkpoint Frequency**: Modify the value of the `--checkpoint_freq` argument to `m` (an integer) to save checkpoints every `m` steps.
3. **Manage Checkpoint Storage**: The current version of Neuron Distributed generates checkpoints roughly 850 GB in size for the 70B model training. Saving all historical checkpoints can consume too much space. Modify the value of the `--num_kept_checkpoint` argument to `n` (an integer) to keep only the latest `n` checkpoints.
4. **Ensure Latest Checkpoint Loading**: To ensure the training process always starts from the latest checkpoint, set the value of the `--loading_step` argument to `latest_if_exists`. This is crucial in the event of hardware failure. As mentioned earlier, Hyperpod provides an auto-resume functionality. If a job fails due to hardware issues, Hyperpod initiates node replacement and restarts the job using the same script. This script must load the latest checkpoints when training resumes.

```bash
torchrun $DISTRIBUTED_ARGS run_llama_nxd.py \
        ...
        --pretrained_weight 1 \ # Change value
        ...
        --checkpoint_freq 5 \ # change value
        --num_kept_checkpoint 2 \ # Change value
        --loading_step latest_if_exists \ # Change value
        --tb_dir $tb_dir |& tee $LOG_PATH/log
exit ${PIPESTATUS[0]}        
```

Using the updated `run_llama3_70B_tp_pp.sh` script, submit the training job as follows:

```bash
sbatch --job-name run_llama3_70B \
       --output logs/run_llama3_70B.out \
       --exclusive --nodes 16 \
       --wrap="srun bash run_llama3_70B_tp_pp.sh"
```

If you are on HyperPod add the `--auto-resume=1` flag as follows:
```bash
sbatch --job-name run_llama3_70B \
       --output logs/run_llama3_70B.out \
       --exclusive --nodes 16 \
       --wrap="srun `--auto-resume=1 `bash run_llama3_70B_tp_pp.sh"
```

This flag indicates that the `srun` command should be automatically retried in case of hardware failure.

You can track job progress as follows:

```bash
tail -f logs/run_llama3_70B.out
```

After a while you will see the following outputs in the log, indicating that the training progressing as expected:

```bash
step 1 step_time 433.9763135910034s throughput 2.3233670754725364 seq/s loss 1.686337987310253 grad norm 10.75
step 2 step_time 287.74868535995483s throughput 2.782773814597335 seq/s loss 1.6844543347833678 grad norm 11.0625
step 3 step_time 285.0779552459717s throughput 2.9877511544511997 seq/s loss 1.6992562628001906 grad norm 11.4375
step 4 step_time 285.1162803173065s throughput 3.102014096248735 seq/s loss 1.6663736239424907 grad norm 10.8125
step 5 step_time 285.26683378219604s throughput 3.1748703415103368 seq/s loss 1.6787556377821602 grad norm 11.25
[2024-07-30 08:36:48.284: I neuronx_distributed/trainer/checkpoint.py:135] synced saving of checkpoint step_5 completed
...
```

and the training process creates checkpoints in every `m` steps as follows:

```text
/fsx/ubuntu/llama3_70B/
├── pretrained_weight
│   └── model
└── step_5
    ├── checkpoint
    ├── done
    ├── model
    ├── optim
    ├── scheduler.pt
    └── user_content.pt
```

### Test Auto-resume functionality

> [!IMPORTANT]  
> This section is applicable only when you are on HyperPod and running the training with `--auto-resume=1` flag.

Remember that the job submission command used in the previous section includes `--auto-resume=1` flag. This instructs HyperPod to run the auto resume process. In this section, we'll dive into testing the auto-resume functionality of HyperPod by simulating an error in one of the compute instances. This will help us observe how HyperPod handles node failures and resumes the job seamlessly.

**Step1: Monitor the Training Log**
First, open a terminal and use the `tail` command to monitor the training log:

```bash
tail -f logs/run_llama3_70B.out
```

**Step2: Identify and login to the Compute Instance we will inject the error**
Open another terminal to identify the compute instances allocated to the training job using the `squeue` command. The output should look like follows:

```
JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                82       dev run_llam   ubuntu  R      43:06     16 ip-10-1-10-50,ip-10-1-16-50,ip-10-1-25-242,ip-10-1-33-0,ip-10-
1-40-177,ip-10-1-45-129,ip-10-1-48-81,ip-10-1-63-78,ip-10-1-65-[134,171],ip-10-1-85-226,ip-10-1-92-96,ip-10-1-97-129,ip-10-1-102-1
84,ip-10-1-115-121,ip-10-1-127-124
```

Choose one of the instances and log in to it with `ssh`,

```bash
ssh ip-10-1-16-50
```

Switch to the root user:

```bash
sudo su - root
```

**Step3: Inject an Artificial Error and Crash the Training Process**
Inject an artificial error with the following command:

```bash
echo "1" >> /var/run/sagemaker_healthcheck_status
```

Now let’s crash the training process. First, check the training processes:

```bash
ps -aux | grep run_llama
```

You will see multiple Python processes running `run_llama_nxd.py` . Pick up one of them and note the process ID:

```text
ubuntu   1578513 16.6  0.9 23848992 4809184 ?    Sl   08:04   7:41 /fsx/ubuntu/aws_neuron_venv_pytorch/bin/python -u run_llama_nxd.py --train_batch_size 512 --use_meta_device_init 1 --training_dir /fsx/ubuntu/examples_datasets/wikicorpus_llama3_tokenized_8k --training_config /fsx/ubuntu/llama/70B_config_llama3 --max_steps 30000 --seq_len 8192 --pipeline_parallel_size 8 --tensor_parallel_size 32 --num_microbatches 512 --lr 0.000015 --min_lr 1e-06 --beta1 0.9 --beta2 0.95 --weight_decay 0.1 --warmup_steps 2000 --constant_steps 0 --use_zero1_optimizer 1 --use_selective_checkpoint 1 --use_flash_attention 1 --qkv_linear 1 --kv_replicator 4 --pretrained_weight 1 --save_load_xser 1 --checkpoint_dir /fsx/ubuntu/llama3_70B/ --checkpoint_freq 5 --num_kept_checkpoint 2 --loading_step latest_if_exists --tb_dir /fsx/ubuntu/tensorboard/llama3_70B_16nodes_82
```

Kill the process using its ID:

```bash
kill -9 1578513
```

**Step4: Observe Auto-Resume Behavior**
After killing the process, check the first terminal we opened in the step1 to see HyperPod initiating the node replacement:

```text
[Auto Resume] Info: JobID: 82 StepID: 0 Initiating communication with cluster agent to diagnose health of nodes
[Auto Resume] Info: JobID: 82 StepID: 0 Response from cluster agent: JobId=82, ResumeAction=RETRYSTEP
[Auto Resume] Info: JobID: 82 StepID: 0 Job failed - replacing nodes
[Auto Resume] Info: JobID: 82 StepID: 0 Job failed - Droping unhealthy nodes
[Auto Resume] Info: JobID: 82 StepID: 0 Succesfully shrink job to retain healthy nodes ip-10-1-10-50,ip-10-1-25-242,ip-10-1-33-0,ip-10-1-40-177,ip-10-1-45-129,ip-10-1-48-81,ip-10-1-63-78,ip-10-1-65-[134,171],ip-10-1-85-226,ip-10-1-92-96,ip-10-1-97-129,ip-10-1-102-184,ip-10-1-115-121,ip-10-1-127-124
srun: job 83 queued and waiting for resources
```

Open one more terminal and run the `sinfo` command to verify the status of the nodes. The output should indicate that the error-injected instance is in a failed state:

```text
PARTITION     AVAIL  TIMELIMIT  NODES  STATE NODELIST
dev*             up   infinite      1   fail ip-10-1-16-50
dev*             up   infinite     15  alloc ip-10-1-10-50,ip-10-1-25-242,ip-10-1-33-0,ip-10-1-40-177,ip-10-1-45-129,ip-10-1-48-81
,ip-10-1-63-78,ip-10-1-65-[134,171],ip-10-1-85-226,ip-10-1-92-96,ip-10-1-97-129,ip-10-1-102-184,ip-10-1-115-121,ip-10-1-127-124
```

Finally, observe on the first terminal that HyperPod retries the last failed training step:

```text
[Auto Resume] Info: JobID: 82 StepID: 0 Job Expansion complete
[Auto Resume] Info: JobID: 82 StepID: 0 Updating to new node list ip-10-1-10-50,ip-10-1-16-50,ip-10-1-25-242,ip-10-1-33-0,ip-10-1-40-177,ip-10-1-45-129,ip-10-1-48-81,ip-10-1-63-78,ip-10-1-65-[134,171],ip-10-1-85-226,ip-10-1
-92-96,ip-10-1-97-129,ip-10-1-102-184,ip-10-1-115-121,ip-10-1-127-124
[Auto Resume] Info: JobID: 82 StepID: 0 Retrying step. Attempt number: 1
...
step 6 step_time 458.5973925590515s throughput 2.114068580652976 seq/s loss 1.6739352685399354 grad norm 10.125
step 7 step_time 286.14009380340576s throughput 2.6113168478814535 seq/s loss 1.696257982752286 grad norm 10.875
step 8 step_time 285.018018245697s throughput 2.8531960686487 seq/s loss 1.6922309934161603 grad norm 10.5625
step 9 step_time 285.1258006095886s throughput 2.9929221242903936 seq/s loss 1.6782752611325122 grad norm 12.75
...
```

Congratulations! You have successfully tested the auto-resume functionality of HyperPod. This process ensures that your training jobs can recover from node failures with minimal disruption. HyperPod's auto-resume feature monitors the state of Slurm nodes and automatically initiates a node replacement workflow if a failure is detected, allowing the job to restart from the last saved checkpoint once the faulty nodes are replaced.
