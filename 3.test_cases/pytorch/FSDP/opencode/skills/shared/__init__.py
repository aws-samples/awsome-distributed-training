"""
Shared utilities for opencode Docker/ECR skills.
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
    # Logger
    'SkillLogger',
    'StatusReporter',
    'LogLevel',
    'create_logger'
]
