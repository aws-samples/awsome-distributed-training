# EFA Cheatsheet

## 1. Settings via environment variables

For optimized performance, you may need to set additional environment variables depending on the
versions of your libfabric.

| Setting                        | Explanation                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FI_EFA_USE_HUGE_PAGE=0`       | Set to 0 when you see `os.fork()` causes `OSError: Cannot allocate memory`. Typically happen by multi-process PyTorch data loader. Disabling huge page causes minor performance hit, but it's needed to prevent fork fails due to the operating system running out of huge pages.                                                                     |
| `FI_EFA_FORK_SAFE=1`           | Not needed for kernel>=5.15. Still fine to set it though no effect. See [ref](https://github.com/ofiwg/libfabric/pull/9112).                                                                                                                                                                                                                          |
| `FI_EFA_USE_DEVICE_RDMA=1`     | Do not set for libfabric>=1.18.0 and aws-ofi-nccl>=1.7.0. It's not harmful to set it on p4/p5 on the newer software, but you just don't have to set it.                                                                                                                                                                                               |
| `FI_EFA_ENABLE_SHM_TRANSFER=1` | Not needed. This is really a no-op, the default already to enable SHMEM                                                                                                                                                                                                                                                                               |
| `FI_PROVIDER=efa`              | Use for aws-ofi-nccl<=1.5.0 AND p4/p5 instances.                                                                                                                                                                                                                                                                                                      |
| `NCCL_PROTO=simple`            | Use for aws-ofi-nccl<=1.5.0 and p4/p5 instances.                                                                                                                                                                                                                                                                                                      |
| `NCCL_SOCKET_NTHREADS`         | Not applicable for EFA.                                                                                                                                                                                                                                                                                                                               |
| `NCCL_NSOCKS_PERTHREAD`        | Not applicable for EFA.                                                                                                                                                                                                                                                                                                                               |
| `NCCL_MIN_CHANNELS=xxx`        | Recommend to leave it out to use the default. For e.g., on p4d/p4de, the number of channels should be 8, which is the minimum for a 4-NIC platform. The reduction message is split by number of GPUs in the job, then the number of channels, so having more channels than necessary causes smaller messages which causes EFA to be starved for data. |
| `NCCL_BUFFSIZE=xxx`            | Recommend to leave it out to use the default.                                                                                                                                                                                                                                                                                                         |
| `RDMAV_FORK_SAFE=1`            | Do not use. This is a RDMA-core environment variable. Prefer `FI_EFA_FORK_SAFE` (if it still makes sense for your Linux kernel version). The two looks the same, but actually behaves very differently, especially on newer kernels, where `RDMAV_FORK_SAFE=1` can break things.                                                                      |
| `RDMAV_*`                      | Do not use                                                                                                                                                                                                                                                                                                                                            |
| NCCL version                   | Recommend one of the stable releases.                                                                                                                                                                                                                                                                                                                 |

## 2. A word on p5.48xlarge instances

Use cuda>=12.0, nccl>=2.18.0 (recommend at least 2.18.5), aws-ofi-nccl>=1.7.2 (recommend at least
1.7.3).

## 3. Sample Presets

### 3.1. libfabric>=1.18.0 and aws-ofi-nccl>=1.7.0

```bash
export FI_EFA_USE_HUGE_PAGE=0
```

### 3.2. aws-ofi-nccl>=1.6.0,<1.7.0 AND p4/p5 instances

```bash
export FI_EFA_USE_HUGE_PAGE=0
export FI_EFA_USE_DEVICE_RDMA=1
```

### 3.3. aws-ofi-nccl<=1.5.0 AND p4/p5 instances

```bash
export FI_EFA_USE_HUGE_PAGE=0
export FI_EFA_USE_DEVICE_RDMA=1
export FI_PROVIDER=efa
export NCCL_PROTO=simple
```
