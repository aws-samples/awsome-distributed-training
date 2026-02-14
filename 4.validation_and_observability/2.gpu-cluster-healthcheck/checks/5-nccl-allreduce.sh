#!/usr/bin/env bash
# Check 5: Multi-Node NCCL all_reduce Performance Test
# Runs all_reduce_perf from the NCCL tests container across allocated nodes.
# Validates bus bandwidth and verifies EFA provider selection.
# Runtime: ~10-20 minutes
# Requires: minimum 2 nodes, Pyxis/Enroot or standalone MPI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

CHECK_NAME="5-nccl-allreduce"
NCCL_CONTAINER="${NCCL_CONTAINER:-public.ecr.aws/hpc-cloud/nccl-tests:latest}"
NCCL_TIMEOUT="${NCCL_TIMEOUT:-1800}"  # 30-minute timeout

# Minimum expected bus bandwidth (GB/s) per instance type.
# These are conservative defaults; override with NCCL_MIN_BUS_BW env var
# if you have a well-characterized baseline for your cluster.
get_min_bus_bw() {
    # Environment override takes precedence over per-instance defaults
    if [[ -n "${NCCL_MIN_BUS_BW:-}" ]]; then
        echo "${NCCL_MIN_BUS_BW}"
        return
    fi
    case "$1" in
        p4d.24xlarge)    echo 300 ;;
        p5.48xlarge)     echo 800 ;;
        p5e.48xlarge)    echo 800 ;;
        p5en.48xlarge)   echo 800 ;;
        p6-b200.48xlarge) echo 900 ;;
        *)               echo 0 ;;
    esac
}

run_check() {
    init_check "${CHECK_NAME}"

    # Determine number of nodes
    local num_nodes=1
    if [[ -n "${SLURM_JOB_NUM_NODES:-}" ]]; then
        num_nodes="${SLURM_JOB_NUM_NODES}"
    elif [[ -n "${SLURM_NNODES:-}" ]]; then
        num_nodes="${SLURM_NNODES}"
    fi

    if [[ "${num_nodes}" -lt 2 ]]; then
        check_skip "${CHECK_NAME}" \
            "NCCL all_reduce requires minimum 2 nodes (allocated: ${num_nodes})"
        return 0
    fi

    local gpus_per_node="${EXPECTED_GPU_COUNT:-8}"

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} srun --ntasks-per-node=1 --container-image=${NCCL_CONTAINER} \\" >&2
        echo -e "${YELLOW}[DRY-RUN]${NC}   all_reduce_perf -b 8 -e 128M -f 2 -g ${gpus_per_node}" >&2
        check_pass "${CHECK_NAME}" "Dry-run: NCCL all_reduce skipped"
        return 0
    fi

    # Set NCCL/EFA environment variables
    export FI_PROVIDER="${EFA_PROVIDER:-efa}"
    export FI_EFA_USE_DEVICE_RDMA=1
    export NCCL_NET_GDR_LEVEL=2
    export NCCL_DEBUG=INFO

    log_info "Running NCCL all_reduce_perf across ${num_nodes} nodes (${gpus_per_node} GPUs/node)"

    local nccl_output
    local nccl_exit=0

    # Try Pyxis/Enroot first, fall back to direct execution
    if srun --help 2>&1 | grep -q "container-image"; then
        log_info "Using Pyxis/Enroot container runtime"
        nccl_output=$(run_with_timeout "${NCCL_TIMEOUT}" \
            srun --ntasks-per-node=1 \
                 --container-image="${NCCL_CONTAINER}" \
                 all_reduce_perf -b 8 -e 128M -f 2 -g "${gpus_per_node}" \
            2>&1) || nccl_exit=$?
    elif command -v all_reduce_perf > /dev/null 2>&1; then
        log_info "Using locally installed NCCL tests"
        nccl_output=$(run_with_timeout "${NCCL_TIMEOUT}" \
            srun --ntasks-per-node=1 \
                 all_reduce_perf -b 8 -e 128M -f 2 -g "${gpus_per_node}" \
            2>&1) || nccl_exit=$?
    else
        check_fail "${CHECK_NAME}" \
            "Neither Pyxis container runtime nor local all_reduce_perf found" "RESET"
        return 1
    fi

    # Save raw output
    echo "${nccl_output}" > "${RESULTS_DIR}/nccl-allreduce-raw.txt"

    if [[ ${nccl_exit} -eq 124 ]]; then
        check_fail "${CHECK_NAME}" \
            "NCCL all_reduce timed out after ${NCCL_TIMEOUT}s" "RESET"
        return 1
    fi

    if [[ ${nccl_exit} -ne 0 ]]; then
        # Check for out-of-bound errors
        if echo "${nccl_output}" | grep -qi "out of bound\|NCCL WARN\|unhandled system error"; then
            check_fail "${CHECK_NAME}" \
                "NCCL all_reduce failed with errors (exit ${nccl_exit})" "ISOLATE"
        else
            check_fail "${CHECK_NAME}" \
                "NCCL all_reduce failed (exit ${nccl_exit})" "RESET"
        fi
        return 1
    fi

    # Verify EFA provider was selected
    if ! echo "${nccl_output}" | grep -qi "Selected Provider is efa\|Using network EFA"; then
        check_warn "${CHECK_NAME}" \
            "EFA provider not confirmed in NCCL output -- performance may be degraded"
    fi

    # Extract maximum bus bandwidth from results
    # Format: size  count  type  redop  root  time  algbw  busbw  ...
    local max_busbw
    max_busbw=$(echo "${nccl_output}" | grep -E "^\s+[0-9]" | awk '{print $NF}' \
        | sort -n | tail -1 || echo "0")

    log_info "Maximum bus bandwidth: ${max_busbw} GB/s"

    # Compare against minimum threshold
    local min_expected
    min_expected=$(get_min_bus_bw "${INSTANCE_TYPE}")
    if [[ "${min_expected}" -gt 0 ]]; then
        local busbw_int
        busbw_int=$(echo "${max_busbw}" | awk '{printf "%d", $1}')
        if [[ "${busbw_int}" -lt "${min_expected}" ]]; then
            # Bandwidth below threshold is advisory (MONITOR) unless the operator
            # has set NCCL_MIN_BUS_BW to a well-characterized baseline.
            check_warn "${CHECK_NAME}" \
                "Bus bandwidth ${max_busbw} GB/s below minimum ${min_expected} GB/s for ${INSTANCE_TYPE}"
        fi
    fi

    check_pass "${CHECK_NAME}" \
        "NCCL all_reduce OK: ${num_nodes} nodes, max busbw=${max_busbw} GB/s"
    return 0
}

# ─── Entry point ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

run_check
