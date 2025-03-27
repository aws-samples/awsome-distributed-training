> | Variable              | Default      | Repository                                                                                  |
> |-----------------------|--------------|---------------------------------------------------------------------------------------------|
> |`GDRCOPY_VERSION`      | `v2.4.1`     | [link](https://github.com/NVIDIA/gdrcopy)                                                   |
> |`EFA_INSTALLER_VERSION`| `1.37.0`     | [link](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html#efa-start-enable) |
> |`AWS_OFI_NCCL_VERSION` | `v1.13.2-aws`| [link](https://github.com/aws/aws-ofi-nccl)                                                 |
> |`NCCL_VERSION`         | `v2.23.4-1`  | [link](https://github.com/NVIDIA/nccl)                                                      |
> |`NCCL_TESTS_VERSION`   | `v2.13.10`   | [link](https://github.com/NVIDIA/nccl-tests)                                                |
> |`NVSHMEM_VERSION`      | `3.2.5-1`    | [link](https://developer.nvidia.com/nvshmem)                                                |



EFA_INSTALLER_VERSION=1.37.0
AWS_OFI_NCCL_VERSION=v1.13.2-aws
NCCL_VERSION=v2.23.4-1
NCCL_TESTS_VERSION=v2.13.10
TAG="efa${EFA_INSTALLER_VERSION}-ofi${AWS_OFI_NCCL_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}"
NCCL_CONTAINER_IMAGE_NAME_TAG="nccl-tests:${TAG}"

docker build --progress=plain -f nccl-tests.Dockerfile \
       --build-arg="EFA_INSTALLER_VERSION=${EFA_INSTALLER_VERSION}" \
       --build-arg="AWS_OFI_NCCL_VERSION=${AWS_OFI_NCCL_VERSION}" \
       --build-arg="NCCL_VERSION=${NCCL_VERSION}" \
       --build-arg="NCCL_TESTS_VERSION=${NCCL_TESTS_VERSION}" \
       -t ${NCCL_CONTAINER_IMAGE_NAME_TAG} \
       .



NVSHMEM_VERSION=3.2.5-1
TAG="efa${EFA_INSTALLER_VERSION}-ofi${AWS_OFI_NCCL_VERSION}-nccl${NCCL_VERSION}-tests${NCCL_TESTS_VERSION}-nvshmem${NVSHMEM_VERSION}"
NVSHMEM_CONTAINER_IMAGE_NAME_TAG="nvshmem:${TAG}"

docker build --progress=plain --no-cache -f nvshmem.Dockerfile \
       --build-arg="EFA_INSTALLER_VERSION=${EFA_INSTALLER_VERSION}" \
       --build-arg="AWS_OFI_NCCL_VERSION=${AWS_OFI_NCCL_VERSION}" \
       --build-arg="NCCL_VERSION=${NCCL_VERSION}" \
       --build-arg="NCCL_TESTS_VERSION=${NCCL_TESTS_VERSION}" \
       --build-arg="NVSHMEM_VERSION=${NVSHMEM_VERSION}" \
       -t ${NVSHMEM_CONTAINER_IMAGE_NAME_TAG} \
       .



enroot import -o /fsx/nvshmem.sqsh dockerd://${NVSHMEM_CONTAINER_IMAGE_NAME_TAG}


srun --mpi=pmi2 --cpu-bind=none --container-image /fsxl/belevich/nvshmem.sqsh -n 2 bash -c "LD_LIBRARY_PATH=/opt/amazon/pmix/lib:/opt/nvshmem/lib:\$LD_LIBRARY_PATH /opt/nvshmem/bin/perftest/device/pt-to-pt/shmem_put_bw"

srun --mpi=pmi2 --cpu-bind=none --container-image /fsxl/belevich/DeepEP/deepep.sqsh -n 2 bash -c "LD_LIBRARY_PATH=/opt/amazon/pmix/lib:/opt/nvshmem/lib:\$LD_LIBRARY_PATH NVSHMEM_BOOTSTRAP_PMI=PMI2 /opt/nvshmem/bin/perftest/device/pt-to-pt/shmem_put_bw"