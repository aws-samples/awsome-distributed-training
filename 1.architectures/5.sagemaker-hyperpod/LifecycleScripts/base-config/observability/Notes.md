

- To download container images, we need to add following permissions to the IAM role.

    Additional required permissions:

    - ecr:GetAuthorizationToken
    - ecr:BatchGetImage
    - ecr:GetDownloadUrlForLayer


    Otherwise we get following error message:

    > An error occurred (AccessDeniedException) when calling the GetAuthorizationToken operation: User: arn:aws:sts::662012767933:assumed-role/sagemaker-slurm-observability-1-c77364c3ExecRole/SageMaker is not authorized to perform: ecr:GetAuthorizationToken on resource: * because no identity-based policy allows the ecr:GetAuthorizationToken action

    > Error response from daemon: pull access denied for 602401143452.dkr.ecr.us-west-2.amazonaws.com/hyperpod/dcgm_exporter, repository does not exist or may require 'docker login': denied: User: arn:aws:sts::662012767933:assumed-role/sagemaker-slurm-observability-1-c77364c3ExecRole/SageMaker is not authorized to perform: ecr:BatchGetImage on resource: arn:aws:ecr:us-west-2:602401143452:repository/hyperpod/dcgm_exporter because no identity-based policy allows the ecr:BatchGetImage action

- AmazonPrometheusRemoteWriteAccess is also needed

- Adding "aws ecr get-login-password" in multiple places but this can be a single place.

- There are multiple install_xyz_exporter.sh but they take almost same structure. I should consider having a same docker image pulling/running function

- localhost:8080 ... should reconsider the port number for slurm-exporter. 8080 is often used for "my HTTP server".

- "instance" attribute should use hostname.

    > node_cpu_seconds_total{cpu="16", instance="localhost:9100", job="node-exporter", mode="nice"}

    > node_amazonefa_send_wrs_total{device="rdmap0s26", instance="localhost:9109", job="efa_exporter", port="1"}

    > DCGM_FI_DEV_MEMORY_TEMP{DCGM_FI_DRIVER_VERSION="570.172.08", Hostname="ip-10-1-201-66", UUID="GPU-4e7a917e-1cac-ddf5-0730-d55dcc6fddb6", device="nvidia0", gpu="0", instance="localhost:9400", job="dcgm_exporter", modelName="NVIDIA A10G", pci_bus_id="00000000:00:1B.0"}

    > slurm_nodes_fail{instance="localhost:8080", job="slurm_exporter"}
