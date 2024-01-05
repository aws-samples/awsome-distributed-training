# Prepare AWS DLAMI (Deep Learning AMI) for AWS ParallelCluster using `pcluster build-image`

This document shows how to use `pcluster build-image` to prepare
[DLAMI](https://aws.amazon.com/machine-learning/amis/) for ParallelCluster.

Choose this approach when you have these requirements:

1. Build AMI using native AWS tools only. This approach uses the `pcluster` cli to launch [EC2 Image
   Builder](https://aws.amazon.com/image-builder/) jobs. No dependency to community toolkits.

2. To use DLAMI which already comes prebuilt with deep-learning stack optimized for AWS:
   [EFA](https://aws.amazon.com/hpc/efa/),
   [Docker](https://www.docker.com/products/container-runtime/), GPU stack
   ([CUDA](https://developer.nvidia.com/cuda-toolkit), [cuDNN](https://developer.nvidia.com/cudnn),
   [nccl](https://github.com/NVIDIA/nccl), [aws-ofi-nccl](https://github.com/aws/aws-ofi-nccl),
   [gdrcopy](https://github.com/NVIDIA/gdrcopy),
   [nvidia-container-toolkit](https://github.com/NVIDIA/nvidia-container-toolkit),
   [nccl-tests](https://github.com/NVIDIA/nccl-tests)) or [Neuron
   SDK](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/), and frameworks (e.g.,
   [PyTorch](https://pytorch.org/)).

## 1. Install PCluster CLI

On your client machine (e.g., laptop) pre-configured with [AWS CLI](https://aws.amazon.com/cli/) and
AWS credential, install PCluster CLI following this
[documentation](https://docs.aws.amazon.com/parallelcluster/latest/ug/install-v3-virtual-environment.html).

Below example uses a Python virtual environment:

```bash
# Create and activate virtualenv for pcluster cli
python3 /usr/bin/python3 -m venv .venv
source .venv/bin/activate
which pip
# Eyeball we're using pip binary from the venv.

# Install pcluster to virtualenv
pip install --upgrade pip setuptools
pip install aws-parallelcluster
pcluster version
```

Here's another example to install `pcluster` to a `conda` environment:

```bash
conda env create pc380-p312 python=3.12   # Replace pc and python versions as you like.
conda activate pc380-p312
conda install -c conda-forge aws-parallelcluster
pcluster version
```

## 2. Build AMI

We provide two build-specification examples: one for DLAMI Base, and another for DLAMI PyTorch; both
with Ubuntu-20.04 flavor. You're strongly recommended to review the `.yaml` files, adjust as needed
(e.g., use the latest DLAMI as parent), and only then proceed to build the custom AMI.

```bash
export AWS_REGION=us-west-2

# Customize DLAMI Base
pcluster build-image -r $AWS_REGION -c 01.config-dlami-ub2004-base-gpu.yaml -i pc-dlami-base

# Customize DLAMI PyTorch
pcluster build-image -r $AWS_REGION -c 02.config-dlami-ub2004-pytorch-gpu.yaml -i pc-dlami-pytorch
```

Each `pcluster build-image` command displays the results in JSON, e.g.,

```json
{
  "image": {
    "imageId": "pc-dlami-base",
    "imageBuildStatus": "BUILD_IN_PROGRESS",
    "cloudformationStackStatus": "CREATE_IN_PROGRESS",
    "cloudformationStackArn": "arn:aws:cloudformation:us-west-2:111122223333:stack/pc-dlami-base/097178b0-3037-11ee-97c3-0672f191cc71",
    "region": "us-west-2",
    "version": "3.8.0"
  }
}
```

<details>
  <summary><b>Pro-tips</b>: syntax-colored <code>pcluster</code> output</b></summary>

  To syntax-color the `pcluster`'s JSON output, pipe the command to `jq`. Examples below.

  ```bash
  export AWS_REGION=us-west-2

  # Customize DLAMI Base
  pcluster build-image -r $AWS_REGION -c 01.config-dlami-ub2004-base-gpu.yaml -i pc-dlami-ubuntu-base-gpu | jq .

  # Customize DLAMI PyTorch
  pcluster build-image -r $AWS_REGION -c 02.config-dlami-ub2004-pytorch-gpu.yaml -i pc-dlami-ubuntu-base-pytorch | jq .
  ```

</details>

While the image is building, you should see a CloudFormation stack with the same name as the AMI
name (e.g., `pc-dlami-ubuntu-base-gpu` for the first example above). From this CloudFormation stack,
you can trace the AWS resources involved in the build process, such as the EC2 instance, the Image
Builder pipeline, etc.

You can also check the build log in CloudWatch. Look for log group
`/aws/imagebuilder/ParallelClusterImage-<AMI_NAME>` and log stream `<PCLUSTER_VERSION>/1`, e.g., for
the first example above are `/aws/imagebuilder/ParallelClusterImage-pc-dlami-ubuntu-base-pytorch`
and `3.8.0/1`.

<details>
  <summary><b>Pro-tips: fetch build logs using community cli <code>awslogs</code></b></summary>

  Below are examples to use the community cli `awslogs` to fetch from CloudWatch the build log. To
  install `awslogs`, please follow its [installation
  instructions](https://github.com/jorgebastida/awslogs#installation).

  The examples assume ami named `pc-dlami-base` and `pcluster` version 3.8.0. Please update the log
  group and stream names accordingly. When in doubt, check the log group and stream names from the
  CloudWatch console.

  ```bash
  # Watch the create-image process of ami name `pc-dlami-base`.
  awslogs get -GS --aws-region=us-west-2 \
      /aws/imagebuilder/ParallelClusterImage-pc-dlami-base 3.8.0/1 --watch -i 30 -s10min

  # Save all logs to a local file. Will also pull the failed logs from the earlier attempt.
  #
  # -s4d instructs the cli tool to fetch logs from the last 4d. Without this flags, it fecthes only
  # a few entries, or even none at all.
  awslogs get -GS --aws-region=us-west-2 \
      /aws/imagebuilder/ParallelClusterImage-pc-dlami-base 3.8.0/1 -s4d &> create-image-01-success.log
  ```

</details>

## 3. Appendix: advance usage

Should you really need to enable `update` in the build .yaml spec, please apply the following
changes otherwise the build will fail.

Edit the `pcluster/resources/imagebuilder/update_and_reboot.yaml`, e.g.,

```bash
vi pyenv/versions/pc361-p312/lib/python3.12/site-packages/pcluster/resources/imagebuilder/update_and_reboot.yaml
```

then, apply the following changes:

```bash
# Locate this line, and change it...
apt-get -y install linux-aws linux-headers-aws linux-image-aws

# ...to this.
apt-get -y install --allow-change-held-packages linux-aws linux-headers-aws linux-image-aws`
```

**Known issue**: when enabling `update`, resulted AMI may not have Lustre work properly. This will
happen when the Lustre client for the new kernel is unavailable at AMI build time. The only known
workaround is to either 1/ disable update, or 2/ wait until AWS releases the newer Lustre client
module.
