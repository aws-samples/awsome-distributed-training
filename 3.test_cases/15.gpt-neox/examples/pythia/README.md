# Pythia GPT-NeoX Test Case <!-- omit in toc -->

This test case illustrates how to train [Pythia](https://arxiv.org/abs/2304.01373) model using GPT-Neox. 

## 1. Preparation

This test case assumes that you have built GPT-NeoX container `../../0.gpt-neox.dockerfile`.

## 2. Dataset preparation

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

## 3. Model training

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
