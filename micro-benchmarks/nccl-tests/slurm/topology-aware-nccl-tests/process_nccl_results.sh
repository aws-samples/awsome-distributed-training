#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Script to convert nccl test outputs to Excel after they complete
# Usage: ./process_nccl_results.sh <submitted_jobs_file.txt>
# Example: ./process_nccl_results.sh submitted_jobs_20250905_052718.txt

set -e

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <submitted_jobs_file.txt>"
    echo "Example: $0 submitted_jobs_20250905_052718.txt"
    echo ""
    echo "Available job files:"
    ls -1 submitted_jobs_*.txt 2>/dev/null || echo "  No submitted_jobs_*.txt files found"
    exit 1
fi

JOBS_FILE="$1"

# Validate input file
if [[ ! -f "$JOBS_FILE" ]]; then
    echo "Error: Job file '$JOBS_FILE' not found"
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
RESULTS_DIR="nccl_results"
CSV_CONVERTER="../../nccl_to_csv.py"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create results directory if it doesn't exist
mkdir -p "$RESULTS_DIR"

# Read job IDs from file
mapfile -t JOB_IDS < "$JOBS_FILE"

echo -e "${GREEN}NCCL Results Processor${NC}"
echo -e "${BLUE}Processing jobs from: $JOBS_FILE${NC}"
echo -e "${BLUE}Job IDs to monitor: ${JOB_IDS[*]}${NC}"
echo ""

# Function to extract job parameters from output file content only
parse_job_details() {
    local output_file=$1
    local nodes test_type data_pattern topo_suffix run_type
    
    if [[ ! -f "$output_file" ]]; then
        echo "unknown_unknown_unknown_unknown"
        return
    fi
    
    # Determine run type (AMI or container) from filename or output content
    if [[ "$output_file" == *"ami"* ]]; then
        run_type="ami"
    elif [[ "$output_file" == *"container"* ]]; then
        run_type="container"
    elif grep -q "Running NCCL.*test in ami" "$output_file"; then
        run_type="ami"
    elif grep -q "Running NCCL.*test in container" "$output_file"; then
        run_type="container"
    else
        run_type="unknown"
    fi
    
    # Extract test type from output - handles both AMI and container formats
    if grep -q "Running NCCL.*test" "$output_file"; then
        # Handle both "Running NCCL allreduce test in ami" and "Running NCCL allreduce test in container"
        test_type=$(grep "Running NCCL.*test" "$output_file" | sed -n 's/.*Running NCCL \([a-z]*\) test.*/\1/p' | head -1)
    fi
    
    # Extract split mask from output - handles both AMI and container formats
    if grep -q "split mask" "$output_file"; then
        data_pattern=$(grep "split mask" "$output_file" | sed -n 's/.*split mask \(0x[0-9a-fA-F]*\).*/\1/p' | head -1)
    fi
    
    # Count unique hostnames to determine nodes
    # Extract hostnames from SLURM output - look for patterns like "hostname: " or "Running on hostname"
    if grep -q "hostname=" "$output_file"; then
        # Extract hostnames from the hostname= pattern added to sbatch files
        nodes=$(grep -oE "hostname=[a-zA-Z0-9.-]+" "$output_file" | \
                sed 's/hostname=//' | \
                sort -u | wc -l)
    fi
    
    # Check if topology sorting was used
    if grep -q "Created sequential hostfile with repeated hostnames" "$output_file"; then
        topo_suffix="_topo"
    else
        topo_suffix=""
    fi
    
    echo "${nodes:-unknown}_${run_type}_${test_type:-unknown}_${data_pattern:-unknown}${topo_suffix}"
}

# Function to convert output to CSV
convert_to_csv() {
    local output_file=$1
    local job_details=$2
    
    echo -e "${YELLOW}Converting $output_file to CSV...${NC}"
    
    # Check if converter exists
    if [[ ! -f "$CSV_CONVERTER" ]]; then
        echo -e "${RED}Error: CSV converter not found at $CSV_CONVERTER${NC}"
        return 1
    fi
    
    # Run converter
    if python3 "$CSV_CONVERTER" "$output_file"; then
        # Move generated files to results directory with descriptive names
        local base_name=$(basename "$output_file" .out)
        local moved_files=0
        
        # Handle results CSV file
        if [[ -f "${base_name}_results.csv" ]]; then
            mv "${base_name}_results.csv" "$RESULTS_DIR/nccl_${job_details}_${TIMESTAMP}_results.csv"
            echo -e "${GREEN}  → Results: $RESULTS_DIR/nccl_${job_details}_${TIMESTAMP}_results.csv${NC}"
            moved_files=$((moved_files + 1))
        fi
        

        
        # Clean up any remaining summary CSV files that match the pattern
        for leftover_file in "${base_name}"*summary*.csv "${base_name}"*_summary.csv; do
            if [[ -f "$leftover_file" ]]; then
                echo -e "${YELLOW}  → Cleaning up leftover summary file: $leftover_file${NC}"
                rm -f "$leftover_file"
            fi
        done
        
        if [[ $moved_files -gt 0 ]]; then
            return 0
        else
            echo -e "${RED}  → No CSV files were generated or found${NC}"
            return 1
        fi
    else
        echo -e "${RED}  → Conversion failed${NC}"
        return 1
    fi
}

