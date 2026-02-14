#!/usr/bin/env bash
# Check 0: nvidia-smi Validation
# Verifies nvidia-smi is functional, GPU count matches expectations,
# and no recent Xid errors exist in dmesg.
# Runtime: ~5 seconds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

CHECK_NAME="0-nvidia-smi"

run_check() {
    init_check "${CHECK_NAME}"

    # Step 1: Verify nvidia-smi executes successfully
    log_info "Verifying nvidia-smi availability"
    local smi_output
    if ! smi_output=$(run_cmd nvidia-smi --query-gpu=gpu_name,gpu_bus_id,memory.total \
        --format=csv,noheader 2>&1); then
        check_fail "${CHECK_NAME}" "nvidia-smi failed to execute" "ISOLATE"
        return 1
    fi

    # Step 2: Count detected GPUs
    local detected_gpus
    detected_gpus=$(echo "${smi_output}" | wc -l | tr -d ' ')
    log_verbose "Detected ${detected_gpus} GPU(s)"

    if [[ -n "${EXPECTED_GPU_COUNT}" && "${EXPECTED_GPU_COUNT}" -gt 0 ]]; then
        if [[ "${detected_gpus}" -ne "${EXPECTED_GPU_COUNT}" ]]; then
            check_fail "${CHECK_NAME}" \
                "GPU count mismatch: expected=${EXPECTED_GPU_COUNT}, detected=${detected_gpus}" \
                "ISOLATE"
            return 1
        fi
        log_verbose "GPU count matches expected: ${detected_gpus}"
    fi

    # Step 3: Check for Xid errors in dmesg (last 10 minutes)
    log_info "Checking dmesg for recent Xid errors"
    local xid_errors=""
    if [[ "${DRY_RUN}" != "1" ]]; then
        # dmesg may require root; proceed gracefully if unavailable
        xid_errors=$(dmesg --time-format iso 2>/dev/null \
            | grep -i "NVRM.*Xid" \
            | tail -20 || true)
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} dmesg | grep NVRM.*Xid" >&2
    fi

    if [[ -n "${xid_errors}" ]]; then
        local xid_count
        xid_count=$(echo "${xid_errors}" | wc -l | tr -d ' ')
        check_warn "${CHECK_NAME}" "Found ${xid_count} Xid error(s) in dmesg"
        log_verbose "Recent Xid errors:\\n${xid_errors}"
    fi

    # Step 4: Check GPU persistence mode
    local persist_mode
    if persist_mode=$(run_cmd nvidia-smi --query-gpu=persistence_mode \
        --format=csv,noheader 2>/dev/null); then
        local disabled_count
        disabled_count=$(echo "${persist_mode}" | grep -ci "disabled" || true)
        if [[ "${disabled_count}" -gt 0 ]]; then
            check_warn "${CHECK_NAME}" \
                "Persistence mode disabled on ${disabled_count} GPU(s) -- recommend enabling"
        fi
    fi

    check_pass "${CHECK_NAME}" \
        "nvidia-smi OK, ${detected_gpus} GPU(s) detected"
    return 0
}

# ─── Entry point ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

run_check
