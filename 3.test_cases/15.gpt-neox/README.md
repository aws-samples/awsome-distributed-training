# GPT-NeoX Test Case <!-- omit in toc -->

GPT-NeoX is an EleutherAI's library for training large-scale language models on GPUs. This framework is based on NVIDIA's Megatron Language Model and has been augemented with techniques from DeepSpeed as well as some novel optimizations. 

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you setup a Slurm cluster using the templates in the architectures [directory](../../1.architectures). You need to setup the following environment variables to run this test case:

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

Before running training jobs, you need to use an [Enroot](https://github.com/NVIDIA/enroot) container to retrieve and preprocess the input data. Below are the steps you need to follow:


1. Build the Docker image with the command below in this directory.

   ```bash
    docker build -t gpt-neox -f 0.gpt-neox.dockerfile .
   ```

2. Once the Docker image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```bash
    REPOSITORY   TAG       IMAGE ID       CREATED          SIZE
    gpt-neox     latest    b6c49033c424   9 minutes ago    24.7GB
   ...
   ```

3. TODO: fix Convert the Docker image to a squash file with the command below.

   ```bash
   enroot import -o ${ENROOT_IMAGE} dockerd://llm-foundry:latest
   ```

   The file will be stored in the `/apps` directory (default). The output should look as below.

    ```bash
    [INFO] Fetching image

    36a8c752c28a2db543d2a632a3fc1fcbd5789a6f3d45b9d3a24632420dedcfa8

    [INFO] Extracting image content...
    [INFO] Creating squashfs filesystem...

    Parallel mksquashfs: Using 32 processors
    Creating 4.0 filesystem on /apps/llm-foundry.sqsh, block size 131072.
    [========================================================================================================================================================================================================================-] 291068/291068 100%

    Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
            uncompressed data, uncompressed metadata, uncompressed fragments, uncompressed xattrs
            duplicates are not removed
    ...
    ```

It will take around 5 minutes to convert the container image from Docker to the Enroot format. Once done proceed to the next stage.


## 3. Create local environment

This test case relies on `deepy.py`, a wrapper around the deepspeed launcher. You create a virtual environment, so that we can call the script from the head node.

```bash
cd $TEST_CASE_PATH
python3.8 -m venv .venv
source .venv/bin/activate
pip install -r https://raw.githubusercontent.com/EleutherAI/gpt-neox/f36aed7ffd93fcb5d674236e476a5c80c0e31163/requirements/requirements.txt
```

## 4. Dataset preparation

This test case uses the [Pile dataset](https://arxiv.org/abs/2101.00027). In this section, you will retrieve and tokenize the dataset.

We will use GPT-NeoX-20B tokenizer. Place the tokenizer file as follows. 

```bash
mkdir -p ${MODEL_PATH}/tokenizers
wget https://the-eye.eu/public/AI/models/GPT-NeoX-20B/slim_weights/20B_tokenizer.json -O ${MODEL_PATH}/tokenizers/20B_tokenizer.json
```

To retireve and tokenize the Pile dataset, we use `prepare_data.py` of NeoX through container using `1.prepare-data.sbatch`.

```bash
sbatch 1.prepare-data.sbatch
```

You will see the following data after the job.

```bash
$ ls ${DATA_PATH}/enwik8/
enwik8.zip  enwik8_text_document.bin  enwik8_text_document.idx
```

## 5. Model training

GPT-NeoX parameters are defined in a YAML configuration file which is passed to the `deepy.py` launcher.
Parameters originate from either the [DeepSpeed runner CLI (DSL)](https://github.com/microsoft/DeepSpeed/blob/master/deepspeed/launcher/runner.py#L33), [DeepSpeed configuration file (DSC)](https://www.deepspeed.ai/docs/config-json/), [Megatron-LM CLI (Meg)](https://github.com/NVIDIA/Megatron-LM/blob/main/megatron/arguments.py#L224) or are GPT-NeoX (NeoX) modifications. See [the configuration README](https://github.com/EleutherAI/gpt-neox/blob/main/configs/README.md) of NeoX repository. You need to make few changes to the config files to make it work on a Slurm cluster. Firstly, you need to tell that launcher is slurm by setting the following in our config:

```yaml
    "launcher": "slurm",
    "deepspeed_slurm": true
```

Additionally, you need to modify all of your configs to conform to the JSON. When launching a GPT-NeoX job you can specify multiple YAML config files. Internally, all of these files are merged into one config and then passed as a single long command line argument to DeepSpeed. When using SLURM and its internal command srun, python fails to parse this long command line argument unless it is in the more restrictive JSON format. This test case prepares sample JSON configs in `configs/pythia` directory. See https://github.com/EleutherAI/gpt-neox/blob/main/configs/README.md#slurm-settings for details.

Note `gas` (`gradient_accumulation_steps`) in the original `pythia` config has been removed in the JSON configs. See https://github.com/EleutherAI/gpt-neox/pull/1144 for details.

