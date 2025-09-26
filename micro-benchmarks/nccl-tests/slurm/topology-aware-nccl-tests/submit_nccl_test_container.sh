#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Script to submit comprehensive NCCL tests with 2 and 4 nodes
# Tests all collective operations with different split masks

set -e

# Configuration
NODE_COUNTS=(2 4 8 16)
APPS_PATH="${APPS_PATH:-/fsxl}"
TEST_TYPES=("allreduce" "allgather" "reducescatter" "alltoall")
# TEST_TYPES=("allreduce" )
SPLIT_MASK=("0x0" "0x7")
# SPLIT_MASK=("0x0")
ENABLE_NCCL_DEBUG="false"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting comprehensive NCCL test submission...${NC}"
echo -e "${BLUE}Configuration:${NC}"
echo "  Node counts: ${NODE_COUNTS[*]}"
echo "  Apps path: $APPS_PATH"
echo "  Test types: ${TEST_TYPES[*]}"
echo "  split masks: ${SPLIT_MASK[*]}"
echo "  NCCL Debug: $ENABLE_NCCL_DEBUG"
echo ""

# Counter for submitted jobs
job_count=0
submitted_jobs=()

# Create job tracking files
timestamp=$(date +"%Y%m%d_%H%M%S")
job_ids_file="logs/submitted_jobs_${timestamp}.txt"
job_details_file="logs/job_details_${timestamp}.csv"

# Initialize CSV file with headers
echo "JobID,Nodes,TestType,SplitMask,TotalGPUs,SubmissionTime" > "$job_details_file"

# Submit all test combinations
for nodes in "${NODE_COUNTS[@]}"; do
    total_gpus=$((nodes * 8))
    
    echo -e "${YELLOW}=== Submitting tests for $nodes nodes ($total_gpus GPUs) ===${NC}"
    
    for test_type in "${TEST_TYPES[@]}"; do
        for split_mask in "${SPLIT_MASK[@]}"; do
            echo "Submitting: $test_type with pattern $split_mask on $nodes nodes"
            
            # Submit the job and capture job ID
            job_output=$(sbatch --nodes=$nodes nccl-tests-container.sbatch "$test_type" "$APPS_PATH" "$split_mask" "$ENABLE_NCCL_DEBUG")
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