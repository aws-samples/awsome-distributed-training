

- To download container images, we need to add following permissions to the IAM role.

    Additional required permissions:

    - ecr:GetAuthorizationToken
    - ecr:BatchGetImage
    - ecr:GetDownloadUrlForLayer


    Otherwise we get following error message:

    > An error occurred (AccessDeniedException) when calling the GetAuthorizationToken operation: User: arn:aws:sts::662012767933:assumed-role/sagemaker-slurm-observability-1-c77364c3ExecRole/SageMaker is not authorized to perform: ecr:GetAuthorizationToken on resource: * because no identity-based policy allows the ecr:GetAuthorizationToken action

    > Error response from daemon: pull access denied for 602401143452.dkr.ecr.us-west-2.amazonaws.com/hyperpod/dcgm_exporter, repository does not exist or may require 'docker login': denied: User: arn:aws:sts::662012767933:assumed-role/sagemaker-slurm-observability-1-c77364c3ExecRole/SageMaker is not authorized to perform: ecr:BatchGetImage on resource: arn:aws:ecr:us-west-2:602401143452:repository/hyperpod/dcgm_exporter because no identity-based policy allows the ecr:BatchGetImage action


- Adding "aws ecr get-login-password" in multiple places but this can be a single place.

- There are multiple install_xyz_exporter.sh but they take almost same structure. I should consider having a same docker image pulling/running function

- Node exporter and EFA exporter cannot run on a same node. Port number conflict.

    > time=2025-08-19T23:49:10.902Z level=ERROR source=node_exporter.go:247 msg="listen tcp :9100: bind: address already in use"
