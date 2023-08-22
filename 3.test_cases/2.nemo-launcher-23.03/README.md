# Nemo Megatron on Slurm <!-- omit from toc -->

Table of contents:

- [1. Pre-requisites](#1-pre-requisites)
- [2. Build AWS-optimized Nemo-Launcher image](#2-build-aws-optimized-nemo-launcher-image)
- [3. Seed Nemo-Launcher on head node](#3-seed-nemo-launcher-on-head-node)
- [4. Launch Nemo pipeline](#4-launch-nemo-pipeline)
  - [4.1. Prepare Sample Dataset](#41-prepare-sample-dataset)
  - [4.2. Pre-training GPT3](#42-pre-training-gpt3)

## 1. Pre-requisites

The following pre-requisites are needed to run this example:

- You have access to the base image [`bignlp-training`](https://registry.ngc.nvidia.com/orgs/ea-bignlp/containers/bignlp-training) is available through NVIDIA's open-beta [here](https://developer.nvidia.com/nemo-framework-open-beta).
- Docker, Enroot and Pixys installed on the cluster and available on all nodes. It is assumed you are using a Custom AMI ([example](../../2.amazon_machine_images))


You will need to setup the following environment variables before running the scripts:

```bash
export VERSION=23.03
export REPO=aws-nemo-megatron
export TAG=$VERSION-py3
export TARGET_PATH=/fsx/nemo-launcher-$VERSION
```

2. This directory is already located on the FSx Lustre filesystem. For simplicity, assume the path
   is `/fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/`.

3. You have set the executable bits of the shell scripts

   ```bash
   find /fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03 \
       -name '*.sh' ! -executable -exec chmod ugo+x {} \;
   ```

4. Your current working directory is `/fsx/ubuntu/sample-slurm-jobs/nemo-launcher-23.03/`.

## 2. Build AWS-optimized Nemo-Launcher image

You will retrieve the container image from Nvidia, build an optimized container for EFA and, convert it into an Enroot file so we can run it on our cluster.

1. You have a registered account with Nvidia and can access NGC. Retrieve the NGC API key following [instructions from Nvidia](https://docs.nvidia.com/ngc/gpu-cloud/ngc-user-guide/index.html#generating-api-key).
2. Configure NGC as shown below using the command below, when requested use `$oauthtoken` for the login and the API key from NGC fro the password.
```bash
docker login nvcr.io
```
3. Copy the file `0.NemoMegatron-aws-optimized.Dockerfile` to the local directory and run the command below. Docker will retrieve the NemoMegatron container image from NGC then build an optimized container for AWS. This stage takes a few minutes and you can follow progress
```bash
docker build --progress plain -t ${REPO}:${TAG} -f 0.NemoMegatron-aws-optimized.Dockerfile .
```
4. Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in `/apps`. This step takes a few minutes.
```bash
IMAGE=/apps/${REPO}_${TAG}.sqsh ; [[ -e $IMAGE ]] && rm $IMAGE ; /usr/bin/time enroot import -o $IMAGE dockerd://${REPO}:${TAG}
```

The Enroot squash file will be placed into the `/apps` directory.


## 3. Set-up NemoMegatron

You will setup the target directory to host the configurations and requirements for NemoMegatron. It is assumed that your have an FSx for Lustre file system available to all nodes of your cluster via the mountpoint `/fsx`. We follow the same logic as in the [NemoMegatron Launcher documentation](https://github.com/NVIDIA/NeMo-Megatron-Launcher/tree/23.03#5111-slurm)


1. Create the target directory with the command below:
```bash
mkdir -p $TARGET_PATH
```
2. Retrieve files from the container and place them in the target directory. You execute the container on your head-node for this task using Enroot [start](https://github.com/NVIDIA/enroot/blob/master/doc/cmd/start.md) command.
```bash
enroot start --mount $TARGET_PATH:/workspace/mount_dir \
             --env NVIDIA_VISIBLE_DEVICES=void \
             /apps/aws-nemo-megatron_23.03-py3.sqsh \
             cp -a /opt/NeMo-Megatron-Launcher/launcher_scripts /opt/NeMo-Megatron-Launcher/auto_configurator /opt/FasterTransformer /workspace/mount_dir/
```
The `NVIDIA_VISIBLE_DEVICES` variable is set to void to prevent the process to check for the Nvidia driver presence (since we don't need GPUs here).
3. Install the NemoMegatron requirements in a Python VirtualEnv by running the set of commands below.
```bash
cd $TARGET_PATH
/usr/bin/python3 -m venv .venv
source .venv
pip install -r <(curl -fsSL https://raw.githubusercontent.com/NVIDIA/NeMo-Megatron-Launcher/23.03/requirements.txt)
```

Next, you need to prepare the configuration files as follow:

1. Review and update the partition name in the .yaml config file `conf.template/cluster/bcm.yaml`. Specifically these values.

| Value            | Default | Definition                           |
| ---------------- | ---------- | ------------------------------------ |
| partition        | `null`                        | Slurm partition, same as a job queue |
| account          | `null`                        | Account if using [accounting](https://slurm.schedmd.com/accounting.html) |
| exclusive        | `True`                        | The job has [exclusive](https://stackoverflow.com/questions/66817279/what-does-the-keyword-exclusive-mean-in-slurm) use the instances it runs on (no other job can take it) |
| gpus_per_task    | `null`                        | Number of instances of GPUs per job |
| gpus_per_node    | `8`                           | Number of GPUs to use per node |
| mem              | `0`                           | Requested memory (all) |
| job_name_prefix  | `"nemo-megatron-"`            | Prefix for your job names |
| gres             | `"gpu:8"`                     | Generic resource [scheduling](https://slurm.schedmd.com/gres.html) |
| srun_args        | `"--no-container-mount-home"` | Arguments for the [srun](https://slurm.schedmd.com/srun.html) command (here for Pyxis) |
| stderr_to_stdout | `True`                        | Merge `stderr` and `stdout` |



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
