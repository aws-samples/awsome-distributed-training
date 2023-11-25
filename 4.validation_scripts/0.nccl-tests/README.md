# NCCL Tests

[NCCL Tests](https://github.com/NVIDIA/nccl-tests) enable you to evaluate the performance of the network using the Nvidia Collective Communication Library. This test case contains a Docker file and scripts to submit NCCL tests on Slurm or [Amazon EKS](https://aws.amazon.com/eks/). Please refer to the relevant instructions below, depending on your environment.

## 0. Prepare the runtime environment

### Slurm 
If you are using Slurm, this guide assumes that you have the following:

- A functional Slurm cluster on AWS.
- Docker, [Pyxis](https://github.com/NVIDIA/pyxis) and [Enroot](https://github.com/NVIDIA/enroot) installed.
- Enroot requires libmd to compile and squashfs-tools to execute.
- A shared directory mounted on `/apps`

It is recommended that you use the templates in the architectures [directory](../../1.architectures)

### Amazon EKS
If you are using EKS, this guide assumes that you have the following:

- A functional EKS cluster on AWS. <br/>
To set up one, please refer to [aws-do-eks](https://bit.ly/do-eks), [Amazon EKS Blueprints for Terraform](https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main), [Amazon EKS Blueprints for CDK](https://aws-quickstart.github.io/cdk-eks-blueprints/), or others.
- NVIDIA device plugin deployed to your cluster. <br/>
If you need to deploy it, please refer to [deployment/nvidia-device-plugin](https://github.com/aws-samples/aws-do-eks/blob/main/Container-Root/eks/deployment/nvidia-device-plugin) or [k8s-device-plugin/deployments](https://github.com/NVIDIA/k8s-device-plugin/tree/main/deployments).
- EFA devide plugin deployed to your cluster. <br/>
If you need to deploy it, please refer to [deployment/efa-device-plugin](https://github.com/aws-samples/aws-do-eks/tree/main/Container-Root/eks/deployment/efa-device-plugin) or [aws-efa-eks](https://github.com/aws-samples/aws-efa-eks).
- Kubeflow MPI operator deployed to your cluster. <br/>
If you need to deploy it, please refer to [deployment/kubeflow/mpi-operator](https://github.com/aws-samples/aws-do-eks/tree/main/Container-Root/eks/deployment/kubeflow/mpi-operator) or [kubeflow/mpi-operator](https://github.com/kubeflow/mpi-operator). 
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-install)

## 1. Prepare the container image and other artifacts

The NCCL tests are packaged in a container.

> You can set versions and the branch for NCCL and EFA by editing the variables below in the Dockerfile.

> | Variable              | Default     |
> |-----------------------|-------------|
> |`EFA_INSTALLER_VERSION`| `latest`    |
> |`AWS_OFI_NCCL_VERSION` | `aws`       |
> |`NCCL_TESTS_VERSION`   | `master`    |
> |`NCCL_VERSION`         | `v2.12.7-1` |

### Slurm

To run the NCCL tests on Slurm, you will need to build the container then convert it into a Squash file using Enroot.

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

### Amazon EKS

To run the NCCL tests on EKS, you will need to build the container image, then push it to a container registry, such as the private [ECR](https://aws.amazon.com/ecr/) in your AWS account.

1. Build the container URI:
   ```bash
   export AWS_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
   export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   export REGISTRY=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/
   export IMAGE=nccl-tests
   export TAG=:latest
   ```

2. Build the container image:
   ```bash
   docker image build -t ${REGISTRY}${IMAGE}${TAG} -f ./0.nccl-tests.Dockerfile .
   ```

3. Create the ECR repository if it does not exis
   ```bash
   REGISTRY_COUNT=$(aws ecr describe-repositories | grep ${IMAGE} | wc -l)
   if [ "$REGISTRY_COUNT" == "0" ]; then
         aws ecr create-repository --repository-name ${IMAGE}
   fi
   ```

4. Login to the container registry
   ```bash
   aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY
   ```

5. Push the container image to the registry
   ```bash
   docker image push ${REGISTRY}${IMAGE}${TAG}
   ```

## 2. Running the NCCL Tests

### Slurm

Copy the file `1.nccl-tests.sbatch` or its content on your cluster then submit a preprocessing jobs with the command below:

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

### 2.1 Measure multiple collectives with one job

Run the NCCL tests for different collectives in one job using the submission script `2.nccl-3collectives.sbatch`. It will execute tests on the collectives [AllReduce](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/collectives.html#allreduce), [AllGather](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/collectives.html#allgather) and [ReduceScatter](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/collectives.html#reducescatter).

```bash
sbatch 2.nccl-3collectives.sbatch
```


### 2.2 Validate the NCCL configuration

You can validate your environment for NCCL using the batch file `3.nccl-validate.sbatch`. Submit it as follows:

```bash
sbatch 3.nccl-validate.sbatch
```

### Amazon EKS

1. Prepare the MPIJob manifest
   Edit file `nccl-test-eks.yaml` and adjust the following values:

   - slotsPerWorker: 8 <- set to the number of GPUs per node in your cluster
   - image: <account>.dkr.ecr.<region>.amazonaws.com/<image>:<tag> <- set to your container image URI. Note: change both locations in the file. You may use `echo ${REGISTRY}${IMAGE}${TAG}` to print the image URI.
   - -np 16 <- set -np option in mpirun to (number_of_worker_nodes * number_of_gpus_per_node)
   - other mpirun parameters if needed for your instance type, please refer to [aws-ofi-nccl](https://github.com/aws/aws-ofi-nccl/blob/master/doc/efa-env-var.md)
   - replicas: 2 <- set to number of worker pods you would like the test to run on. This must be less than or eaqual to the number of nodes in your cluster.
   - node.kubernetes.io/instance-type: "p5.48xlarge" <- set to the instance type of the nodes in your cluster against which you would like the nccl test to be run
   - nvidia.com/gpu: 8 <- set to the number of GPUs per node in your cluster, adjust in both the limits and requests section
   - vpc.amazonaws.com/efa: 32 <- set to the number of EFA adapters per node in your cluster, adjust in both the limits and requests section

   Please note that the current default settings have been specified for instance type p5.48xlarge. Only the image URI is required to be set for running the test on this instance type.
   The current manifest executes the `all_reduce_perf` test. If you wish to execute other NCCL tests, change the section between lines 59 and 73 in this MPIJob manifest file. 

2. Apply the MPIJob manifest to the cluster
   ```bash
   kubectl apply -f ./nccl-test-eks.yaml
   ```

3. Wait until pods to enter the Running state
   To monitor the state of the pods, execute the following command:
   ```bash
   watch kubectl get pods -o wide
   ```
   Once the state of the launcher and worker pods becomes "Running", press `Ctrl-C` to return to the command prompt.

4. View test logs
   To follow the test logs, execute the following command:
   ```bash
   kubectl logs -f $(kubectl get pods | grep launcher | cut -d ' ' -f 1)
   ```

   The following is an example exerpt from the logs of a NCCL all_reduce_perf test, executed on a cluster with two p5.48xlarge instances:
   ```log
   [1,0]<stdout>:#                                                              out-of-place                       in-place          
   [1,0]<stdout>:#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
   [1,0]<stdout>:#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
   [1,0]<stdout>:           0             0     float     sum      -1    15.51    0.00    0.00      0    15.52    0.00    0.00      0
   [1,0]<stdout>:           0             0     float     sum      -1    15.51    0.00    0.00      0    15.50    0.00    0.00      0
   [1,0]<stdout>:           4             1     float     sum      -1    202.2    0.00    0.00      0    179.4    0.00    0.00      0
   [1,0]<stdout>:           8             2     float     sum      -1    175.5    0.00    0.00      0    178.2    0.00    0.00      0
   [1,0]<stdout>:          16             4     float     sum      -1    177.6    0.00    0.00      0    176.1    0.00    0.00      0
   [1,0]<stdout>:          32             8     float     sum      -1    175.8    0.00    0.00      0    173.1    0.00    0.00      0
   [1,0]<stdout>:          64            16     float     sum      -1    175.7    0.00    0.00      0    172.9    0.00    0.00      0
   [1,0]<stdout>:         128            32     float     sum      -1    171.8    0.00    0.00      0    174.8    0.00    0.00      0
   [1,0]<stdout>:         256            64     float     sum      -1    176.7    0.00    0.00      0    172.4    0.00    0.00      0
   [1,0]<stdout>:         512           128     float     sum      -1    174.4    0.00    0.01      0    176.8    0.00    0.01      0
   [1,0]<stdout>:        1024           256     float     sum      -1    172.0    0.01    0.01      0    175.1    0.01    0.01      0
   [1,0]<stdout>:        2048           512     float     sum      -1    175.9    0.01    0.02      0    174.6    0.01    0.02      0
   [1,0]<stdout>:        4096          1024     float     sum      -1    174.1    0.02    0.04      0    174.7    0.02    0.04      0
   [1,0]<stdout>:        8192          2048     float     sum      -1    175.7    0.05    0.09      0    176.5    0.05    0.09      0
   [1,0]<stdout>:       16384          4096     float     sum      -1    224.9    0.07    0.14      0    183.8    0.09    0.17      0
   [1,0]<stdout>:       32768          8192     float     sum      -1    193.8    0.17    0.32      0    191.2    0.17    0.32      0
   [1,0]<stdout>:       65536         16384     float     sum      -1    194.9    0.34    0.63      0    194.8    0.34    0.63      0
   [1,0]<stdout>:      131072         32768     float     sum      -1    203.8    0.64    1.21      0    204.2    0.64    1.20      0
   [1,0]<stdout>:      262144         65536     float     sum      -1    218.7    1.20    2.25      0    217.7    1.20    2.26      0
   [1,0]<stdout>:      524288        131072     float     sum      -1    225.7    2.32    4.36      0    225.9    2.32    4.35      0
   [1,0]<stdout>:     1048576        262144     float     sum      -1    239.3    4.38    8.22      0    245.5    4.27    8.01      0
   [1,0]<stdout>:     2097152        524288     float     sum      -1    269.9    7.77   14.57      0    306.0    6.85   12.85      0
   [1,0]<stdout>:     4194304       1048576     float     sum      -1    305.7   13.72   25.72      0    302.2   13.88   26.02      0
   [1,0]<stdout>:     8388608       2097152     float     sum      -1    336.1   24.96   46.79      0    335.2   25.02   46.92      0
   [1,0]<stdout>:    16777216       4194304     float     sum      -1    530.9   31.60   59.25      0    564.3   29.73   55.74      0
   [1,0]<stdout>:    33554432       8388608     float     sum      -1    859.2   39.05   73.23      0    856.8   39.16   73.43      0
   [1,0]<stdout>:    67108864      16777216     float     sum      -1    996.0   67.38  126.33      0   1001.7   66.99  125.62      0
   [1,0]<stdout>:   134217728      33554432     float     sum      -1   1950.5   68.81  129.02      0   1725.6   77.78  145.83      0
   [1,0]<stdout>:   268435456      67108864     float     sum      -1   3010.8   89.16  167.17      0   3020.7   88.87  166.62      0
   [1,0]<stdout>:   536870912     134217728     float     sum      -1   3608.0  148.80  279.00      0   3599.7  149.14  279.64      0
   [1,0]<stdout>:  1073741824     268435456     float     sum      -1   6426.3  167.09  313.29      0   6426.1  167.09  313.29      0
   [1,0]<stdout>:  2147483648     536870912     float     sum      -1   9197.5  233.49  437.79      0   9195.2  233.54  437.89      0
   [1,0]<stdout>:# Out of bounds values : 0 OK
   [1,0]<stdout>:# Avg bus bandwidth    : 52.9753
   ```
   Press `Ctrl-C` to return to the command prompt if you do not wish to wait until the launcher pod enters the "Completed" state.

5. Clean up test run
   Before running a subsequent test, the current MPIJob needs to be deleted:
   ```bash
   kubectl delete -f nccl-test-eks.yaml
   ```

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
