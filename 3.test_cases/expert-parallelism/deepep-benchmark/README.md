# DeepEP Benchmark
https://github.com/deepseek-ai/DeepEP

Updated to [NVSHMEM 3.4.5-0](https://github.com/NVIDIA/nvshmem/commit/df2814155acfba6227534dd81a8bf338da9e55f2) and DeepEP [Sep 25, 2025](https://github.com/deepseek-ai/DeepEP/tree/e02e4d2e1fbfdf09e02e870b6acc5831cbd11e39)

## Git clone NVSHMEM

3.4.5-0:
```
git clone https://github.com/NVIDIA/nvshmem.git && cd ./nvshmem && git checkout df2814155acfba6227534dd81a8bf338da9e55f2 && cd ..
```

devel brach:
```
git clone https://github.com/NVIDIA/nvshmem.git && cd ./nvshmem && git checkout devel && cd ..
```

## Building DeepEP Docker image

```bash
GDRCOPY_VERSION=v2.5.1
EFA_INSTALLER_VERSION=1.43.2
NCCL_VERSION=v2.27.7-1
NCCL_TESTS_VERSION=v2.16.9
NVSHMEM_VERSION=3.4.5-0
TAG="efa${EFA_INSTALLER_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}-nvshmem${NVSHMEM_VERSION}"
DEEPEP_CONTAINER_IMAGE_NAME_TAG="deepep:${TAG}"
```

```bash
docker build --progress=plain -f ./deepep.Dockerfile \
       --build-arg="EFA_INSTALLER_VERSION=${EFA_INSTALLER_VERSION}" \
       --build-arg="NCCL_VERSION=${NCCL_VERSION}" \
       --build-arg="NCCL_TESTS_VERSION=${NCCL_TESTS_VERSION}" \
       --build-arg="NVSHMEM_VERSION=${NVSHMEM_VERSION}" \
       -t ${DEEPEP_CONTAINER_IMAGE_NAME_TAG} \
       .
```

```bash
enroot import -o ./deepep.sqsh dockerd://${DEEPEP_CONTAINER_IMAGE_NAME_TAG}
```

## Running DeepEP Benchmark

### Intranode

```bash
srun --mpi=pmix --cpu-bind=none --container-image ./deepep.sqsh python /DeepEP/tests/test_intranode.py
```

## P5en results
DeepEP commit [e02e4d2e1fbfdf09e02e870b6acc5831cbd11e39](https://github.com/deepseek-ai/DeepEP/tree/e02e4d2e1fbfdf09e02e870b6acc5831cbd11e39)
```
[config] num_tokens=4096, hidden=7168, num_topk=8
[layout] Kernel performance: 0.041 ms

[testing] Running with BF16, without top-k (async=False, previous=False) ... passed
[testing] Running with BF16, with top-k (async=False, previous=False) ... passed
[testing] Running with BF16, without top-k (async=False, previous=False) ... passed
[testing] Running with BF16, with top-k (async=False, previous=False) ... passed
[testing] Running with FP8, without top-k (async=False, previous=False) ... passed
[testing] Running with FP8, with top-k (async=False, previous=False) ... passed
[testing] Running with BF16, without top-k (async=True, previous=False) ... passed
[testing] Running with BF16, with top-k (async=True, previous=False) ... passed
[testing] Running with BF16, without top-k (async=True, previous=False) ... passed
[testing] Running with BF16, with top-k (async=True, previous=False) ... passed
[testing] Running with FP8, without top-k (async=True, previous=False) ... passed
[testing] Running with FP8, with top-k (async=True, previous=False) ... passed
[testing] Running with BF16, without top-k (async=False, previous=True) ... passed
[testing] Running with BF16, with top-k (async=False, previous=True) ... passed
[testing] Running with BF16, without top-k (async=False, previous=True) ... passed
[testing] Running with BF16, with top-k (async=False, previous=True) ... passed
[testing] Running with FP8, without top-k (async=False, previous=True) ... passed
[testing] Running with FP8, with top-k (async=False, previous=True) ... passed
[testing] Running with BF16, without top-k (async=True, previous=True) ... passed
[testing] Running with BF16, with top-k (async=True, previous=True) ... passed
[testing] Running with BF16, without top-k (async=True, previous=True) ... passed
[testing] Running with BF16, with top-k (async=True, previous=True) ... passed
[testing] Running with FP8, without top-k (async=True, previous=True) ... passed
[testing] Running with FP8, with top-k (async=True, previous=True) ... passed

[tuning] SMs 24, NVL chunk 4: 294.24 GB/s (NVL), 544.47 us
[tuning] SMs 24, NVL chunk 6: 320.68 GB/s (NVL), 499.58 us
[tuning] SMs 24, NVL chunk 8: 317.79 GB/s (NVL), 504.13 us
[tuning] SMs 24, NVL chunk 10: 316.46 GB/s (NVL), 506.25 us
[tuning] SMs 24, NVL chunk 12: 308.37 GB/s (NVL), 519.53 us
[tuning] SMs 24, NVL chunk 14: 298.15 GB/s (NVL), 537.34 us
[tuning] SMs 24, NVL chunk 16: 292.44 GB/s (NVL), 547.83 us
[tuning] SMs 24, NVL chunk 18: 297.46 GB/s (NVL), 538.58 us
[tuning] SMs 24, NVL chunk 20: 293.29 GB/s (NVL), 546.24 us
[tuning] SMs 24, NVL chunk 22: 287.31 GB/s (NVL), 557.62 us
[tuning] SMs 24, NVL chunk 24: 287.20 GB/s (NVL), 557.83 us
[tuning] SMs 24, NVL chunk 26: 286.76 GB/s (NVL), 558.67 us
[tuning] SMs 24, NVL chunk 28: 287.96 GB/s (NVL), 556.35 us
[tuning] SMs 24, NVL chunk 30: 282.88 GB/s (NVL), 566.33 us
[tuning] SMs 24, NVL chunk 32: 281.40 GB/s (NVL), 569.32 us
[tuning] SMs 24, NVL chunk default: 319.82 GB/s (NVL), 500.93 us
[tuning] Best dispatch (FP8): SMs 24, NVL chunk 6, 320.68 GB/s (NVL), t: 499.58 us

[tuning] SMs 24, NVL chunk 4: 331.77 GB/s (NVL), 936.50 us
[tuning] SMs 24, NVL chunk 6: 304.74 GB/s (NVL), 1019.58 us
[tuning] SMs 24, NVL chunk 8: 305.57 GB/s (NVL), 1016.81 us
[tuning] SMs 24, NVL chunk 10: 305.73 GB/s (NVL), 1016.26 us
[tuning] SMs 24, NVL chunk 12: 303.80 GB/s (NVL), 1022.74 us
[tuning] SMs 24, NVL chunk 14: 300.82 GB/s (NVL), 1032.85 us
[tuning] SMs 24, NVL chunk 16: 300.27 GB/s (NVL), 1034.75 us
[tuning] SMs 24, NVL chunk 18: 301.12 GB/s (NVL), 1031.83 us
[tuning] SMs 24, NVL chunk 20: 298.67 GB/s (NVL), 1040.29 us
[tuning] SMs 24, NVL chunk 22: 296.76 GB/s (NVL), 1046.98 us
[tuning] SMs 24, NVL chunk 24: 296.46 GB/s (NVL), 1048.05 us
[tuning] SMs 24, NVL chunk 26: 294.70 GB/s (NVL), 1054.29 us
[tuning] SMs 24, NVL chunk 28: 293.73 GB/s (NVL), 1057.80 us
[tuning] SMs 24, NVL chunk 30: 292.28 GB/s (NVL), 1063.03 us
[tuning] SMs 24, NVL chunk 32: 292.16 GB/s (NVL), 1063.47 us
[tuning] SMs 24, NVL chunk default: 305.72 GB/s (NVL), 1016.31 us
[tuning] Best dispatch (BF16): SMs 24, NVL chunk 4, 331.77 GB/s (NVL), t: 936.50 us

[tuning] SMs 24, NVL chunk 1: 159.88 GB/s (NVL), 1943.39 us
[tuning] SMs 24, NVL chunk 2: 277.52 GB/s (NVL), 1119.56 us
[tuning] SMs 24, NVL chunk 3: 316.19 GB/s (NVL), 982.64 us
[tuning] SMs 24, NVL chunk 4: 321.89 GB/s (NVL), 965.24 us
[tuning] SMs 24, NVL chunk 5: 311.73 GB/s (NVL), 996.72 us
[tuning] SMs 24, NVL chunk 6: 294.88 GB/s (NVL), 1053.67 us
[tuning] SMs 24, NVL chunk 7: 304.14 GB/s (NVL), 1021.57 us
[tuning] SMs 24, NVL chunk 8: 288.61 GB/s (NVL), 1076.55 us
[tuning] SMs 24, NVL chunk 9: 284.72 GB/s (NVL), 1091.26 us
[tuning] SMs 24, NVL chunk 10: 289.42 GB/s (NVL), 1073.55 us
[tuning] SMs 24, NVL chunk 11: 284.57 GB/s (NVL), 1091.85 us
[tuning] SMs 24, NVL chunk 12: 284.85 GB/s (NVL), 1090.75 us
[tuning] SMs 24, NVL chunk 13: 288.21 GB/s (NVL), 1078.05 us
[tuning] SMs 24, NVL chunk 14: 285.78 GB/s (NVL), 1087.20 us
[tuning] SMs 24, NVL chunk 15: 283.55 GB/s (NVL), 1095.76 us
[tuning] SMs 24, NVL chunk 16: 283.94 GB/s (NVL), 1094.27 us
[tuning] SMs 24, NVL chunk default: 319.88 GB/s (NVL), 971.32 us
[tuning] Best combine: SMs 24, NVL chunk 4: 321.89 GB/s (NVL), t: 965.24 us
```

### Internode

```bash
srun \
  -l --mpi=pmix --cpu-bind=none \
  --container-image ./deepep.sqsh \
  -N 2 \
  bash -c 'MASTER_ADDR=${SLURM_NODELIST%%,*} WORLD_SIZE=$SLURM_NNODES RANK=$SLURM_PROCID NVSHMEM_REMOTE_TRANSPORT=libfabric NVSHMEM_LIBFABRIC_PROVIDER=efa python3 -u -X faulthandler /DeepEP/tests/test_internode.py'
```
