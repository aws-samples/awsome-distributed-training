"""
Shared utilities for opencode Docker/ECR/K8s skills.
"""

from .aws_utils import (
    AWSClient,
    get_aws_profiles,
    validate_aws_credentials,
    docker_login_ecr,
    discover_ecr_repositories,
    get_ecr_repository_uri,
    create_ecr_repository,
    check_s3_bucket_exists,
    create_s3_bucket,
    get_codebuild_project_status
)

from .docker_utils import (
    DockerClient,
    check_docker_installed,
    check_docker_running,
    parse_dockerfile,
    analyze_base_image_compatibility,
    get_recommended_base_image,
    check_image_exists_locally
)

from .k8s_utils import (
    EKSClient,
    K8sClient,
    ClusterValidator,
    ConfigMapManager
)

from .cluster_manager import (
    ClusterManager
)

from .job_deployer import (
    JobDeployer
)

from .failure_analyzer import (
    FailureAnalyzer,
    FailureSeverity,
    FailurePattern
)

from .logger import (
    SkillLogger,
    StatusReporter,
    LogLevel,
    create_logger
)

__all__ = [
    # AWS
    'AWSClient',
    'get_aws_profiles',
    'validate_aws_credentials',
    'docker_login_ecr',
    'discover_ecr_repositories',
    'get_ecr_repository_uri',
    'create_ecr_repository',
    'check_s3_bucket_exists',
    'create_s3_bucket',
    'get_codebuild_project_status',
    # Docker
    'DockerClient',
    'check_docker_installed',
    'check_docker_running',
    'parse_dockerfile',
    'analyze_base_image_compatibility',
    'get_recommended_base_image',
    'check_image_exists_locally',
    # K8s
    'EKSClient',
    'K8sClient',
    'ClusterValidator',
    'ConfigMapManager',
    # Cluster Management
    'ClusterManager',
    # Job Deployment
    'JobDeployer',
    # Failure Analysis
    'FailureAnalyzer',
    'FailureSeverity',
    'FailurePattern',
    # Logger
    'SkillLogger',
    'StatusReporter',
    'LogLevel',
    'create_logger'
]
