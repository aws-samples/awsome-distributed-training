# LLM Foundry Mosaic Pretrained Transformers (MPT) Test Case <!-- omit in toc -->
MPT are GPT-style models in [llm-foundry](https://github.com/mosaicml/llm-foundry/tree/main) with some special features -- [Flash Attention](https://arxiv.org/abs/2205.14135) for efficiency, [ALiBi](https://arxiv.org/abs/2108.12409) for context length extrapolation, and stability improvements to mitigate loss spikes.

This project contains:

* AWS optimized [llm-foundry](https://github.com/mosaicml/llm-foundry/tree/main) container image.
* Slurm scripts for the [c4 dataset](https://huggingface.co/datasets/c4) preparation and multi-node distributed training.

```bash
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/composer.sqsh
export FSX_PATH=/fsx
export DATA_PATH=$FSX_PATH/c4-dataset
export LLM_FOUNDRY_VER=v0.10.0
```


```bash
git clone git clone  --single-branch --branch ${LLM_FOUNDRY_VER} https://github.com/mosaicml/llm-foundry.git
```


## 3. Run the processing job

You need to retrieve input data and preprocess it before running the training job.

1. Run a preprocessing job by submitting the script `1.c4-preprocess.sbatch` to Slurm. The command will return the Slurm Job ID. You can use `squeue` to consult the status of your jobs.

    ```bash
    sbatch 1.c4-preprocess.sbatch
    ```

    It will create the streaming dataset for composer library using C4 dataset in `/fsx/c4-dataset` (default).

2. You see a new file in your current working directory called `c4-preprocess_XY.out` where `XY` corresponds the Slurm job ID. This is your output file and will capture the `STDOUT` and `STDERR` from your job. You can check how it progresses via the command `tail -f c4-preprocess_XY.out` with the correct job ID instead of `XY`. If running successfully, the job will generate an output similar to the except below.

    ```console
    Downloading (…)okenizer_config.json: 100%|██████████| 156/156 [00:00<00:00, 1.09MB/s]
    ...
    Downloading metadata: 100%|██████████| 2.40M/2.40M [00:01<00:00, 2.05MB/s]
    ...
    train_small:  32%|███▏      | 31745/100000 [01:51<00:19, 3538.83it/s]
    ...
    val_small: 100%|██████████| 10000/10000 [00:19<00:00, 514.19it/s]
    ```

    Please be aware that this job downloads the tokenizer on demand (if it's not available under `./EleutherAI/gpt-neox-20b`), after which the tokenizer will be cached under `$HOME/.cache/huggingface`, and the `$HOME` directory is an NFS filesystem shared by the head node. Please consult the [HuggingFace cache management](https://huggingface.co/docs/datasets/cache) document to learn more about fine-grained control of the HuggingFace cache.

3. After the job completed, check `/fsx/c4-dataset` (default) which will contain a structure similar as below

    ```console
    /fsx/c4-dataset/
    ├── train_small
    │   ├── index.json
    │   ├── shard.00000.mds
    │   ├── shard.00001.mds
    │   ├── shard.00002.mds
    ...
    │   ├── shard.00023.mds
    │   └── shard.00024.mds
    └── val_small
        ├── index.json
        ├── shard.00000.mds
        ├── shard.00001.mds
        └── shard.00002.mds
    ```

Once preprocessing is done, you will run a training job in the next stage.

## 4. Distributed training of MPT

Now that the data is preprocessed, we will pretrain a MPT model with [Mosaic Composer](https://github.com/mosaicml/composer).

1. Run a training job by submitting script `2.train-mpt-manual-distributed.sbatch` to Slurm via `sbatch` as shown below.

    ```bash
    sbatch 2.train-mpt-manual-distributed.sbatch
    ```
by default it runs `mpt-7b` model. You can specify model to be trained as:
    ```bash
    sbatch 2.train-mpt-manual-distributed.sbatch mpt-30b
    ```

2. When the training job completes successfully, it should produce a log output similar to the below in the `logs/` directory of `$TEST_CASE_PATH`.

```console
...
0: [batch=1/300000000]:
0:       Train time/epoch: 0
0:       Train time/batch: 0
0:       Train time/sample: 0
0:       Train time/batch_in_epoch: 0
0:       Train time/sample_in_epoch: 0
0:       Train time/token: 0
0:       Train time/token_in_epoch: 0
0:       Train memory/allocated_mem: 3.6287
0:       Train memory/active_mem: 3.6287
0:       Train memory/inactive_mem: 2.7844
0:       Train memory/reserved_mem: 20.9650
0:       Train memory/alloc_retries: 0
0:       Train trainer/device_train_microbatch_size: 8
0:       Train loss/train/total: 12.0000
0:       Train metrics/train/LanguageCrossEntropy: 12.0000
0:       Train metrics/train/LanguagePerplexity: 162754.5000
0:       Train time/train: 0.0037
0:       Train time/val: 0.0000
...
```