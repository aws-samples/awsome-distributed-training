# Pythia GPT-NeoX Test Case <!-- omit in toc -->

GPT-NeoX is an [EleutherAI](https://www.eleuther.ai)'s library for training large-scale language models on GPUs. This framework is based on [NVIDIA's Megatron Language Model](https://github.com/NVIDIA/Megatron-LM) and has been augmented with techniques from [DeepSpeed](https://www.deepspeed.ai) as well as some novel optimizations. This test case illustrates how to train [Pythia](https://arxiv.org/abs/2304.01373) model using GPT-Neox. 

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you set up a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to set the following environment variables to run this test case:

```bash
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/gpt-neox.sqsh
export FSX_PATH=/fsx
export DATA_PATH=$FSX_PATH/pile_subset     # use pile to download entire dataset (see 4. Data preparation)
export MODEL_PATH=$FSX_PATH/gpt-neox
export TEST_CASE_PATH=${HOME}/15.gpt-neox  # where you copy the test case or set to your test case path
cd $TEST_CASE_PATH                         # Note that we assume that you are here during the following command executions
```



## 2. Build the container

Before running training jobs, you need to use a build docker container image. [Enroot](https://github.com/NVIDIA/enroot) will be used to turn the image into unprivileged sandbox for Slurm. 
You can build the image on your login node using the option 1 below, but build step could overwhelm it as it will compile [flash-attention](https://github.com/Dao-AILab/flash-attention).
If you want to avoid that, follow steps in option 2.

### Option 1: Bulid image on login node

Below are the steps you need to follow:


1. Build the Docker image with the command below in this directory.

   ```bash
    docker build -t gpt-neox -f 0.gpt-neox.dockerfile .
   ```

If you wish to reduce memory footprint of the build process, consider tweaknig `MAX_JOBS` for `flash-attn` compile (in `0.gpt-neox.dockerfile` line 172).

2. Once the Docker image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```bash
    REPOSITORY   TAG       IMAGE ID       CREATED          SIZE
    gpt-neox     latest    b6c49033c424   9 minutes ago    24.7GB
   ...
   ```

3. Convert the Docker image to a squash file with the command below.

   ```bash
   enroot import -o ${ENROOT_IMAGE} dockerd://get-neox:latest
   ```

   The file will be stored in the `/apps` directory (default). The output should look as below.

    ```bash
    [INFO] Fetching image

    36a8c752c28a2db543d2a632a3fc1fcbd5789a6f3d45b9d3a24632420dedcfa8

    [INFO] Extracting image content...
    [INFO] Creating squashfs filesystem...

    Parallel mksquashfs: Using 32 processors
    Creating 4.0 filesystem on /apps/gpt-neox.sqsh, block size 131072.
    [========================================================================================================================================================================================================================-] 291068/291068 100%

    Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
            uncompressed data, uncompressed metadata, uncompressed fragments, uncompressed xattrs
            duplicates are not removed
    ...
    ```

Once done proceed to the next stage.

### Option 2: Build image on a compute node

In this option, you will use a compute node to build the image. Submit the job as:

    ```bash
    sbatch 1.build-image.sbatch
    ```


## 4. Dataset preparation

This test case uses the [C4 dataset](https://paperswithcode.com/paper/exploring-the-limits-of-transfer-learning). In this section, you will retrieve and tokenize the dataset.

We will use GPT-NeoX-20B tokenizer. Place the tokenizer file as follows. 

```bash
mkdir -p ${MODEL_PATH}/tokenizers
wget https://the-eye.eu/public/AI/models/GPT-NeoX-20B/slim_weights/20B_tokenizer.json -O ${MODEL_PATH}/tokenizers/20B_tokenizer.json
```

To retrieve and tokenize the Pile dataset, we use `prepare_data.py` of NeoX through container. The exact steps are described in `1.prepare-data.sbatch`.

```bash
sbatch 2.prepare-data.sbatch
```

By default, the script only downloads subset of the dataset. Use the following if you wish to download whole C4 dataset:
```bash
DATASET=c4 sbatch 2.prepare-data.sbatch
```

You will see the following data after the job.

```bash
$ ls ${DATA_PATH}/c4_openwebtext/
c4-train.00000-of-01024.jsonl  c4-train.00002-of-01024.jsonl  c4_openwebtext_text_document.bin
c4-train.00001-of-01024.jsonl  c4-train.00003-of-01024.jsonl  c4_openwebtext_text_document.idx
```

## 5. Model training

GPT-NeoX parameters are defined in a YAML configuration file which is passed to the `deepy.py` launcher.
Parameters originate from either the [DeepSpeed runner CLI (DSL)](https://github.com/microsoft/DeepSpeed/blob/master/deepspeed/launcher/runner.py#L33), [DeepSpeed configuration file (DSC)](https://www.deepspeed.ai/docs/config-json/), [Megatron-LM CLI (Meg)](https://github.com/NVIDIA/Megatron-LM/blob/main/megatron/arguments.py#L224) or are GPT-NeoX (NeoX) modifications. See [the configuration README](https://github.com/EleutherAI/gpt-neox/blob/main/configs/README.md) of NeoX repository. You need to make few changes to the config files to make it work on a Slurm cluster. Firstly, you need to tell where to retrieve training data and model checkpoints.

```json
    "vocab_file": "/fsx/gpt-neox/tokenizers/20B_tokenizer.json",
    "save": "/fsx/gpt-neox/models/pythia/1-4B_checkpoints",
    "load": "/fsx/gpt-neox/models/pythia/1-4B_checkpoints",
    "data_path": " /fsx/c4_subset/c4_openwebtext/c4_openwebtext_text_document",
```

Additionally, you need to modify all of your configs to conform to the JSON. When launching a GPT-NeoX job you can specify multiple YAML config files. Internally, all of these files are merged into one config and then passed as a single long command line argument to DeepSpeed. When using SLURM and its internal command srun, python fails to parse this long command line argument unless it is in the more restrictive JSON format. This test case prepares sample JSON configs in `configs/pythia` directory.

Note: `gas` (`gradient_accumulation_steps`) in the original `pythia` config has been removed in the JSON configs. See https://github.com/EleutherAI/gpt-neox/pull/1144 for details.

Launch distributed training using `3.train.sbatch`.

```bash
sbatch 3.train.sbatch
````

By default, the 1.4 B model will be trained. You may modify the `MODEL_CONFIG` variable in the script to train different sizing. 

