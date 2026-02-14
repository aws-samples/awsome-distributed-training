#!/bin/bash
#
# Quick wrapper script for CodeBuild Docker image builder
# Usage: ./build-with-codebuild.sh [options]
#

set -e

# Default values
PROJECT_NAME="pytorch-fsdp"
REGION="us-west-2"
CONTEXT="."
WAIT="true"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --no-wait)
      WAIT="false"
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --project NAME      CodeBuild project name (default: pytorch-fsdp)"
      echo "  --region REGION     AWS region (default: us-west-2)"
      echo "  --context PATH      Build context path (default: .)"
      echo "  --no-wait           Don't wait for build completion"
      echo "  --help              Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Use defaults"
      echo "  $0 --project my-project               # Custom project"
      echo "  $0 --no-wait                          # Background build"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Run the Python builder
python3 "${SCRIPT_DIR}/../src/build_image_codebuild.py" \
  --codebuild-project "${PROJECT_NAME}" \
  --region "${REGION}" \
  --context "${CONTEXT}" \
  --verbose \
  $(if [ "$WAIT" = "true" ]; then echo "--wait"; fi)
