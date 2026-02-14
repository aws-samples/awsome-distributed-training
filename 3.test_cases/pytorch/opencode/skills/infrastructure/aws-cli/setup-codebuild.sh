#!/bin/bash
#
# AWS CodeBuild Setup Script for PyTorch FSDP
# 
# This script sets up a complete CodeBuild infrastructure for building,
# testing, and pushing Docker images to ECR.
#
# Usage: ./setup-codebuild.sh [options]
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PROJECT_NAME="pytorch-fsdp"
REPOSITORY_NAME="fsdp"
REGION="us-west-2"
AWS_PROFILE=""
GITHUB_REPO=""
GITHUB_BRANCH="main"
ENABLE_WEBHOOK="true"
BUILD_TIMEOUT="60"
COMPUTE_TYPE="BUILD_GENERAL1_MEDIUM"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --repository-name)
      REPOSITORY_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --profile)
      AWS_PROFILE="--profile $2"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --github-branch)
      GITHUB_BRANCH="$2"
      shift 2
      ;;
    --no-webhook)
      ENABLE_WEBHOOK="false"
      shift
      ;;
    --timeout)
      BUILD_TIMEOUT="$2"
      shift 2
      ;;
    --compute-type)
      COMPUTE_TYPE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --project-name NAME       CodeBuild project name (default: pytorch-fsdp)"
      echo "  --repository-name NAME    ECR repository name (default: fsdp)"
      echo "  --region REGION          AWS region (default: us-west-2)"
      echo "  --profile PROFILE        AWS profile name"
      echo "  --github-repo URL        GitHub repository URL"
      echo "  --github-branch BRANCH   GitHub branch (default: main)"
      echo "  --no-webhook            Disable webhook trigger"
      echo "  --timeout MINUTES       Build timeout (default: 60)"
      echo "  --compute-type TYPE     Compute type (default: BUILD_GENERAL1_MEDIUM)"
      echo "  --help                  Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."
  
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed"
    exit 1
  fi
  
  # Check AWS credentials
  if ! aws sts get-caller-identity $AWS_PROFILE &> /dev/null; then
    log_error "AWS credentials not configured"
    exit 1
  fi
  
  ACCOUNT_ID=$(aws sts get-caller-identity $AWS_PROFILE --query Account --output text)
  log_success "AWS credentials valid (Account: $ACCOUNT_ID)"
}

