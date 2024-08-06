# MaxText slurm test cases

Here we describes how to run distributed training with MaxText on Slurm cluster.

* A functional Slurm cluster on AWS, whose compute instances are based on DeepLearning AMI.
* An FSx for Lustre filesystem mounted on `/fsx`.
* `enroot` if you want to run the container example.
* The [MaxText container](..) is built on the headnode.

## Convert image
Convert the Docker container image to an [Enroot](https://github.com/NVIDIA/enroot) squash file that will be stored in `/fsx/ubuntu/images`. This step takes a few minutes.

```bash
DOCKER_IMAGE=maxtext:jetstream-v0.2.2
ENROOT_IMAGE=/fsx/ubuntu/images/maxtext-jetstream-v0.2.2.sqsh
[ ! -e ${ENROOT_IMAGE} ] || rm ${ENROOT_IMAGE}
enroot import -o ${ENROOT_IMAGE} dockerd://${DOCKER_IMAGE}
```

```text
[INFO] Fetching image

38061de404ddd45685276abdb6a8bf2e8e240dfd8ae3622c45b8a4a820ee1d06

[INFO] Extracting image content...
[INFO] Creating squashfs filesystem...

Parallel mksquashfs: Using 32 processors
Creating 4.0 filesystem on /fsx/ubuntu/images/maxtext-jetstream-v0.2.2.sqsh, block size 131072.
[==============================================================================================================================================================================================================|] 239581/239581 100%

Exportable Squashfs 4.0 filesystem, gzip compressed, data block size 131072
        uncompressed data, uncompressed metadata, uncompressed fragments,
        uncompressed xattrs, uncompressed ids
        duplicates are not removed
...
```

Once done proceed to the next stage.

## Run training job

```bash
sbatch 0.synthetic-data.sbatch
```
