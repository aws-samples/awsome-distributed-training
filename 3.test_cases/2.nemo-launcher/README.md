# Nemo Megatron on Slurm <!-- omit from toc -->

Table of contents:

- [1. Pre-requisites](#1-pre-requisites)
- [2. Build AWS-optimized Nemo-Launcher image](#2-build-aws-optimized-nemo-launcher-image)
- [3. Set-up the NemoMegatron environment](#3-set-up-the-nemomegatron-environment)
- [4. Prepare Input Data](#4-prepare-input-data)
- [5. Pre-training GPT3](#5-pre-training-gpt3)
- [6. Customizing Pre-Training](#6-customizing-pre-training)

## 1. Pre-requisites

The following pre-requisites are needed to run this example:

- You have access to the base image [`nemofw-training`](https://registry.ngc.nvidia.com/orgs/ea-bignlp/containers/bignlp-training) is available through NVIDIA's open-beta [here](https://developer.nvidia.com/nemo-framework-open-beta).
- Docker, [Enroot](https://github.com/NVIDIA/enroot) and [Pixys](https://github.com/NVIDIA/pyxis) installed on the cluster and available on all nodes. It is assumed you are using a Custom AMI ([example](../../2.amazon_machine_images))

You will need to setup the following environment variables before running the scripts. :

```bash
export NEMO_VERSION=23.07
export REPO=aws-nemo-megatron
export TAG=$NEMO_VERSION-py3
export TARGET_PATH=/fsx/nemo-launcher-$NEMO_VERSION   # must be a shared filesystem
export TEST_CASE_PATH=/home/ec2-user/2.nemo-launcher  # where you copy the test case or set to your test case path
export ENROOT_IMAGE=/apps/${REPO}_${TAG}.sqsh

cd $TEST_CASE_PATH
```

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
[[ -e $ENROOT_IMAGE ]] && rm $ENROOT_IMAGE ; /usr/bin/time enroot import -o $ENROOT_IMAGE dockerd://${REPO}:${TAG}
```

The Enroot squash file will be placed into the `/apps` directory.

## 3. Set-up the NemoMegatron environment

You will setup the target directory to host the configurations and requirements for NemoMegatron. It is assumed that your have an FSx for Lustre file system available to all nodes of your cluster via the mountpoint `/fsx`. We follow the same logic as in the [NemoMegatron Launcher documentation](https://github.com/NVIDIA/NeMo-Megatron-Launcher/tree/23.07#5111-slurm)

1. Create the target directory with the command below:

```bash
mkdir -p $TARGET_PATH
```

2. Retrieve files from the container and place them in the target directory. You execute the container on your head-node for this task using Enroot [start](https://github.com/NVIDIA/enroot/blob/master/doc/cmd/start.md) command.

```bash
cd $TARGET_PATH
enroot start --mount $TARGET_PATH:/workspace/mount_dir \
             --env NVIDIA_VISIBLE_DEVICES=void \
             $ENROOT_IMAGE \
             cp -a /opt/NeMo-Megatron-Launcher/launcher_scripts /opt/NeMo-Megatron-Launcher/auto_configurator /opt/FasterTransformer /workspace/mount_dir/
```

The `NVIDIA_VISIBLE_DEVICES` variable is set to void to prevent the process to check for the Nvidia driver presence (since we don't need GPUs here).

3. Install the NemoMegatron requirements in a Python VirtualEnv by running the set of commands below.

```bash
cd $TARGET_PATH
sudo amazon-linux-extras install -y python3.8 # we need Python =>3.8
/usr/bin/python3.8 -m venv .venv
source .venv/bin/activate
pip3.8 install --upgrade pip setuptools
pip3.8 install -r <(curl -fsSL https://raw.githubusercontent.com/NVIDIA/NeMo-Megatron-Launcher/$NEMO_VERSION/requirements.txt)
```

Next, you need to prepare the configuration files as follow:

1. Review and update the partition name in the .yaml config file `conf.template/cluster/bcm.yaml`. Here is a summary of the values.

| Value              | Default                       | Definition                                                                                                                                                                  |
| ------------------ | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `partition`        | `null`                        | Slurm partition, same as a job queue                                                                                                                                        |
| `account`          | `null`                        | Account if using [accounting](https://slurm.schedmd.com/accounting.html)                                                                                                    |
| `exclusive`        | `True`                        | The job has [exclusive](https://stackoverflow.com/questions/66817279/what-does-the-keyword-exclusive-mean-in-slurm) use the instances it runs on (no other job can take it) |
| `gpus_per_task`    | `null`                        | Number of instances of GPUs per job                                                                                                                                         |
| `gpus_per_node`    | `8`                           | Number of GPUs to use per node. This is set to 8 GPUs as for th p4d.24xlarge                                                                                                |
| `mem`              | `0`                           | Requested memory (all)                                                                                                                                                      |
| `job_name_prefix`  | `"nemo-megatron-"`            | Prefix for your job names                                                                                                                                                   |
| `gres`             | `"gpu:8"`                     | Generic resource [scheduling](https://slurm.schedmd.com/gres.html)                                                                                                          |
| `srun_args`        | `"--no-container-mount-home"` | Arguments for the [srun](https://slurm.schedmd.com/srun.html) command (here for Pyxis)                                                                                      |
| `stderr_to_stdout` | `True`                        | Merge `stderr` and `stdout`                                                                                                                                                 |

2. Copy all the .yaml config files `{conf.template/ => launcher_scripts/conf/}` and substitute environment variables as follows:

```bash
cp -Rv ${TEST_CASE_PATH}/conf.template/cluster ${TARGET_PATH}/launcher_scripts/conf/cluster
envsubst < ${TEST_CASE_PATH}/conf.template/config.yaml > ${TARGET_PATH}/launcher_scripts/conf/config.yaml
```

## 4. Prepare Input Data

The pre-training we're going to run uses the [GPT2](https://huggingface.co/gpt2) tokenizer which requires you to download the vocabularies files:

```bash
mkdir -p $TARGET_PATH/data/bpe
curl -L https://huggingface.co/gpt2/raw/main/vocab.json > $TARGET_PATH/data/bpe/vocab.json
curl -L https://huggingface.co/gpt2/raw/main/merges.txt > $TARGET_PATH/data/bpe/merges.txt
```

We also create an input directory but leave it empty for our pre-training which uses a mock dataset generated on-the-fly.

```bash
mkdir -p $TARGET_PATH/data
```

## 5. Pre-training GPT3

This section assumes that you went through the previous sections and 1/ retrieved and built the AWS optimized NemoMegatron container, 2/ setup the NemoMegatron environment, and 3/ download the vocabularies.

To start pre-training, source the NemoMegatron environment:

```bash
source ${TARGET_PATH}/.venv/bin/activate
```

To pre-train a GPT3-126m on two instances with mock dataset, run the following:

```bash
cd $TARGET_PATH
$TEST_CASE_PATH/bmk-pretrain-gpt3-126m2.sh
```

which results in this execution tree:

```bash
$TEST_CASE_PATH/bmk-pretrain-gpt3-126m.sh
\_ $TEST_CASE_PATH/1.bmk-pretrain-gpt3.sh
   \_ $TARGET_PATH/launcher_scripts/main.py
      \_ sbatch
```

As can be seen, Nemo-launcher `launcher_scripts/main.py` interacts with Slurm on our behalf to generate an `.sbatch` file and submit it to Slurm. Nemo-launcher logs all the invocation commands, output, and error to `$TARGET_PATH/results/<MODEL_SIZE>/` described below.

```bash
$TARGET_PATH/results/gpt3_126m
├── gpt3_126m_hydra.yaml                        # The fully interpolated pre-training configuration
├── launcher_cmd.log                            # The full invocation command of launcher_scripts/main.py
├── launcher.log                                # Job id produced by the sbatch command
├── log-nemo-megatron-gpt3_126m_<JOB_ID>.out    # Stdout of the pre-training Slurm job
├── nemo-megatron-gpt3_126m_submission.sh       # .sbatch file generated and submitted by nemo-launcher
└── results
    ├── cmd-args.log                            # The full invocation command of the pre-training script
    ├── events.out.tfevents.*                   # Tensorboard logs
    ├── git-info.log                            # The commit hash of the NeMO repo provided in the container.
    ├── hparams.yaml                            # Pre-training hyperparameters
    ├── lightning_logs.txt                      # Additional logs from PyTorch-Lightning
    ├── nemo_error_log.txt                      # Stderr of pre-training step
    └── nemo_log_globalrank-*.txt               # Log of each rank
```

Please note that except for `log-nemo-megatron-gpt3_126m_<JOB_ID>.out`, the other files will be overridden when you launch another pre-training of that same model size. To completely separate the output among jobs, edit `TEST_CASE_PATH/bmk-pretrain-gpt3-126m.sh` and uncomment the `#export UNIQUE_OUTPUT_DIR=1` line to produce this output dir instead:

```bash
$TARGET_PATH/results-<TIMESTAMP>/gpt3_126m/
├── gpt3_126m_hydra.yaml
├── ...
└── results
    ├── cmd-args.log
    ├── ...
    └── nemo_log_globalrank-*.txt\
```

Congratulations! You've successfully run this test case to completion.

## 6. Customizing Pre-Training

The `$TEST_CASE_PATH` comes with `bmk-pretrain-gpt3-126m2.sh` and `bmk-pretrain-gpt3-5b2.sh` to pre-train 126m and 5b models, respectively, on two instances.

To pre-train a different model size on different instance count, create your own `bmk-pretrain-gpt3-<SIZE><INSTANCE>.sh` based on those examples. Please that pre-training LLM requires understanding on the hyperparameters such as parallelism and batches. Please refer to the NeMO project ([website](https://developer.nvidia.com/nemo), [GitHub](https://github.com/NVIDIA/NeMo), [NeMo-Megatron-Launcher](https://github.com/NVIDIA/NeMo-Megatron-Launcher)) and the Megatron papers ([Shoeybi20](https://arxiv.org/abs/1909.08053), [Narayanan21](https://arxiv.org/abs/2104.04473)).

At the very least, you'd want to review and customize one or more YAML files under `$TARGET_PATH/launcher_scripts/conf/`. Nemo-launcher organizes its config files in an opinionated hierarchy. Below is an example of relevant YAML files when launching `$TARGET_PATH/launcher_scripts/main.py` for `training` stage for `gpt3/126m` (see `$TEST_CASE_PATH/1.bmk-pretrain-gpt3.sh`).

```bash
$TARGET_PATH/launcher_scripts/conf
├── config.yaml        # Config for generating job scripts (.sbatch, .yaml, etc.)
├── cluster
│   └── bcm.yaml       # Config for Slurm jobs
└── training           # Config for stage "training"
    └── gpt3           # Config for model "gpt3"
        └── 126m.yaml  # Config for model size "126m"
```