# Create IAM Role
create_iam_role() {
  local role_name="${PROJECT_NAME}-codebuild-role"
  
  log_info "Creating IAM role: $role_name"
  
  # Check if role exists
  if aws iam get-role --role-name "$role_name" $AWS_PROFILE &> /dev/null; then
    log_warning "Role already exists: $role_name"
    return 0
  fi
  
  # Create trust policy
  trust_policy=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
  
  # Create role
  aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document "$trust_policy" \
    $AWS_PROFILE
  
  # Create inline policy
  policy_document=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::${PROJECT_NAME}-build-artifacts-*/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${PROJECT_NAME}/*"
    }
  ]
}
EOF
)
  
  # Attach policy to role
  aws iam put-role-policy \
    --role-name "$role_name" \
    --policy-name "${PROJECT_NAME}-codebuild-policy" \
    --policy-document "$policy_document" \
    $AWS_PROFILE
  
  log_success "Created IAM role: $role_name"
}

# Create S3 Bucket for Artifacts
create_s3_bucket() {
  local bucket_name="${PROJECT_NAME}-build-artifacts-${ACCOUNT_ID}"
  
  log_info "Creating S3 bucket: $bucket_name"
  
  # Check if bucket exists
  if aws s3api head-bucket --bucket "$bucket_name" $AWS_PROFILE 2>/dev/null; then
    log_warning "Bucket already exists: $bucket_name"
    return 0
  fi
  
  # Create bucket
  if [ "$REGION" == "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$bucket_name" \
      $AWS_PROFILE
  else
    aws s3api create-bucket \
      --bucket "$bucket_name" \
      --create-bucket-configuration LocationConstraint="$REGION" \
      $AWS_PROFILE
  fi
  
  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "$bucket_name" \
    --versioning-configuration Status=Enabled \
    $AWS_PROFILE
  
  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "$bucket_name" \
    --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }' \
    $AWS_PROFILE
  
  log_success "Created S3 bucket: $bucket_name"
}

# Create ECR Repository
create_ecr_repository() {
  log_info "Creating ECR repository: $REPOSITORY_NAME"
  
  # Check if repository exists
  if aws ecr describe-repositories \
    --repository-names "$REPOSITORY_NAME" \
    --region "$REGION" \
    $AWS_PROFILE &> /dev/null; then
    log_warning "Repository already exists: $REPOSITORY_NAME"
    return 0
  fi
  
  # Create repository
  aws ecr create-repository \
    --repository-name "$REPOSITORY_NAME" \
    --region "$REGION" \
    $AWS_PROFILE
  
  log_success "Created ECR repository: $REPOSITORY_NAME"
}

# Create CloudWatch Log Group
create_log_group() {
  local log_group="/aws/codebuild/${PROJECT_NAME}"
  
  log_info "Creating CloudWatch log group: $log_group"
  
  # Check if log group exists
  if aws logs describe-log-groups \
    --log-group-name-prefix "$log_group" \
    --region "$REGION" \
    $AWS_PROFILE | grep -q "$log_group"; then
    log_warning "Log group already exists: $log_group"
    return 0
  fi
  
  # Create log group
  aws logs create-log-group \
    --log-group-name "$log_group" \
    --region "$REGION" \
    $AWS_PROFILE
  
  # Set retention
  aws logs put-retention-policy \
    --log-group-name "$log_group" \
    --retention-in-days 30 \
    --region "$REGION" \
    $AWS_PROFILE
  
  log_success "Created CloudWatch log group: $log_group"
}

# Create CodeBuild Project
create_codebuild_project() {
  log_info "Creating CodeBuild project: $PROJECT_NAME"
  
  # Check if project exists
  if aws codebuild batch-get-projects \
    --names "$PROJECT_NAME" \
    --region "$REGION" \
    $AWS_PROFILE | grep -q '"name": "'$PROJECT_NAME'"'; then
    log_warning "Project already exists: $PROJECT_NAME"
    return 0
  fi
  
  # Get role ARN
  role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-codebuild-role"
  
  # Create project
  aws codebuild create-project \
    --name "$PROJECT_NAME" \
    --description "Build, test, and push PyTorch FSDP Docker images" \
    --source "{
      \"type\": \"GITHUB\",
      \"location\": \"$GITHUB_REPO\",
      \"buildspec\": \"buildspec.yml\",
      \"gitCloneDepth\": 1,
      \"reportBuildStatus\": true
    }" \
    --artifacts "{
      \"type\": \"S3\",
      \"location\": \"${PROJECT_NAME}-build-artifacts-${ACCOUNT_ID}\",
      \"path\": \"/build-output\",
      \"namespaceType\": \"BUILD_ID\",
      \"name\": \"artifacts\",
      \"packaging\": \"NONE\"
    }" \
    --environment "{
      \"type\": \"LINUX_CONTAINER\",
      \"image\": \"aws/codebuild/standard:7.0\",
      \"computeType\": \"$COMPUTE_TYPE\",
      \"privilegedMode\": true,
      \"environmentVariables\": [
        {
          \"name\": \"AWS_DEFAULT_REGION\",
          \"value\": \"$REGION\"
        },
        {
          \"name\": \"ECR_REPOSITORY\",
          \"value\": \"$REPOSITORY_NAME\"
        }
      ]
    }" \
    --service-role "$role_arn" \
    --timeout-in-minutes "$BUILD_TIMEOUT" \
    --logs-config "{
      \"cloudWatchLogs\": {
        \"status\": \"ENABLED\",
        \"groupName\": \"/aws/codebuild/${PROJECT_NAME}\"
      }
    }" \
    --region "$REGION" \
    $AWS_PROFILE
  
  log_success "Created CodeBuild project: $PROJECT_NAME"
}

# Create Webhook for GitHub integration
create_webhook() {
  if [ "$ENABLE_WEBHOOK" != "true" ]; then
    log_info "Webhook creation skipped"
    return 0
  fi
  
  if [ -z "$GITHUB_REPO" ]; then
    log_warning "No GitHub repo specified, skipping webhook"
    return 0
  fi
  
  log_info "Creating webhook for GitHub integration"
  
  # Create webhook
  aws codebuild create-webhook \
    --project-name "$PROJECT_NAME" \
    --filter-groups "[[
      {
        \"type\": \"EVENT\",
        \"pattern\": \"PULL_REQUEST_CREATED,PULL_REQUEST_UPDATED\"
      },
      {
        \"type\": \"BASE_REF\",
        \"pattern\": \"^refs/heads/${GITHUB_BRANCH}$\"
      }
    ]]" \
    --region "$REGION" \
    $AWS_PROFILE
  
  log_success "Created webhook for GitHub integration"
}

# Create scheduled build (nightly)
create_scheduled_build() {
  log_info "Creating scheduled nightly build"
  
  rule_name="${PROJECT_NAME}-nightly-build"
  
  # Create EventBridge rule
  aws events put-rule \
    --name "$rule_name" \
    --schedule-expression "cron(0 2 * * ? *)" \
    --region "$REGION" \
    $AWS_PROFILE
  
  # Add target
  aws events put-targets \
    --rule "$rule_name" \
    --targets "[
      {
        \"Id\": \"1\",
        \"Arn\": \"arn:aws:codebuild:${REGION}:${ACCOUNT_ID}:project/${PROJECT_NAME}\",
        \"RoleArn\": \"arn:aws:iam::${ACCOUNT_ID}:role/${PROJECT_NAME}-codebuild-role\"
      }
    ]" \
    --region "$REGION" \
    $AWS_PROFILE
  
  log_success "Created scheduled nightly build (2 AM UTC)"
}

# Print summary
print_summary() {
  echo ""
  echo "============================================================"
  echo "SETUP COMPLETE"
  echo "============================================================"
  echo ""
  echo "Project Name: $PROJECT_NAME"
  echo "ECR Repository: $REPOSITORY_NAME"
  echo "Region: $REGION"
  echo "Account ID: $ACCOUNT_ID"
  echo ""
  echo "Resources Created:"
  echo "  ✅ IAM Role: ${PROJECT_NAME}-codebuild-role"
  echo "  ✅ S3 Bucket: ${PROJECT_NAME}-build-artifacts-${ACCOUNT_ID}"
  echo "  ✅ ECR Repository: $REPOSITORY_NAME"
  echo "  ✅ CloudWatch Log Group: /aws/codebuild/${PROJECT_NAME}"
  echo "  ✅ CodeBuild Project: $PROJECT_NAME"
  
  if [ "$ENABLE_WEBHOOK" == "true" ] && [ -n "$GITHUB_REPO" ]; then
    echo "  ✅ GitHub Webhook: Enabled"
  fi
  
  echo "  ✅ Scheduled Build: Nightly at 2 AM UTC"
  echo ""
  echo "Next Steps:"
  echo "  1. Ensure buildspec.yml is in your repository root"
  echo "  2. Push to GitHub to trigger first build"
  echo "  3. Monitor builds in AWS Console:"
  echo "     https://${REGION}.console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT_NAME}"
  echo ""
  echo "To trigger a manual build:"
  echo "  aws codebuild start-build --project-name $PROJECT_NAME --region $REGION $AWS_PROFILE"
  echo ""
  echo "============================================================"
}

# Main execution
main() {
  echo "============================================================"
  echo "AWS CodeBuild Setup for PyTorch FSDP"
  echo "============================================================"
  echo ""
  
  check_prerequisites
  create_iam_role
  create_s3_bucket
  create_ecr_repository
  create_log_group
  create_codebuild_project
  create_webhook
  create_scheduled_build
  print_summary
}

# Run main
main
