# PyTorch DDP on CPU <!-- omit in toc -->

This test case is intended to provide simplest possible distributed training example on CPU using [PyTorch DDP](https://pytorch.org/tutorials/beginner/ddp_series_theory.html).

## 1. Preparation

This guide assumes that you have the following:

* A functional Slurm cluster on AWS, whose compute instances are based on DeepLearning AMI.
* An FSx for Lustre filesystem mounted on `/fsx`.

We recommend that you setup a Slurm cluster using the templates in the architectures [directory](../../1.architectures). 


## 2. Submit training job

Submit DDP training job with:

```bash
sbatch 1.train.sbatch
```

Output of the training job can be found in `logs` directory.

