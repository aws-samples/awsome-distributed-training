# ML Training Reference Architectures & Tests <!-- omit from toc -->

This repository contains reference architectures and test cases for distributed model training with [AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html), [AWS Batch](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html), and [Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-console.html). The test cases cover different types and sizes of models as well as different frameworks and parallel optimizations (Pytorch DDP/FSDP, MegatronLM, NemoMegatron...).

The major components of this directory are:

```bash
reference-architectures/
|-- 1.architectures/               # CloudFormation templates for reference arch
|-- 2.ami_and_containers/          # Scripts to create AMIs and container images
|-- 3.test_cases/                  # Reference test cases and/or benchmark scripts
|-- 4.validation_observability/    # Tools to measure performance or troubleshoot
`-- ...
```

**NOTE**: the architectures are designed to work with the S3 bucket and VPC created using reference templates `1.architectures/0.s3/` and `1.architectures/1.vpc_network/`. _You're strongly recommended to deploy these two templates **before** deploying any of the reference architectures._

## 1. Architectures

Architectures are located in `1.architectures` and consists of utilities and service related architectures.

| Name                                                               | Category | Usage                                               |
| ------------------------------------------------------------------ | -------- | --------------------------------------------------- |
| [`0.s3`](./1.architectures/0.s3)                                   | Storage  | Create an S3 bucket                                 |
| [`1.vpc_network`](./1.architectures/1.vpc_network)                 | Network  | Create a VPC with subnets required resources        |
| [`2.aws-parallelcluster`](./1.architectures/2.aws-parallelcluster) | Compute  | Cluster templates for GPU & custom silicon training |
| [`3.aws-batch`](./1.architectures/3.aws-batch)                     | Compute  | AWS Batch template for distributed training         |
| [`4.amazon-eks`](./1.architectures/4.amazon-eks)                   | Compute  | Manifest files to train with Amazon EKS             |
| [`5.sagemaker-hyperpod`](./1.architectures/5.sagemaker-hyperpod)   | Compute  | SageMaker HyperPod template for distributed training|

More will come, feel free to add new ones (EKS, Ray?). You will also find [documentation](./1.architectures/efa-cheatsheet.md) for EFA and the recommended environment variables.

## 2. Custom Amazon Machine Images

Custom machine images can be built using [Packer](www.packer.io) for AWS ParallelCluster, Amazon EKS and plain EC2. These images are based are on Ansible roles and playbooks.

## 3. Test cases: support matrix

All test cases are under `3.test_cases/`. You can go in each test case directory to learn how to run it.

| Test cases                                                                    | Slurm | Kubernetes  | AWS Batch  |
| ----------------------------------------------------------------------------- | ----- | ----------- | ---------- |
| [`1.megatron-lm`](./3.test_cases/1.megatron-lm)                               |  ✅   | ❓          | ❓         |
| [`2.nemo-launcher`](./3.test_cases/2.nemo-launcher)                           |  ✅   | ❌          | ❌         |
| [`3.MPT`](./3.test_cases/3.MPT)                                               |  ✅   | ❓          | ❓         |
| [`4.DDP`](./3.test_cases/4.DDP)                                               |  ✅   | ❓          | ❓         |
| [`5.param-benchmark`](./3.test_cases/5.param-benchmark)                       |  ✅   | ❓          | ❓         |
| [`6.stable-diffusion`](./3.test_cases/6.stable-diffusion)                     |  ✅   | ❓          | ❓         |
| [`7.tensorflow-distributed`](./3.test_cases/7.tensorflow-distributed)         |  ✅   | ❓          | ❓         |
| [`8.neuronx-nemo-megatron`](./3.test_cases/8.neuronx-nemo-megatron)           |  ✅   | ❓          | ❓         |
| [`10.FSDP`](./3.test_cases/10.FSDP)                                           |  ✅   | ❓          | ❓         |
| [`11.modelparallel`](./3.test_cases/11.modelparallel)                         |  ✅   | ❓          | ❓         |
| [`12.SM-dataparallel-FSDP`](./3.test_cases/12.SM-dataparallel-FSDP)           |  ✅   | ❓          | ❓         |
| [`13.SM-dataparallel-deepspeed`](./3.test_cases/13.SM-dataparallel-deepspeed) |  ✅   | ❓          | ❓         |

## 4. Validation scripts

Utilities scripts and micro-benchmarks examples are set under `4.validation_scripts/`. The EFA Prometheus exporter can be found in this [directory](./4.validation_and_observability/3.efa-node-exporter) 

## 5. CI

Integration tests are written in [pytest](https://docs.pytest.org). Just run:

```bash
pytest .
```

Alternatively you can run tests with out capturing stdout and keeping all docker images an other artifacts.

```bash
pytest -s --keep-artifacts=t
```

## 6. Contributors

Thanks to all the contributors for building, reviewing and testing.

[![Contributors](https://contrib.rocks/image?repo=aws-samples/awsome-distributed-training)](https://github.com/aws-samples/awsome-distributed-training/graphs/contributors)
