#!/bin/bash
#
# Quick wrapper script for Docker image builder
# Auto-detects local Docker or falls back to CodeBuild
#
# Usage: ./build.sh [options]
#

set -e

# Default values
PROJECT_NAME="pytorch-fsdp"
REGION="us-west-2"
CONTEXT="."
WAIT="true"
MODE=""

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
    --force-local)
      MODE="--force-local"
      shift
      ;;
    --force-codebuild)
      MODE="--force-codebuild"
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Build Docker images with auto-detection:"
      echo "  - If Docker is available locally, builds locally"
      echo "  - If Docker is NOT available, falls back to AWS CodeBuild"
      echo ""
      echo "Options:"
      echo "  --project NAME      CodeBuild project name (default: pytorch-fsdp)"
      echo "  --region REGION     AWS region (default: us-west-2)"
      echo "  --context PATH      Build context path (default: .)"
      echo "  --no-wait           Don't wait for CodeBuild completion"
      echo "  --force-local       Force local Docker build"
      echo "  --force-codebuild   Force CodeBuild build"
      echo "  --help              Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Auto-detect"
      echo "  $0 --force-local --context ./FSDP     # Local Docker"
      echo "  $0 --force-codebuild --no-wait        # Background CodeBuild"
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

# Build the command
CMD="python3 ${SCRIPT_DIR}/../src/build_image.py"
CMD="${CMD} --codebuild-project ${PROJECT_NAME}"
CMD="${CMD} --region ${REGION}"
CMD="${CMD} --context ${CONTEXT}"
CMD="${CMD} --verbose"

if [ -n "$MODE" ]; then
  CMD="${CMD} ${MODE}"
fi

if [ "$WAIT" = "false" ]; then
  CMD="${CMD} --no-wait"
fi

# Run
exec $CMD
