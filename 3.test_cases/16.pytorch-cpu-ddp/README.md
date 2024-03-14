# PyTorch DDP on CPU <!-- omit in toc -->

This test case is intended to provide a simple distributed training example on CPU using [PyTorch DDP](https://pytorch.org/tutorials/beginner/ddp_series_theory.html).

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

Output of the training job can be found in `logs` directory:

```bash
# cat logs/cpu-ddp_xxx.out
Node IP: 10.1.96.108
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] master_addr is only used for static rdzv_backend and when rdzv_endpoint is not specified.
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] 
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] *****************************************
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] Setting OMP_NUM_THREADS environment variable for each process to be 1 in default, to avoid your system being overloaded, please further tune the variable for optimal performance in your application as needed. 
[2024-03-12 08:22:45,549] torch.distributed.run: [WARNING] *****************************************
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO] Starting elastic_operator with launch configs:
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   entrypoint       : ddp.py
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   min_nodes        : 2
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   max_nodes        : 2
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   nproc_per_node   : 4
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   run_id           : 5982
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_backend     : c10d
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_endpoint    : 10.1.96.108:29500
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   rdzv_configs     : {'timeout': 900}
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   max_restarts     : 0
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   monitor_interval : 5
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   log_dir          : None
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO]   metrics_cfg      : {}
[2024-03-12 08:22:45,549] torch.distributed.launcher.api: [INFO] 
[2024-03-12 08:22:45,552] torch.distributed.elastic.agent.server.local_elastic_agent: [INFO] log directory set to: /tmp/torchelastic_9g50nxjq/5982_tflt1tcd
[2024-03-12 08:22:45,552] torch.distributed.elastic.agent.server.api: [INFO] [default] starting workers for entrypoint: python
...
[RANK 3] Epoch 49 | Batchsize: 32 | Steps: 8
[RANK 5] Epoch 49 | Batchsize: 32 | Steps: 8
[RANK 4] Epoch 49 | Batchsize: 32 | Steps: 8
[2024-03-12 08:22:56,574] torch.distributed.elastic.agent.server.api: [INFO] [default] worker group successfully finished. Waiting 300 seconds for other agents to finish.
[2024-03-12 08:22:56,574] torch.distributed.elastic.agent.server.api: [INFO] Local worker group finished (WorkerState.SUCCEEDED). Waiting 300 seconds for other agents to finish
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] [default] worker group successfully finished. Waiting 300 seconds for other agents to finish.
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Local worker group finished (WorkerState.SUCCEEDED). Waiting 300 seconds for other agents to finish
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Done waiting for other agents. Elapsed: 0.0010929107666015625 seconds
[2024-03-12 08:22:56,575] torch.distributed.elastic.agent.server.api: [INFO] Done waiting for other agents. Elapsed: 0.0005395412445068359 seconds
```

