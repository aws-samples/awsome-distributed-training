# MegatronLM Test Case

[MegatronLM](https://github.com/NVIDIA/Megatron-LM) is a framework from Nvidia that can be used to train LLMs. We recommend that you read papers on the framework to know the different knobs you can tune and in particular these articles:

- [Megatron-LM: Training Multi-Billion Parameter Language Models Using Model Parallelism](https://arxiv.org/abs/1909.08053)
- [Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM](https://arxiv.org/abs/1909.08053)

To run a test case you will go through a series of steps described below:

1. Build the data preprocessing container.
2. Pre-process the data using a tokenizer and the preprocessing container.
3. Build the container for distributed training
4. Train!

We describe the steps below for Slurm users. EKS users may follow the sequence but details will vary.

## 0. Preparation

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- An FSx for Lustre filesystem mounted on `/fsx`.

It is recommended that you use the templates in the architectures [directory](../../1.architectures)

You will also setup the following variables in your terminal environment.

```bash
export DATA_PATH=/fsx # FSx for Lustre shared file-system
```

Make sure that your current directory is under a shared filesystem such as `/fsx/` or the home directory when using [Parallel Cluster](../../1.architectures/aws-parallelcluster).

## 1. Data Preprocessing

Before running training jobs you need to retrieve input data and preprocess it. This section of the guide you will retrieve a container then you convert it into a Squash file via [Enroot](https://github.com/NVIDIA/enroot), you will then retrieve input data ans tokenize it using the GPT2 vocabulary.

Below are the steps you need to follow:

1. Copy the file `0.distributed-training.Dockerfile` or its content to your head-node.
2. Build the container image with the command below

   ```bash
   docker build -t megatron-training -f 0.distributed-training.Dockerfile .
   ```

3. Once the image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```
   [ec2-user@ip-10-0-10-78 ~]$ docker images
   REPOSITORY               TAG         IMAGE ID       CREATED          SIZE
   megatron-training           latest      a33c9d5bcb6e   9 seconds ago    20.7GB
   ```

4. Create the squash file with the command below.

   ```bash
   enroot import -o megatron-training.sqsh  dockerd://megatron-training:latest
   ```

   The file will be stored in the current directory (if left as default). The output should look as below.

    ```bash
    [ec2-user@ip-10-0-10-78 ~]$ enroot import -o ./megatron-training.sqsh  dockerd://megatron-training:latest
    [INFO] Fetching image

    e19aa13505c1710876982dc440226dc479da5177dc4770452cc79bedc8b5b41d

    [INFO] Extracting image content...
    [INFO] Creating squashfs filesystem...

    Parallel mksquashfs: Using 32 processors
    Creating 4.0 filesystem on /home/ec2-user/megatron-training.sqsh, block size 131072.
    [==========================================================/] 299550/299550 100%

    Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
       uncompressed data, uncompressed metadata, uncompressed fragments, uncompressed xattrs
       duplicates are not removed
    ...
    ```

5. Run the code below to retrieve the input datasets and vocabulary.

    ```bash
    #!/bin/bash
    mkdir -p gpt2
    cd gpt2/

    wget https://huggingface.co/bigscience/misc-test-data/resolve/main/stas/oscar-1GB.jsonl.xz
    wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-vocab.json
    wget https://s3.amazonaws.com/models.huggingface.co/bert/gpt2-merges.txt
    xz -d oscar-1GB.jsonl.xz
    ```

6. Now you copy the file `1.data-preprocessing.sbatch` or its content on your cluster then submit a preprocessing jobs with the command below:

    ```bash
    sbatch 1.data-preprocessing.sbatch
    ```

7. You will see a new file in your current working directory called `slurm-XY.out` where `XY` is a number. This is your output file and will capture the `STDOUT` and `STDERR` from your job. You can check how it progresses via the command `tail -f slurm-XY.out` but with the relevant filename. The file content will be similar to the below:

    ```
    0: Opening /fsx/oscar-1GB.jsonl
    0: Time to startup: 0.9956498146057129
    0: Processed 1000 documents (101.28050670002645 docs/s, 1.258563987556778 MB/s).
    0: Processed 2000 documents (188.07992853480727 docs/s, 2.3571624257619614 MB/s).
    ...
    0: Processed 78000 documents (1293.9967304914383 docs/s, 16.67556064420713 MB/s).
    0: Processed 79000 documents (1298.6715286585202 docs/s, 16.763634765830606 MB/s).
    ```

Voilà! You have executed the preprocessing job. You will go through the steps to run your training job.

## 2. Distributed training

Now that the data is preprocessed, we will pretrain a GPT3 model MegatronLM.

1. Copy the file `2.distributed-training.sbatch` to your cluster then submit a training jobs with the command below:

    ```bash
    sbatch 2.distributed-training.sbatch
    ```

5. The training starts running and should produce an output similar to below if successful.

```
1:  iteration       25/73242187 | consumed samples:           50 | elapsed time per iteration (ms): 87.0 | learning rate: 1.638E-08 | global batch size:     2 | lm loss: 1.086954E+01 | loss scale: 4294967296.0 | grad norm: 0.000 | number of skipped iterations:   0 | number of nan iterations:   0 |
1:  iteration       26/73242187 | consumed samples:           52 | elapsed time per iteration (ms): 86.5 | learning rate: 1.704E-08 | global batch size:     2 | lm loss: 1.086217E+01 | loss scale: 4294967296.0 | grad norm: 0.000 | number of skipped iterations:   0 | number of nan iterations:   0 |
1:  iteration       27/73242187 | consumed samples:           54 | elapsed time per iteration (ms): 88.4 | learning rate: 1.769E-08 | global batch size:     2 | lm loss: 1.087129E+01 | loss scale: 4294967296.0 | grad norm: 0.000 | number of skipped iterations:   0 | number of nan iterations:   0 |
```

## 3. What's next?

The example is based on the GPT3 example from MegatronLM's [repository](https://github.com/NVIDIA/Megatron-LM/blob/main/examples/pretrain_gpt.sh). You can modify `NUM_ATTENTION_HEADS`, `NUM_LAYERS`, and `HIDDEN_SIZE`  based on the Table 1 (Page 8) of the document [Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM](https://arxiv.org/abs/2104.04473) to change the model size. You can also run the following commands to launch training for different model sizes before submitting a job as follows: `NUM_LAYERS=64 HIDDEN_SIZE=8192 NUM_ATTENTION_HEADS=48 sbatch  3.distributed-training.sbatch`

| Model size | Parameters                                                |
|------------|-----------------------------------------------------------|
| 1.7B       | `NUM_ATTENTION_HEADS=24 HIDDEN_SIZE=2304 NUM_LAYERS=24`   |
| 3.6B       | `NUM_ATTENTION_HEADS=32 HIDDEN_SIZE=3072 NUM_LAYERS=30`   |
| 7.5B       | `NUM_ATTENTION_HEADS=32 HIDDEN_SIZE=4096 NUM_LAYERS=36`   |
| 18.4B      | `NUM_ATTENTION_HEADS=48 HIDDEN_SIZE=6144 NUM_LAYERS=40`   |
| 39.1B      | `NUM_ATTENTION_HEADS=64 HIDDEN_SIZE=8192 NUM_LAYERS=48`   |
| 76.1B      | `NUM_ATTENTION_HEADS=80 HIDDEN_SIZE=10240 NUM_LAYERS=60`  |
| 145.6B     | `NUM_ATTENTION_HEADS=96 HIDDEN_SIZE=12288 NUM_LAYERS=80`  |
| 310.1B     | `NUM_ATTENTION_HEADS=128 HIDDEN_SIZE=16384 NUM_LAYERS=96` |

## 4. Appendix

### 4.1. Benchmark mode

To run in benchmark mode (i.e., train only, no validation and test), apply these changes to `2.distributed-training.sbatch` when calling `pretrain_gpt.py`:

```diff
-        --eval-iters 40 \
-        --eval-interval 1000 \
-        --split 98,2,0 \
+        --eval-iters 0 \
+        --split 100,0,0 \
```

Incorrect settings will cause this error message to appear in the Slurm output:

```text
Traceback (most recent call last):
  File "/workspace/Megatron-LM/pretrain_gpt.py", line 198, in <module>
    pretrain(train_valid_test_datasets_provider,
  File "/workspace/Megatron-LM/megatron/training.py", line 227, in pretrain
    = build_train_valid_test_data_iterators(
  File "/workspace/Megatron-LM/megatron/training.py", line 1283, in build_train_valid_test_data_iterators
    build_train_valid_test_data_loaders(
  File "/workspace/Megatron-LM/megatron/training.py", line 1244, in build_train_valid_test_data_loaders
    train_ds, valid_ds, test_ds = build_train_valid_test_datasets(
  File "/workspace/Megatron-LM/megatron/training.py", line 1214, in build_train_valid_test_datasets
    return build_train_valid_test_datasets_provider(train_val_test_num_samples)
  File "/workspace/Megatron-LM/pretrain_gpt.py", line 186, in train_valid_test_datasets_provider
    ).build()
  File "/workspace/Megatron-LM/megatron/core/datasets/blended_megatron_dataset_builder.py", line 56, in build
    return self._build_blended_dataset_splits()
  File "/workspace/Megatron-LM/megatron/core/datasets/blended_megatron_dataset_builder.py", line 76, in _build_blended_dataset_splits
    return self._build_megatron_dataset_splits(blend[0], split, self.sizes)
  File "/workspace/Megatron-LM/megatron/core/datasets/blended_megatron_dataset_builder.py", line 216, in _build_megatron_dataset_splits
    self.build_generic_dataset(
  File "/workspace/Megatron-LM/megatron/core/datasets/blended_megatron_dataset_builder.py", line 258, in build_generic_dataset
    dataset = cls(*args)
  File "/workspace/Megatron-LM/megatron/core/datasets/gpt_dataset.py", line 68, in __init__
    super().__init__(indexed_dataset, indexed_indices, num_samples, index_split, config)
  File "/workspace/Megatron-LM/megatron/core/datasets/megatron_dataset.py", line 42, in __init__
    assert num_samples > 0
AssertionError
```

### 4.2. Adjust training steps

By default, the .sbatch scripts specify the number of samples, then the number of training steps equals to `--train_samples` / `--global-batch-size`. To directly specify the number of steps, apply these changes to `2.distributed-training.sbatch` when calling `pretrain_gpt.py`. Note that `samples` and `iters` are mutually exclusive.

```diff
-        --train-samples 146484375 \
-        --lr-decay-samples 126953125 \
-        --lr-warmup-samples 183105 \
+        --train-iters 50 \
+        --lr-decay-iters 45 \
+        --lr-warmup-iters 2 \
```
