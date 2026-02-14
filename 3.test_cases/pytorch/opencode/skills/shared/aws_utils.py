"""
Shared AWS utilities for opencode skills.
"""

import boto3
import subprocess
import json
from typing import Optional, Dict, List
from botocore.exceptions import ClientError


class AWSClient:
    """AWS client wrapper with profile support."""
    
    def __init__(self, profile_name: Optional[str] = None, region: str = "us-west-2"):
        self.profile_name = profile_name
        self.region = region
        self.session = boto3.Session(profile_name=profile_name, region_name=region)
        
    def get_ecr_client(self):
        """Get ECR client."""
        return self.session.client('ecr')
    
    def get_codebuild_client(self):
        """Get CodeBuild client."""
        return self.session.client('codebuild')
    
    def get_s3_client(self):
        """Get S3 client."""
        return self.session.client('s3')
    
    def get_sts_client(self):
        """Get STS client for account info."""
        return self.session.client('sts')
    
    def get_account_id(self) -> str:
        """Get current AWS account ID."""
        sts = self.get_sts_client()
        return sts.get_caller_identity()['Account']
    
    def get_caller_identity(self) -> Dict:
        """Get caller identity info."""
        sts = self.get_sts_client()
        return sts.get_caller_identity()


def get_aws_profiles() -> List[str]:
    """Get list of available AWS profiles."""
    try:
        session = boto3.Session()
        return session.available_profiles
    except Exception:
        return []


def validate_aws_credentials(profile_name: Optional[str] = None) -> bool:
    """Validate AWS credentials are working."""
    try:
        session = boto3.Session(profile_name=profile_name)
        sts = session.client('sts')
        sts.get_caller_identity()
        return True
    except Exception:
        return False


def get_ecr_login_token(region: str = "us-west-2", profile_name: Optional[str] = None) -> str:
    """Get ECR login token."""
    session = boto3.Session(profile_name=profile_name, region_name=region)
    ecr = session.client('ecr')
    response = ecr.get_authorization_token()
    return response['authorizationData'][0]['authorizationToken']


def docker_login_ecr(registry_id: str, region: str = "us-west-2", profile_name: Optional[str] = None) -> bool:
    """Login Docker to ECR."""
    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        ecr = session.client('ecr')
        
        # Get login token
        token = ecr.get_authorization_token(registryIds=[registry_id])
        auth_data = token['authorizationData'][0]
        
        # Decode and login
        import base64
        decoded = base64.b64decode(auth_data['authorizationToken']).decode('utf-8')
        username, password = decoded.split(':')
        registry_url = auth_data['proxyEndpoint'].replace('https://', '')
        
        # Docker login
        cmd = [
            'docker', 'login',
            '--username', username,
            '--password-stdin',
            registry_url
        ]
        
        result = subprocess.run(
            cmd,
            input=password,
            capture_output=True,
            text=True
        )
        
        return result.returncode == 0
        
    except Exception as e:
        print(f"❌ ECR login failed: {e}")
        return False


def discover_ecr_repositories(region: str = "us-west-2", profile_name: Optional[str] = None) -> List[Dict]:
    """Discover ECR repositories in region."""
    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        ecr = session.client('ecr')
        
        response = ecr.describe_repositories()
        return response.get('repositories', [])
        
    except ClientError as e:
        print(f"❌ Failed to list ECR repositories: {e}")
        return []


def get_ecr_repository_uri(repository_name: str, region: str = "us-west-2", 
                          profile_name: Optional[str] = None) -> Optional[str]:
    """Get full URI for ECR repository."""
    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        ecr = session.client('ecr')
        
        response = ecr.describe_repositories(repositoryNames=[repository_name])
        repo = response['repositories'][0]
        return repo['repositoryUri']
        
    except ClientError:
        return None


def create_ecr_repository(repository_name: str, region: str = "us-west-2",
                         profile_name: Optional[str] = None) -> bool:
    """Create ECR repository if it doesn't exist."""
    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        ecr = session.client('ecr')
        
        ecr.create_repository(repositoryName=repository_name)
        print(f"✅ Created ECR repository: {repository_name}")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'RepositoryAlreadyExistsException':
            print(f"ℹ️  Repository already exists: {repository_name}")
            return True
        else:
            print(f"❌ Failed to create repository: {e}")
            return False


def check_s3_bucket_exists(bucket_name: str, profile_name: Optional[str] = None) -> bool:
    """Check if S3 bucket exists."""
    try:
        session = boto3.Session(profile_name=profile_name)
        s3 = session.client('s3')
        s3.head_bucket(Bucket=bucket_name)
        return True
    except ClientError:
        return False


def create_s3_bucket(bucket_name: str, region: str = "us-west-2", 
                    profile_name: Optional[str] = None) -> bool:
    """Create S3 bucket for build artifacts."""
    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        s3 = session.client('s3')
        
        if region == "us-east-1":
            s3.create_bucket(Bucket=bucket_name)
        else:
            s3.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={'LocationConstraint': region}
            )
        
        # Enable versioning
        s3.put_bucket_versioning(
            Bucket=bucket_name,
            VersioningConfiguration={'Status': 'Enabled'}
        )
        
        print(f"✅ Created S3 bucket: {bucket_name}")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'BucketAlreadyOwnedByYou':
            print(f"ℹ️  Bucket already exists: {bucket_name}")
            return True
        else:
            print(f"❌ Failed to create bucket: {e}")
            return False


def get_codebuild_project_status(project_name: str, region: str = "us-west-2",
                                 profile_name: Optional[str] = None) -> Optional[Dict]:
    """Get CodeBuild project status."""
    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        codebuild = session.client('codebuild')
        
        response = codebuild.batch_get_projects(names=[project_name])
        projects = response.get('projects', [])
        
        if projects:
            return projects[0]
        return None
        
    except ClientError:
        return None
