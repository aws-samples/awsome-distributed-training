# 1. Problem 
Large Language Model - GPT3 175B

## Requirements
* [PyTorch 23.09-py3 NGC container](https://ngc.nvidia.com/registry/nvidia-pytorch)
* Slurm with [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) (multi-node)
* [nvidia-docker](https://github.com/NVIDIA/nvidia-docker) (single-node)

# 2. Directions

## Steps to run benchmark.

### Steps to configure the training setup
Launch configuration and system-specific hyperparameters for the appropriate
NVIDIA DGX submission are in the `config_DGXH100_*.sh` scripts.

Data related variables (PREPROC_DATA, SPM, LOAD_CHECKPOINTS_PATH) are not
covered in the config files and must be set separately. 

### Steps to launch training

1. Build the container and push to a docker registry:
```
docker build --pull -t <docker/registry>/mlperf-nvidia:large_language_model-pytorch .
docker push <docker/registry>/mlperf-nvidia:large_language_model-pytorch
```
2. Launch the training:
```
source config_DGXH100_64x8x128x4x8_mbs1.sh  # use appropriate config
CONT="<docker/registry>/mlperf-nvidia:large_language_model-pytorch LOGDIR=<path/to/output/dir> PREPROC_DATA=<path/to/dataset> SPM=<path/to/tokenizer/model> LOAD_CHECKPOINTS_PATH=<path/to/checkpoint> sbatch -N $DGXNNODES -t $WALLTIME run.sub
```
### Hyperparameter settings

Hyperparameters are recorded in the `config_*.sh` files for each configuration and in `run_and_time.sh`.

# 3. Dataset/Environment
Please refer to the [instructions](https://github.com/mlcommons/training/blob/master/large_language_model/megatron-lm/README.md#3-datasetenvironment) from the reference to download the dataset.
Separate tokenizer files download can be skipped - the unpacked dataset archive already contains the required tokenizer `c4_en_301_5Mexp2_spm.model` in the `spm` directory.

The C4 dataset location (`preprocessed_c4_spm` directory) should be set as PREPROC_DATA variable and the tokenizer location (the `c4_en_301_5Mexp2_spm.model` **file**) as the SPM variable. 

# 4. Model
### Publication/Attribution
[Megatron](https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/stable/nlp/nemo_megatron/intro.html) is a large, powerful transformer developed by the Applied Deep Learning Research team at NVIDIA. This repository uses [Nemo Megatron](https://github.com/NVIDIA/NeMo). NeMo Megatron GPT has been integrated with [NVIDIA Transformer Engine](https://github.com/NVIDIA/TransformerEngine). Transformer Engine enables FP8 training on NVIDIA Hopper GPUs.

### List of Layers

The model largely follows the GPT3 [paper](https://arxiv.org/abs/2005.14165), refer [here](https://github.com/mlcommons/training/tree/master/large_language_model/megatron-lm#list-of-layers) for model details.

### Model checkpoint
In the benchmarking region, we resume training from a reference checkpoint which is trained with Global Batch Size of 1536 for 4000 iterations. 

Please refer to the [instructions](https://github.com/mlcommons/training/blob/master/large_language_model/megatron-lm/README.md#checkpoint-download) from the reference to download the BF16 model checkpoint.
The postprocessing step can be skipped - the `gpt3/megatron-lm/checkpoint_nemo_bf16.tar` is already NeMo-compatible after unpacking.

The `LOAD_CHECKPOINTS_PATH` variable should be set to the **parent** directory of the `ckpt4000-consumed_samples=0` checkpoint.

For more details on the checkpoint format, please refer to the reference checkpoint [description](https://github.com/mlcommons/training/blob/master/large_language_model/megatron-lm/README.md#model-checkpoint). 

# 5. Quality

### Quality metric
Log Perplexity

### Quality target
2.69

### Evaluation frequency
Evaluate after every 24576 samples (=50.33B tokens)

### Evaluation thoroughness
Evaluation on the validation subset that consists of 24567 examples.


# 6. Additional notes

### Config naming convention

`<number of nodes DGXNNODES>x<number of gpus per node>x<mini batch size>x<tensor parallelism TENSOR_MODEL_PARALLEL>x<pipeline parallelism PIPELINE_MODEL_PARALLEL>`

```
MP = TP * PP
DP = WS // MP
miniBS = GBS // DP
```
where: 
```
MP = model parallelism
TP = tensor parallelism
PP = pipeline parallelism
DP = data parallelism
WS = world size (number of nodes x number of gpus per node)
GBS = global batch size
```
Note: changing `MICRO_BATCH_SIZE` doesn't affect GBS or any of the above parameters.
Effectively it controls gradient accumulation (`GA = miniBS // microBS`).

### Seeds
NeMo produces dataset index shuffling only on one process and holds the `SEED` value in the file name.
Thus, all processes need to have the same value of `SEED` otherwise will not be able to read the data.
The `SEED` environment variable can be set prior to launching the job, otherwise it is set in `run.sub`.