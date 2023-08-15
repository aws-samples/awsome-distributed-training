# NCCL Tests

[NCCL Tests](https://github.com/NVIDIA/nccl-tests) enable you to evaluate the performance of the network using the Nvidia Collective Communication Library. This test case contains a Docker file and a Slurm submission scripts so you can run NCCL tests on Slurm.

## 0. Preparation

This guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- Enroot requires libmd to compile and squashfs-tools to execute.
- A shared directory mounted on `/apps`

It is recommended that you use the templates in the architectures [directory](../../1.architectures)


## 1. Build the container and the Squash file

The NCCL tests are packaged in a container for reproducibility purposes, to run it on Slurm you will need to build your container then convert it into a Squash file using Enroot.

To build the container:

1. Copy the file `0.nccl-tests.Dockerfile` or its content to your head-node.
2. Build the container image with the command below
   ```bash
   docker build -t nccl-tests -f 0.nccl-tests.Dockerfile .
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
   enroot import -o /apps/nccl.sqsh  dockerd://nccl-tests:latest
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
...
0:    536870912       8388608     float    none       0   6561.3   81.82   76.71      0   6508.3   82.49   77.33      0
0:   1073741824      16777216     float    none       0    12828   83.70   78.47      0    12809   83.82   78.59      0
0:   2147483648      33554432     float    none       0    25421   84.48   79.20      0    25283   84.94   79.63      0
```


To change the type of collective to test, modify the line with `srun` in the file `1.nccl-tests.sbatch` and change `scatter_perf` to any of: `all_gather_perf`, `alltoall_perf`, `gather_perf`, `reduce_perf`, `scatter_perf`, `all_reduce_perf`, `broadcast_perf`, `hypercube_perf`, `reduce_scatter_perf`, `sendrecv_perf`.


## 3. Understanding NCCL Bandwidth

The NCCL tests reports metrics for the time to execute a given communication collective operation, the Algorithmic bandwidth and the bus bandwidth.

The algorithm bandwidth is based on the following data_size / time where data_size is the size of the data being exchanged through the collective operation while time is the time taken by the operation. The bus bandwidth is generated using a formula specific to each collective operation to reflect the speed of inter-GPU communications. This metric can be used to compare to the hardware peak bandwidth “independently to the number of ranks used” (as shared here).

| API           | Algbw                                              | Busbw                                    | Theoretical Max BW    | source                              |
|---------------|----------------------------------------------------|------------------------------------------|-----------------------|-------------------------------------|
| AllReduce     | baseBw = (count * typesize) / 1.0E9 / sec          | busBw = baseBw * (2*(nranks - 1)/nranks) | B = S/t * (2*(n-1)/n) | https://tinyurl.com/all-reduce      |
| ReduceScatter | baseBw = (count * nranks * typesize) / 1.0E9 / sec | busBw = baseBw * ((nranks - 1)/nranks)   | B = S/t * (n-1)/n     | https://tinyurl.com/reduce-scatter  |
| AllGather     | baseBw = (count * typesize) / 1.0E9 / sec          | busBw = baseBw * ((nranks - 1)/nranks)   | B = S/t * (n-1)/n     | https://tinyurl.com/all-gather      |
| Broadcast     | baseBw = (count * typesize) / 1.0E9 / sec          | busBw = baseBw                           | B = S/t               | https://tinyurl.com/nccl-broadcast  |
| Gather        | baseBw = (count * nranks * typesize) / 1.0E9 / sec | busBw = baseBw * ((nranks - 1)/nranks)   | B = S/t * (n-1)/n     | https://tinyurl.com/nccl-gather     |
| Reduce        | baseBw = (count * typesize) / 1.0E9 / sec          | busBw = baseBw                           | B = S/t               | https://tinyurl.com/nccl-reduce     |
| Scatter       | baseBw = (count * nranks * typesize) / 1.0E9 / sec | busBw = baseBw * ((nranks - 1)/nranks)   | B = S/t * (n-1)/n     | https://tinyurl.com/nccl-scatter    |
| AlltoAll      | baseBw = (count * nranks * typesize) / 1.0E9 / sec | busBw = baseBw * ((nranks - 1)/nranks)   | B = S/t * (n-1)/n     | https://tinyurl.com/nccl-all-to-all |
| SendRecv      | baseBw = (count * typesize) / 1.0E9 / sec          | busBw = baseBw                           | B = S/t               | https://tinyurl.com/sendrcv         |



#### Notes for Algbw & Busbw**

* `typesize` : size of the data type transferred in bytes (2 bytes for half-precision, 4 for single precision....).
* `count` : number of elements transferred through the collective communication operation.
* `nranks` : number of ranks participating to the collective communication operation.
* `sec` : time in seconds to execute the collective communication operation.

#### Notes for the Theoretical Max BW

The formula defines the maximum theoretical bandwidth that can be achieved on different communication collectives in the ideal case.

* `n` : number of ranks participating to the operation. (similar to nranks for Algbw and Busbw)
* `t` : time to complete the operation. (similar to sec for Algbw and Busbw)
* `S` : number of elements being communicated (similar to count for Algbw and Busbw)
* `B` : theoretical peak bandwidth.