# Function to check if output file has performance data
has_performance_data() {
    local output_file=$1
    
    if [[ ! -f "$output_file" ]]; then
        return 1
    fi
    
    # Check for NCCL performance table
    if grep -q "out-of-place.*in-place" "$output_file" && \
       grep -q "size.*count.*type.*redop" "$output_file" && \
       grep -q "Avg bus bandwidth" "$output_file"; then
        return 0
    fi
    
    return 1
}

# Removed job status checking - assuming all jobs are complete

# Function to get expected output filename for job ID
get_output_filename() {
    local job_id=$1
    
    # Check for both AMI and container output file patterns in logs/ directory first
    if [[ -f "logs/nccl-tests-ami_${job_id}.out" ]]; then
        echo "logs/nccl-tests-ami_${job_id}.out"
    elif [[ -f "logs/nccl-tests-container_${job_id}.out" ]]; then
        echo "logs/nccl-tests-container_${job_id}.out"
    elif [[ -f "nccl-tests-ami_${job_id}.out" ]]; then
        echo "nccl-tests-ami_${job_id}.out"
    elif [[ -f "nccl-tests-container_${job_id}.out" ]]; then
        echo "nccl-tests-container_${job_id}.out"
    else
        # Default to logs/container pattern for backwards compatibility
        echo "logs/nccl-tests-container_${job_id}.out"
    fi
}

# Main monitoring loop
processed_files=()
completed_jobs=()
failed_jobs=()

echo -e "${BLUE}Processing ${#JOB_IDS[@]} completed jobs...${NC}"
echo -e "${BLUE}Timestamp for this run: ${TIMESTAMP}${NC}"
echo ""

# Process all jobs assuming they are complete
for job_id in "${JOB_IDS[@]}"; do
    output_file=$(get_output_filename "$job_id")
    
    echo -e "${YELLOW}Processing job $job_id...${NC}"
    
    if [[ -f "$output_file" ]] && has_performance_data "$output_file"; then
        job_details=$(parse_job_details "$output_file")
        echo -e "${BLUE}  → Job details: $job_details${NC}"
        
        if convert_to_csv "$output_file" "$job_details"; then
            processed_files+=("$output_file")
            completed_jobs+=("$job_id")
            echo -e "${GREEN}  → Successfully processed job $job_id${NC}"
        else
            failed_jobs+=("$job_id")
            echo -e "${RED}  → Processing failed for job $job_id${NC}"
        fi
    else
        echo -e "${YELLOW}  → Output file missing or incomplete for job $job_id${NC}"
        failed_jobs+=("$job_id")
    fi
    echo ""
done

echo ""
echo -e "${GREEN}Processing complete!${NC}"
echo -e "${BLUE}Results saved in: $RESULTS_DIR/${NC}"

echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  Successfully processed: ${#completed_jobs[@]} jobs"
echo "  Failed/Missing: ${#failed_jobs[@]} jobs"
echo "  Total jobs: ${#JOB_IDS[@]}"

if [[ ${#completed_jobs[@]} -gt 0 ]]; then
    echo ""
    echo -e "${GREEN}Successfully processed jobs:${NC}"
    for job_id in "${completed_jobs[@]}"; do
        echo "  - Job $job_id"
    done
fi

if [[ ${#failed_jobs[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed/Missing jobs:${NC}"
    for job_id in "${failed_jobs[@]}"; do
        echo "  - Job $job_id"
    done
fi

if [[ ${#processed_files[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BLUE}Generated CSV files:${NC}"
    ls -la "$RESULTS_DIR"/*.csv 2>/dev/null || echo "No CSV files found"
else
    echo -e "${YELLOW}No CSV files were generated${NC}"
fi

# Final cleanup: remove any remaining CSV files in current directory
echo ""
echo -e "${YELLOW}Performing final cleanup...${NC}"
cleanup_count=0
for leftover_file in nccl-tests-*_*.csv; do
    if [[ -f "$leftover_file" ]]; then
        echo -e "${YELLOW}  → Removing leftover file: $leftover_file${NC}"
        rm -f "$leftover_file"
        cleanup_count=$((cleanup_count + 1))
    fi
done

if [[ $cleanup_count -gt 0 ]]; then
    echo -e "${GREEN}Cleaned up $cleanup_count leftover CSV files${NC}"
else
    echo -e "${GREEN}No leftover files to clean up${NC}"
fi