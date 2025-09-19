#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Script to submit comprehensive NCCL tests with AMI-based jobs
# Tests all collective operations with different Split mask

set -e

# Create logs directory if it doesn't exist
mkdir -p logs

# Configuration
NODE_COUNTS=(2 4 8 16)
# NODE_COUNTS=(16)
ADDITIONAL_LD_LIBRARY_PATH="/usr/local/cuda-12.9/lib64:/opt/nccl/build/lib/:/opt/amazon/ofi-nccl/lib/x86_64-linux-gnu/"
TEST_TYPES=("allreduce" "allgather" "reducescatter" "alltoall")
# TEST_TYPES=("allreduce")
SPLIT_MASK=("0x0" "0x7")
# SPLIT_MASK=("0x0")
TOPO_SORTED_FILE="topo_sorted_hostnames.txt"
# TOPO_SORTED_FILE=""
ENABLE_NCCL_DEBUG="false"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting comprehensive NCCL test submission (AMI version)...${NC}"
echo -e "${BLUE}Configuration:${NC}"
echo "  Node counts: ${NODE_COUNTS[*]}"
echo "  LD Library path: $ADDITIONAL_LD_LIBRARY_PATH"
echo "  Test types: ${TEST_TYPES[*]}"
echo "  Split mask: ${SPLIT_MASK[*]}"
echo "  NCCL Debug: $ENABLE_NCCL_DEBUG"
echo ""

# Counter for submitted jobs
job_count=0
submitted_jobs=()

# Create job tracking files
timestamp=$(date +"%Y%m%d_%H%M%S")
job_ids_file="logs/submitted_jobs_ami_${timestamp}.txt"
job_details_file="logs/job_details_ami_${timestamp}.csv"

# Initialize CSV file with headers
echo "JobID,Nodes,TestType,SplitMask,TotalGPUs,SubmissionTime" > "$job_details_file"

# Submit all test combinations
for nodes in "${NODE_COUNTS[@]}"; do
    total_gpus=$((nodes * 8))
    
    echo -e "${YELLOW}=== Submitting AMI tests for $nodes nodes ($total_gpus GPUs) ===${NC}"
    
    for test_type in "${TEST_TYPES[@]}"; do
        for split_mask in "${SPLIT_MASK[@]}"; do
            echo "Submitting: $test_type with pattern $split_mask on $nodes nodes"
            
            # Submit the job and capture job ID
            job_output=$(sbatch --nodes=$nodes nccl-tests-ami.sbatch "$test_type" "$ADDITIONAL_LD_LIBRARY_PATH" "$split_mask" "$TOPO_SORTED_FILE" "$ENABLE_NCCL_DEBUG")
            job_id=$(echo "$job_output" | grep -o '[0-9]\+')
            
            if [ -n "$job_id" ]; then
                submitted_jobs+=("$job_id")
                job_count=$((job_count + 1))
                echo "  → Job ID: $job_id"
                
                # Save job ID to file
                echo "$job_id" >> "$job_ids_file"
                
                # Save job details to CSV
                submission_time=$(date +"%Y-%m-%d %H:%M:%S")
                echo "$job_id,$nodes,$test_type,$split_mask,$total_gpus,$submission_time" >> "$job_details_file"
                echo "tail -f logs/nccl-tests-ami_$job_id.out"
            else
                echo "  → Error: Failed to get job ID"
            fi
            
            # Small delay to avoid overwhelming the scheduler
            sleep 1
        done
    done
    echo ""
done

echo -e "${GREEN}Summary:${NC}"
echo "Total jobs submitted: $job_count"
echo "Job IDs: ${submitted_jobs[*]}"
echo ""

# Save summary information
echo -e "${BLUE}Job tracking files created:${NC}"
echo "  Job IDs: $job_ids_file"
echo "  Job details: $job_details_file"
echo ""

# Show queue status
echo -e "${YELLOW}Current queue status:${NC}"
squeue -u $USER

echo ""
echo -e "${GREEN}All jobs submitted successfully!${NC}"
echo -e "${BLUE}Monitor progress with: squeue -u $USER${NC}"
echo -e "${BLUE}Check job details with: scontrol show job <job_id>${NC}"
echo -e "${BLUE}Monitor specific jobs: squeue -j $(IFS=,; echo "${submitted_jobs[*]}")${NC}"
echo ""
echo -e "${YELLOW}To automatically process results as jobs complete, run:${NC}"
echo -e "${BLUE}./process_nccl_results.sh $job_ids_file${NC}"
echo ""
echo -e "${YELLOW}To cancel all submitted jobs if needed:${NC}"
echo -e "${BLUE}scancel $(IFS=' '; echo "${submitted_jobs[*]}")${NC}"
