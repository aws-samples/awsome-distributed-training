# Tensorflow MultiWorkerMirroredStrategy test case <!-- omit in toc -->

`MultiWorkerMirroredStrategy` in TensorFlow is a strategy designed for synchronous training across multiple workers, typically in a multi-node setup. This strategy is a part of TensorFlow's distributed training API. Consult the [official Tensorflow documention](https://www.tensorflow.org/api_docs/python/tf/distribute/experimental/MultiWorkerMirroredStrategy) for more information.

This project contains:

* AWS optimized `tensorflow` container image.
* Slurm scripts for the distributed training. 

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS.
* Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you setup a Slurm cluster using the templates in the architectures [directory](../../1.architectures). Before creating the Slurm cluster, you need to setup the following environment variables:

```bash
export APPS_PATH=/apps
export ENROOT_IMAGE=$APPS_PATH/tensorflow.sqsh
export FSX_PATH=/fsx
export DATA_PATH=$FSX_PATH/mnist
export TEST_CASE_PATH=${HOME}/7.tensorflow-distributed  # where you copy the test case or set to your test case path
cd $TEST_CASE_PATH
```

then follow the detailed instructions [here](../../1.architectures/2.aws-parallelcluster/README.md).

## 2. Build the container

Before running training jobs, you need to use an [Enroot](https://github.com/NVIDIA/enroot) container to retrieve and preprocess the input data. Below are the steps you need to follow:

1. Copy the test case files to your cluster. You will need `0.tensorflow.Dockerfile`,
2. Build the Docker image with the command below in this directory.

   ```bash
   docker build -t tensorflow -f 0.tensorflow.Dockerfile .
   ```

3. Once the Docker image is built, you can check if it is present with `docker images`. You should see an output similar to this one:

   ```bash
   REPOSITORY         TAG                                  IMAGE ID       CREATED          SIZE
   tensorflow         latest                               a94ca0003efb   23 minutes ago   15.3GB
   ...
   ```

4. Convert the Docker image to a squash file with the command below.

   ```bash
   enroot import -o ${ENROOT_IMAGE} dockerd://tensorflow:latest
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

For ease of testing we've included a `Makefile` that automatically builds and imports the latest image. To run this, execute `make` or you can individually specify `make build` to build the Docker image, `make clean` to remove the squash file and `make import` to import the Dockerfile into enroot squash file.

## 3. Run the train job

Here, we will conduct simple NN against mnist dataset.

1. Run a training job by submitting script `1.run-training.sbatch` to Slurm via `sbatch` as shown below.
    ```bash
    sbatch 1.run-training.sbatch
    ```

2. When the training job completes successfully, it should produce a log output similar to the below in the `logs/` directory of `$TEST_CASE_PATH`

    ```console
    ...
    56/70 [=======================>......] - ETA: 1s - loss: 4.0206 - accuracy: 1.0957
    62/70 [=========================>....] - ETA: 0s - loss: 4.0104 - accuracy: 1.1046
    62/70 [=========================>....] - ETA: 0s - loss: 4.0104 - accuracy: 1.1046
    69/70 [============================>.] - ETA: 0s - loss: 3.9982 - accuracy: 1.1101
    69/70 [============================>.] - ETA: 0s - loss: 3.9982 - accuracy: 1.1101
    70/70 [==============================] - 6s 82ms/step - loss: 1.9969 - accuracy: 0.5576
    70/70 [==============================] - 6s 82ms/step - loss: 1.9969 - accuracy: 0.5576
    ```

## 4. Authors / Reviewers

* [A] Keita Watanabe - mlkeita@
* [R] Pierre-Yves Aquilanti - pierreya@
