# MosaicML Composer Test Cases <!-- omit in toc -->

Composer is an open-source deep learning training library by MosaicML. Built on top of PyTorch, the Composer library makes it easier to implement distributed training workflows on large-scale clusters.
This directory contains docker image and instructions how to build container image. For acutal model training examples, go to `examples` directory.

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you setup a Slurm cluster using the templates in the architectures [directory](../../1.architectures). Before creating the Slurm cluster, you need to setup the following environment variables:

```bash
export APPS_PATH=/fsx/apps
export ENROOT_IMAGE=$APPS_PATH/composer.sqsh
```

then follow the detailed instructions [here](../../1.architectures/2.aws-parallelcluster/README.md).

## 2. Build the container

Before running training jobs, you need to use an [Enroot](https://github.com/NVIDIA/enroot) container to retrieve and preprocess the input data. 
The image we use in this test case is based on the [AWS PyTorch base image](../../2.ami_and_containers/containers/pytorch). Make suer the image is built and tagged as `nvidia-pt-aws:latest` prior to the test case image build.
Below are the steps you need to follow to build the base image and the test case image:

1. Copy the test case files to your cluster. You will need `0.composer.Dockerfile`,
2. Build the Docker image with the command below in this directory.

   ```bash
   pushd  ../../2.ami_and_containers/containers/pytorch
   docker build -t nvidia-pt -f 0.nvcr-pytorch-aws.dockerfile .
   popd
   docker build -t composer -f 0.composer.Dockerfile .
   ```

3. Once the Docker image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```bash
   REPOSITORY         TAG                                  IMAGE ID       CREATED       SIZE
   composer           latest                               a964fb32cd53   2 weeks ago   23.6GB
   ...
   ```

4. Convert the Docker image to a squash file with the command below.

   ```bash
   enroot import -o ${ENROOT_IMAGE} dockerd://composer:latest
   ```

   The file will be stored in the `/fsx/apps` directory (default). The output should look as below.

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

For ease of testing we've included a `Makefile` that automatically builds and imports the latest image. To run this, execute `make` or you can individually specify `make build` to build the Docker image, `make clean` to remove the squash file and `make import` to import the Dockerfile into enroot squash file.

## 3. Next steps


## 4. Authors / Reviewers

* [A] Keita Watanabe - mlkeita@
* [R] Pierre-Yves Aquilanti - pierreya@
* [R] Verdi March - marcverd@
