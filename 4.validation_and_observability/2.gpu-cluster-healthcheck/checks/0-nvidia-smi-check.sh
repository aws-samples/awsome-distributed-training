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

    # Step 3: Check for Xid errors in dmesg with severity classification
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
        # Extract unique Xid codes from dmesg lines
        local xid_codes
        xid_codes=$(echo "${xid_errors}" | grep -oP 'Xid.*?:\s*\K[0-9]+' | sort -un || true)

        # Classify each Xid code by severity
        local highest_severity="MONITOR"
        local severity_details=""

        for code in ${xid_codes}; do
            local code_severity="MONITOR"
            local code_group="UNKNOWN"
            case "${code}" in
                64|79|81|125|154) code_severity="ISOLATE"; code_group="FATAL" ;;
                48|63|74|94|95|126) code_severity="RESET"; code_group="RECOVERABLE" ;;
                119|120|143) code_severity="RESET"; code_group="GSP_FIRMWARE" ;;
                13|31|43) code_severity="MONITOR"; code_group="APP_FAULT" ;;
                92) code_severity="MONITOR"; code_group="ECC_WARNING" ;;
                *) code_severity="MONITOR"; code_group="UNKNOWN" ;;
            esac

            if [[ -n "${severity_details}" ]]; then
                severity_details+=", "
            fi
            severity_details+="Xid ${code} (${code_severity}/${code_group})"

            # Track highest severity: ISOLATE > RESET > MONITOR
            if [[ "${code_severity}" == "ISOLATE" ]]; then
                highest_severity="ISOLATE"
            elif [[ "${code_severity}" == "RESET" && "${highest_severity}" != "ISOLATE" ]]; then
                highest_severity="RESET"
            fi
        done

        local xid_count
        xid_count=$(echo "${xid_errors}" | wc -l | tr -d ' ')

        if [[ "${highest_severity}" == "ISOLATE" || "${highest_severity}" == "RESET" ]]; then
            check_fail "${CHECK_NAME}" \
                "Found ${xid_count} Xid error(s): ${severity_details}" "${highest_severity}"
        else
            check_warn "${CHECK_NAME}" "Found ${xid_count} Xid error(s): ${severity_details}"
        fi
        log_verbose "Recent Xid errors:\\n${xid_errors}"
    fi

    # Step 4: Check for SXid (NVSwitch) errors in dmesg
    log_info "Checking dmesg for SXid (NVSwitch) errors"
    local sxid_errors=""
    if [[ "${DRY_RUN}" != "1" ]]; then
        sxid_errors=$(dmesg 2>/dev/null | grep -i "SXid" | tail -20 || true)
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} dmesg | grep -i SXid" >&2
    fi

    if [[ -n "${sxid_errors}" ]]; then
        local sxid_count
        sxid_count=$(echo "${sxid_errors}" | wc -l | tr -d ' ')
        local sxid_msg="Found ${sxid_count} SXid (NVSwitch) error(s) in dmesg"

        # SXid alongside Xid 74 suggests NVSwitch root cause
        if [[ -n "${xid_errors}" ]] && echo "${xid_errors}" | grep -qP 'Xid.*?:\s*74\b'; then
            sxid_msg+="; SXid with Xid 74 indicates likely NVSwitch root cause (recommend RESET)"
        fi

        check_warn "${CHECK_NAME}" "${sxid_msg}"
        log_verbose "Recent SXid errors:\\n${sxid_errors}"
    fi

    # Step 5: Check GPU persistence mode
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

    # Step 6: Capture GPU UUIDs (informational)
    log_info "Capturing GPU UUIDs"
    local uuid_output=""
    if uuid_output=$(run_cmd nvidia-smi --query-gpu=index,serial,uuid \
        --format=csv,noheader 2>/dev/null); then
        if [[ -n "${uuid_output}" ]]; then
            echo "${uuid_output}" > "${RESULTS_DIR}/gpu-uuids.csv"
            local uuid_count
            uuid_count=$(echo "${uuid_output}" | wc -l | tr -d ' ')
            log_info "Captured UUIDs for ${uuid_count} GPU(s)"
        fi
    else
        log_verbose "nvidia-smi UUID query failed -- skipping UUID capture"
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
