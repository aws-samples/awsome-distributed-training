# NCCL Tests

[NCCL Tests](https://github.com/NVIDIA/nccl-tests) enable you to evaluate the performance of the network using the Nvidia Collective Communication Library. This test case contains a Docker file and a Slurm submission scripts so you can run NCCL tests on Slurm.

## 0. Preparation

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- A shared directory mounted on `/apps`
It is recommended that you use the templates in the architectures [directory](../../1.architectures)


## 1. Build the container and the Squash file

The NCCL tests are packaged in a container for reproducibility purposes, to run it on Slurm you will need to build your container then convert it into a Squash file using Enroot.

To build the container:

1. Copy the file `0.nccl-tests.Dockerfile` or its content to your head-node.
2. Build the container image with the command below
   ```bash
   docker build -t nccl-tests -f 1.nccl-tests.Dockerfile .
   ```
3. Once the image is built, you can check if it is present with `docker images`. You should see an output similar to this one:
   ```
   REPOSITORY               TAG                        IMAGE ID       CREATED         SIZE
   nccl                     latest                     6e981e5cf6a5   5 hours ago     8.61GB
   ...
   nvidia/cuda              12.2.0-devel-ubuntu20.04   a86c511c87e1   2 weeks ago     6.56GB
   ```
3. Convert the container image to a squash file via Enroot
   ```bash
   enroot import -o /apps/nccl.sqsh  dockerd://nccl:latest
   ```
   The file will be stored in the `/apps` directory.

> You can set versions and the branch for NCCL and EFA by editing the variables below in the Dockerfile.

> | Variable              | Default     |
> |-----------------------|-------------|
> |`EFA_INSTALLER_VERSION`| `latest`    |
> |`AWS_OFI_NCCL_VERSION` | `aws`       |
> |`NCCL_TESTS_VERSION`   | `master`    |
> |`NCCL_VERSION`         | `v2.12.7-1` |


## 2. Running the NCCL Tests

Now you copy the file `1.nccl-tests.sbatch` or its content on your cluster then submit a preprocessing jobs with the command below:

```bash
sbatch 1.nccl-tests.sbatch
```

A Scatter performance test will be executed from 8B to 2 GB, the output should look as below (with a lot more information).

```
0: #
0: #                                                              out-of-place                       in-place
0: #       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
0: #        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
0:            0             0     float    none       0     0.15    0.00    0.00      0     0.14    0.00    0.00      0
0:            0             0     float    none       0     0.14    0.00    0.00      0     0.14    0.00    0.00      0
0:            0             0     float    none       0     0.13    0.00    0.00      0     0.13    0.00    0.00      0
0:           64             1     float    none       0    88.38    0.00    0.00      0    89.81    0.00    0.00      0
0:          128             2     float    none       0    88.74    0.00    0.00      0    89.43    0.00    0.00      0
0:          256             4     float    none       0    88.76    0.00    0.00      0    88.73    0.00    0.00      0
0:          512             8     float    none       0    88.48    0.01    0.01      0    88.80    0.01    0.01      0
0:         1024            16     float    none       0    88.10    0.01    0.01      0    88.79    0.01    0.01      0
0:         2048            32     float    none       0    88.21    0.02    0.02      0    88.27    0.02    0.02      0
0:         4096            64     float    none       0    88.32    0.05    0.04      0    88.30    0.05    0.04      0
0:         8192           128     float    none       0    88.42    0.09    0.09      0    88.24    0.09    0.09      0
0:        16384           256     float    none       0    90.87    0.18    0.17      0    90.57    0.18    0.17      0
0:        32768           512     float    none       0    93.21    0.35    0.33      0    93.35    0.35    0.33      0
0:        65536          1024     float    none       0    90.94    0.72    0.68      0    90.47    0.72    0.68      0
0:       131072          2048     float    none       0    94.21    1.39    1.30      0    93.69    1.40    1.31      0
0:       262144          4096     float    none       0    102.2    2.56    2.40      0    103.3    2.54    2.38      0
0:       524288          8192     float    none       0    106.5    4.92    4.62      0    113.8    4.61    4.32      0
0:      1048576         16384     float    none       0    123.1    8.51    7.98      0    124.6    8.42    7.89      0
0:      2097152         32768     float    none       0    166.1   12.63   11.84      0    165.7   12.66   11.87      0
0:      4194304         65536     float    none       0    223.2   18.79   17.62      0    224.1   18.72   17.55      0
0:      8388608        131072     float    none       0    374.1   22.42   21.02      0    361.5   23.20   21.75      0
0:     16777216        262144     float    none       0    576.3   29.11   27.29      0    569.0   29.49   27.64      0
0:     33554432        524288     float    none       0    671.7   49.95   46.83      0    670.7   50.03   46.90      0
0:     67108864       1048576     float    none       0   1100.1   61.00   57.19      0   1062.4   63.17   59.22      0
0:    134217728       2097152     float    none       0   1838.9   72.99   68.43      0   1832.9   73.23   68.65      0
0:    268435456       4194304     float    none       0   3435.0   78.15   73.26      0   3386.4   79.27   74.31      0
0:    536870912       8388608     float    none       0   6561.3   81.82   76.71      0   6508.3   82.49   77.33      0
0:   1073741824      16777216     float    none       0    12828   83.70   78.47      0    12809   83.82   78.59      0
0:   2147483648      33554432     float    none       0    25421   84.48   79.20      0    25283   84.94   79.63      0
```


To change the type of collective to test, modify the line with `srun` in the file `1.nccl-tests.sbatch` and change `scatter_perf` to any of: `all_gather_perf`, `alltoall_perf`, `gather_perf`, `reduce_perf`, `scatter_perf`, `all_reduce_perf`, `broadcast_perf`, `hypercube_perf`, `reduce_scatter_perf`, `sendrecv_perf`.
