# Nemo Megatron on Slurm <!-- omit from toc -->

Table of contents:

- [1. Pre-requisites](#1-pre-requisites)
- [2. Build AWS-optimized Nemo-Launcher image](#2-build-aws-optimized-nemo-launcher-image)
- [3. Seed Nemo-Launcher on head node](#3-seed-nemo-launcher-on-head-node)
- [4. Launch Nemo pipeline](#4-launch-nemo-pipeline)
  - [4.1. Prepare Sample Dataset](#41-prepare-sample-dataset)
  - [4.2. Pre-training GPT3](#42-pre-training-gpt3)

## 1. Pre-requisites

1. As of this writing, the base image
   [bignlp-training](https://registry.ngc.nvidia.com/orgs/ea-bignlp/containers/bignlp-training) is
   still under NVIDIA's open-beta, and you need to register
   [here](https://developer.nvidia.com/nemo-framework-open-beta).

2. This directory is already located on the FSx Lustre filesystem. For simplicity, assume the path
   is `/fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/`.

3. You have set the executable bits of the shell scripts

   ```bash
   find /fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03 \
       -name '*.sh' ! -executable -exec chmod ugo+x {} \;
   ```

4. Your current working directory is `/fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/`.

## 2. Build AWS-optimized Nemo-Launcher image

All the way to the enroot format.

```bash
docker login nvcr.io
# Username: $oauthtoken
# Password: <API KEY>

/usr/bin/time bash ./build-enroot-image.sh
# EC2: us-west-2 / m5.4xlarge / EBS gp3 3k IOPS, 350 MB/s throughput
#
# docker pull (cold): 3:34.85elapsed
# docker build: ~6min
# Enroot import: 7:29.12elapsed
# Total (as reported): 17:11.90elapsed
```

<details>
<summary>[OPTIONAL] Try enroot image by starting a container out of it.</summary>

```bash
  /usr/bin/time enroot create --name test-nemo /fsx/ubuntu/aws-nemo-megatron_23.03-py3.sqsh
  # 3.21user 29.64system 0:27.88elapsed 117%CPU (0avgtext+0avgdata 581864maxresident)k
  # Will create /tmp/enroot/data/user-1000/test-nemo/ taking up the same size of sqsh file

  # Show containers
  enroot list

  declare -a ENROOT_START_ARGS=(
      # Needed when starting on CPU-only instances (e.g., on head node).
      -e NVIDIA_VISIBLE_DEVICES=void
  )
  enroot start "${ENROOT_START_ARGS[@]}" test-nemo

  # After exiting the enroot container, remove it and list to make sure it's gone.
  # This command will remove /tmp/enroot/data/user-1000/test-nemo/
  enroot remove -f test-nemo
  enroot list
  ```

</details>

## 3. Seed Nemo-Launcher on head node

Run this helper script, which faithfully implements the [official Nemo-Launcher
documentation](https://github.com/NVIDIA/NeMo-Megatron-Launcher/tree/23.03#5111-slurm):

```bash
./step-00-bootstrap-launcher.sh
```

Next, you need to prepare the configuration files as follow:

1. Review and update the partition name in the .yaml config file `conf.template/cluster/bcm.yaml`.

2. Copy all the .yaml config files `{conf.template/ => launcher_scripts/conf/}` with this command:

   ```console
   $ cp -TRv conf.template/ launcher_scripts/conf/
   'conf.template/cluster/bcm.yaml' -> 'launcher_scripts/conf/cluster/bcm.yaml'
   'conf.template/config.yaml' -> 'launcher_scripts/conf/config.yaml'
   'conf.template/data_preparation/gpt3/download_gpt3_pile.yaml' -> 'launcher_scripts/conf/data_preparation/gpt3/download_gpt3_pile.yaml'
   ```

## 4. Launch Nemo pipeline

This section assumes the following has been done:

```bash
source /fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/.venv/bin/activate
```

### 4.1. Prepare Sample Dataset

```bash
# Edit launch-data_preparation.sh to override Hydra config. Or, modify the config directly.
./step-01-data_preparation.sh
```

Once completed, expect the training data (vocab and the pre-processed Pile dataset) as follows:

```text
/fsx/ubuntu/data
├── bpe                                 # Vocabulary from HF Hub
│   ├── merges.txt
│   └── vocab.json
└── the_pile_gpt3                       # Pre-processed the Pile data set (in Nemo format)
    ├── my-gpt3_00_text_document.bin
    ├── my-gpt3_00_text_document.idx
    ├── ...
    ├── ...
    ├── my-gpt3_04_text_document.bin
    └── my-gpt3_04_text_document.idx
```

Job logs available here:

```text
/fsx/ubuntu/nemo-megatron-23.03/results/
└── download_gpt3_pile                                               # Correspond to stage
    ├── download                                                     # Job within a stage
    │   ├── download_gpt3_pile_hydra.yaml                            # Interpolated config
    │   ├── launcher.log                                             # Status of job submission
    │   ├── log-nemo-megatron-download_gpt3_pile_<ARRAY_JOB_ID>.out  # Std{err,out} of this array task
    │   ├── ...
    │   └── nemo-megatron-download_gpt3_pile_submission.sh           # Script to submit a Slurm array job
    ├── extract
    │   ├── download_gpt3_pile_hydra.yaml
    │   ├── launcher.log
    │   ├── log-nemo-megatron-download_gpt3_pile_<ARRAY_JOB_ID>.out
    │   ├── ...
    │   └── nemo-megatron-download_gpt3_pile_submission.sh
    ├── launcher_cmd.log
    └── preprocess
        ├── download_gpt3_pile_hydra.yaml
        ├── launcher.log
        ├── log-nemo-megatron-download_gpt3_pile_<ARRAY_JOB_ID>.out
        ├── ...
        └── nemo-megatron-download_gpt3_pile_submission.sh
```

### 4.2. Pre-training GPT3

```bash
# Choose one of these options:
# 1. edit then run step-02-pretrain-gpt3.sh, or
# 2. review, edit (if necessary), then run pretrain-gpt3-*.sh.
#
# Below show option 2.
./pretrain-gpt3-126m2.sh
```
