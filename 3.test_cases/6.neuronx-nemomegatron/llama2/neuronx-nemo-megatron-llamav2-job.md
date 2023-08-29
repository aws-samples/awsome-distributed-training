# Launch a Llama2 pretraining job using neuronx-nemo-megatron

This tutorial explains how to run Llama V2 pretraining jobs with AWS EC2 trn1.32xl instances using [neuronx-nemo-megatron](https://github.com/aws-neuron/neuronx-nemo-megatron) and [AWS ParallelCluster](https://aws.amazon.com/hpc/parallelcluster/).

neuronx-nemo-megatron (also known as "AWS Neuron Reference for NeMo Megatron") includes modified versions of the open-source packages [NeMo](https://github.com/NVIDIA/NeMo) and [Apex](https://github.com/NVIDIA/apex) that have been adapted for use with AWS Neuron and AWS EC2 Trn1 instances. neuronx-nemo-megatron allows for pretraining models with hundreds of billions of parameters across thousands of Trainium accelerators, and enables advanced training capabilities such as 3D parallelism, sequence parallelism, and activation checkpointing.

## Prerequisites
Before proceeding with this tutorial, please follow [these instructions](https://github.com/aws-neuron/aws-neuron-parallelcluster-samples#train-a-model-on-aws-trn1-parallelcluster) to create a ParallelCluster consisting of 1 or more trn1.32xl or trn1n.32xl nodes. ParallelCluster automates the creation of trn1 clusters, and provides the SLURM job management system for scheduling and managing distributed training jobs. Please note that the home directory on your ParallelCluster head node will be shared with all of the worker nodes via NFS.

## Install neuronx-nemo-megatron

With your trn1 ParallelCluster in place, begin by logging into the head node of your cluster using SSH. To provide access to TensorBoard (required in a later step), please make sure that you enable port forwarding for TCP port 6006 when you login, ex:
```
ssh -i YOUR_KEY.pem ubuntu@HEAD_NODE_IP_ADDRESS -L 6006:127.0.0.1:6006
```

Once logged into the head node, activate the provided PyTorch Neuron virtual environment that was created when you set up your ParallelCluster. **Note**: if your PyTorch Neuron environment is lower than Neuron 2.11, please refer to the [Neuron documentation](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/frameworks/torch/torch-neuronx/setup/pytorch-update.html#pytorch-neuronx-update) for instructions on updating to Neuron 2.11 or later.
```
cd ~
source ./aws_neuron_venv_pytorch/bin/activate
```

Next, clone the neuronx-nemo-megatron repo to the head node:
```
cd ~
git clone https://github.com/aws-neuron/neuronx-nemo-megatron.git
cd neuronx-nemo-megatron
```

Install the `wheel` Python package and run the build script to create the neuronx-nemo-megatron wheels:
```
pip3 install wheel
./build.sh
```

Install the neuronx-nemo-megatron packages and dependencies in your virtual environment:
```
pip3 install ./build/*.whl
pip3 install -r requirements.txt torch==1.13.1 protobuf==3.20.3
```

Build the Megatron helper module
```
cd ~
python3 -c "from nemo.collections.nlp.data.language_modeling.megatron.dataset_utils import compile_helper; \
compile_helper()"
```

The above utility will help make this file : ```nemo.collections.nlp.data.language_modeling.megatron.dataset_utils``` and below is the expected output (You can ignore the error)
```
2023-Aug-17 22:53:01.0674 47940:47940 ERROR  TDRV:tdrv_get_dev_info                       No neuron device available
[NeMo W 2023-08-17 22:53:03 optimizers:67] Could not import distributed_fused_adam optimizer from Apex
[NeMo W 2023-08-17 22:53:04 experimental:27] Module <class 'nemo.collections.nlp.data.language_modeling.megatron.megatron_batch_samplers.MegatronPretrainingRandomBatchSampler'> is experimental, not ready for production and is not fully supported. Use at your own risk.
```

## Download LlamaV2 dataset and tokenizer
This tutorial makes use of a Red pyjama dataset. The dataset can be downloaded to your cluster by running the following commands on the head node:

```
wget https://data.together.xyz/redpajama-data-1T/v1.0.0/book/book.jsonl
```

The above command will give you the raw dataset of around 50G which needs to be tokenized using a llamaV2 tokenizer. To tokenize the data, you need to request the tokenizer from hugging face and meta following the below link : 

[Request Tokenizer and model weights from hugging face](https://huggingface.co/meta-llama/Llama-2-7b)

Note: Use of this model is governed by the Meta license. In order to download the model weights and tokenizer, please visit the above website and accept our License before requesting access here.

Once you have the Tokenizer and the dataset. You can tokenize the dataset following the below command : 
```
python nemo/scripts/nlp_language_modeling/preprocess_data_for_megatron.py \
    --input=DATA_FOLDER/DATA.jsonl \
    --json-keys=text \
    --tokenizer-library=huggingface \
    --tokenizer-type=TOKENIZER_FOLDER/llama7b-hf \
    --dataset-impl=mmap \
    --output-prefix=DATA_FOLDER/DATA_tokenized \
    --append-eod \
    --need-pad-id \
    --workers=32
```

Post tokenizing the dataset, you will have a path to the tokenizer and the dataset which will be used for pretraining. 

## Llama2 training configurations
We tested with the following model sizes: 7B
### Llama2 7B

- Model configuration
    - Attention heads: 32
    - Layers: 32
    - Sequence length: 4096
    - Hidden size: 4096
    - Hidden FFN size: 11008
    - Microbatch size: 1
    - Global batch size: 256

- Distributed training configuration
    - Number of nodes: 4
    - Tensor parallel degree: 8
    - Pipeline parallel degree: 1
    - Data parallel degree: 16

## Pre-compile the model
By default, PyTorch Neuron uses a just in time (JIT) compilation flow that sequentially compiles all of the neural network compute graphs as they are encountered during a training job. The compiled graphs are cached in a local compiler cache so that subsequent training jobs can leverage the compiled graphs and avoid compilation (so long as the graph signatures and Neuron version have not changed).

An alternative to the JIT flow is to use the included [neuron_parallel_compile](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/frameworks/torch/torch-neuronx/api-reference-guide/training/pytorch-neuron-parallel-compile.html?highlight=neuron_parallel_compile) command to perform ahead of time (AOT) compilation. In the AOT compilation flow, the compute graphs are first identified and extracted during a short simulated training run, and the extracted graphs are then compiled and cached using parallel compilation, which is considerably faster than the JIT flow.

Before starting the compilation you need to update your path to the dataset and tokenizer in the llama_7b script as below : 

```
vi llama_7b.sh

# Update the below lines
# For tokenizer
model.tokenizer.type='PATH_TO_LLAMA_TOKENIZER/llamav2_weights/7b-hf' \

# For Dataset
model.data.data_prefix=[1.0,PATH_TO_TOKENIZED_DATASET/books/book.jsonl-processed_text_document] \
```
Run the following commands to launch an AOT pre-compilation job on your ParallelCluster:
```
cd ~/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling
sbatch --nodes 4 compile.slurm ./llama_7b.sh
```

Once you have launched the precompilation job, run the `squeue` command to view the SLURM job queue on your cluster. If you have not recently run a job on your cluster, it may take 4-5 minutes for the requested trn1.32xlarge nodes to be launched and initialized. Once the job is running, `squeue` should show output similar to the following:
```
    JOBID  PARTITION  NAME           USER    ST  TIME  NODES NODELIST(REASON)
    10     compute1   compile.slurm  ubuntu  R   5:11  4     compute1-dy-queue1-i1-[1-4]
```

You can view the output of the precompilation job by examining the file named `slurm-compile.slurm-ZZ.out` where ZZ represents the JOBID of your job in the `squeue` output, above. Ex:
```
tail -f slurm-compile.slurm-10.out
```

Once the precompilation job is complete, you should see a message similar to the following in the logs:
```
2023-06-11 23:04:08.000738: INFO ||PARALLEL_COMPILE||: Total graphs: 22
2023-06-11 23:04:08.000738: INFO ||PARALLEL_COMPILE||: Total successful compilations: 22
2023-06-11 23:04:08.000738: INFO ||PARALLEL_COMPILE||: Total failed compilations: 0
```

At this point, you can press `CTRL-C` to exit the tail command.

## Launch a pretraining job
The Llama2 pretraining job can be launched in the same manner as the precompilation job described above. In this case, we change the SLURM script from `compile.slurm` to `run.slurm`, but the other parameters remain the same:
```
cd ~/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling
sbatch --nodes 4 run.slurm ./llama_7b.sh
```


As outlined above, you can again use the `squeue` command to view the job queue. Once you see that your pretraining job is running, you can view the output of the training job by examining the file named `slurm-run.slurm-ZZ.out` where ZZ represents the JOBID of your job:
```
tail -f slurm-run.slurm-11.out
```

Once the model is loaded onto the Trainium accelerators and training has commenced, you will begin to see output indicating the job progress:
```
Epoch 0:  22%|██▏       | 4499/20101 [22:26:14<77:48:37, 17.95s/it, loss=2.43, v_num=5563, reduced_train_loss=2.470, gradient_norm=0.121, parameter_norm=1864.0, global_step=4512.0, consumed_samples=1.16e+6, iteration_time=16.40]
Epoch 0:  22%|██▏       | 4500/20101 [22:26:32<77:48:18, 17.95s/it, loss=2.43, v_num=5563, reduced_train_loss=2.470, gradient_norm=0.121, parameter_norm=1864.0, global_step=4512.0, consumed_samples=1.16e+6, iteration_time=16.40]
Epoch 0:  22%|██▏       | 4500/20101 [22:26:32<77:48:18, 17.95s/it, loss=2.44, v_num=5563, reduced_train_loss=2.450, gradient_norm=0.120, parameter_norm=1864.0, global_step=4512.0, consumed_samples=1.16e+6, iteration_time=16.50]
```

## Monitor training
### TensorBoard
In addition to the text-based job monitoring described in the previous section, you can also use standard tools such as TensorBoard to monitor training job progress. To view an ongoing training job in TensorBoard, you first need to identify the experiment directory associated with your ongoing job. This will typically be the most recently created directory under `~/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/nemo_experiments/megatron_llama`. Once you have identifed the directory, `cd` into it, and then launch TensorBoard:
```
cd ~/neuronx-nemo-megatron/nemo/examples/nlp/language_modeling/nemo_experiments/megatron_llama
ls -alt|head
# Identify the correct experiment directory in the
# output of the ls command, ex: 2023-06-10_00-22-42
cd YOUR_EXPERIMENT_DIR  # <- replace this with your experiment directory
tensorboard --logdir ./
```

With TensorBoard running, you can then view the TensorBoard dashboard by browsing to http://localhost:6006 on your local machine. If you cannot access TensorBoard at this address, please make sure that you have port-forwarded TCP port 6006 when SSH'ing into the head node, ex: `ssh -i YOUR_KEY.pem ubuntu@HEAD_NODE_IP_ADDRESS -L 6006:127.0.0.1:6006`

### neuron-top / neuron-monitor / neuron-ls
The [neuron-top](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-top-user-guide.html?highlight=neuron-top) tool can be used to view useful information about NeuronCore utilization, vCPU and RAM utilization, and loaded graphs on a per-node basis. To use neuron-top during on ongoing training job, first SSH into one of your compute nodes from the head node, and then run `neuron-top`:
```
ssh compute1-dy-queue1-i1-1  # to determine which compute nodes are in use, run the squeue command
neuron-top
```

Similarly, once you are logged into one of the active compute nodes, you can also use other Neuron tools such as [neuron-monitor](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html) and [neuron-ls](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html) to capture performance/utilization statistics and to understand NeuronCore allocation.

## Known issues/limitations
* The initial release of neuronx-nemo-megatron supports Llama2 pretraining only. Model evaluation will be available in a future release.
* neuronx-nemo-megatron currently requires pytorch-lightning v1.8.6

## Troubleshooting guide
See [Troubleshooting Guide for AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/troubleshooting-v3.html) for more details and fixes to common issues.
