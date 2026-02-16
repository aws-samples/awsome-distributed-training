#!/usr/bin/env bash
# Check 6: EFA Loopback Bandwidth/Latency Test
# Iterates over all RDMA devices and runs per-device bandwidth and latency tests.
# Reports MaxBw, AvgBw, MaxLat, MinLat for each device.
# Runtime: ~5-15 minutes depending on EFA device count

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

CHECK_NAME="6-efa-loopback"
EFA_TEST_TIMEOUT="${EFA_TEST_TIMEOUT:-120}"  # Per-device timeout

# Minimum expected EFA bandwidth (Gbps) per device per instance type.
# Override with EFA_MIN_BW env var.
get_min_efa_bw() {
    if [[ -n "${EFA_MIN_BW:-}" ]]; then echo "${EFA_MIN_BW}"; return; fi
    case "$1" in
        p4d.24xlarge)      echo 20 ;;
        p5.48xlarge)       echo 20 ;;
        p5e.48xlarge)      echo 20 ;;
        p5en.48xlarge)     echo 20 ;;
        p6-b200.48xlarge)  echo 20 ;;
        *)                 echo 0 ;;
    esac
}

run_check() {
    init_check "${CHECK_NAME}"

    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} fi_pingpong -p efa -d <device> for each RDMA device" >&2
        check_pass "${CHECK_NAME}" "Dry-run: EFA loopback tests skipped"
        return 0
    fi

    # Discover RDMA devices
    if ! command -v ibv_devices > /dev/null 2>&1; then
        check_fail "${CHECK_NAME}" "ibv_devices not found -- RDMA tools not installed" "RESET"
        return 1
    fi

    local devices
    # ibv_devices has 2 header lines; skip them before parsing device names
    devices=$(ibv_devices 2>/dev/null | tail -n +3 | grep -oE "rdma[0-9]+" || \
              ibv_devices 2>/dev/null | tail -n +3 | grep -oE "efa_[0-9]+" || \
              ibv_devices 2>/dev/null | tail -n +3 | awk 'NF{print $1}' || true)

    if [[ -z "${devices}" ]]; then
        check_fail "${CHECK_NAME}" "No RDMA devices found" "ISOLATE"
        return 1
    fi

    local device_count
    device_count=$(echo "${devices}" | wc -l | tr -d ' ')
    log_info "Testing ${device_count} RDMA device(s)"

    local failures=0
    local degraded=0
    local min_efa_bw
    min_efa_bw=$(get_min_efa_bw "${INSTANCE_TYPE}")
    local results_json="["

    while IFS= read -r device; do
        [[ -z "${device}" ]] && continue
        log_info "Testing device: ${device}"

        local test_output=""
        local test_exit=0

        # Run fi_pingpong in loopback mode if available
        if command -v fi_pingpong > /dev/null 2>&1; then
            # Start server in background, then run client
            local server_pid
            fi_pingpong -p efa -d "${device}" -I 100 > /dev/null 2>&1 &
            server_pid=$!
            sleep 1

            test_output=$(timeout "${EFA_TEST_TIMEOUT}" \
                fi_pingpong -p efa -d "${device}" -I 100 localhost 2>&1) || test_exit=$?

            kill "${server_pid}" 2>/dev/null || true
            wait "${server_pid}" 2>/dev/null || true
        elif command -v ib_write_bw > /dev/null 2>&1; then
            # Fallback to ib_write_bw for bandwidth testing
            local server_pid
            ib_write_bw -d "${device}" --report_gbits > /dev/null 2>&1 &
            server_pid=$!
            sleep 1

            test_output=$(timeout "${EFA_TEST_TIMEOUT}" \
                ib_write_bw -d "${device}" --report_gbits localhost 2>&1) || test_exit=$?

            kill "${server_pid}" 2>/dev/null || true
            wait "${server_pid}" 2>/dev/null || true
        else
            log_warn "No suitable EFA test tool found (fi_pingpong or ib_write_bw)"
            check_skip "${CHECK_NAME}" "No EFA loopback test tools available"
            return 0
        fi

        # Parse results
        local bw_value="N/A"
        local lat_value="N/A"

        if [[ ${test_exit} -eq 0 && -n "${test_output}" ]]; then
            # Extract bandwidth (varies by tool output format)
            bw_value=$(echo "${test_output}" | grep -iE "bandwidth|bytes/sec|Gb/s" \
                | tail -1 | awk '{print $(NF-1), $NF}' || echo "N/A")
            lat_value=$(echo "${test_output}" | grep -iE "latency|usec" \
                | tail -1 | awk '{print $(NF-1), $NF}' || echo "N/A")

            log_verbose "Device ${device}: bw=${bw_value}, lat=${lat_value}"

            # Check bandwidth against per-instance threshold
            if [[ "${min_efa_bw}" -gt 0 && "${bw_value}" != "N/A" ]]; then
                local bw_numeric
                bw_numeric=$(echo "${bw_value}" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "0")
                local bw_int
                bw_int=$(echo "${bw_numeric}" | awk '{printf "%d", $1}')
                if [[ "${bw_int}" -lt "${min_efa_bw}" ]]; then
                    log_warn "Device ${device}: bandwidth ${bw_value} below threshold ${min_efa_bw} Gbps"
                    degraded=$((degraded + 1))
                fi
            fi
        else
            log_warn "Device ${device}: test failed or timed out (exit ${test_exit})"
            failures=$((failures + 1))
        fi

        # Append to JSON results
        if [[ "${results_json}" != "[" ]]; then
            results_json+=","
        fi
        results_json+=$(cat <<ENDJSON

    {
      "device": "${device}",
      "status": "$([ ${test_exit} -eq 0 ] && echo 'PASS' || echo 'FAIL')",
      "bandwidth": "${bw_value}",
      "latency": "${lat_value}"
    }
ENDJSON
)
    done <<< "${devices}"

    results_json+=$'\n]'

    # Save per-device results
    echo "${results_json}" > "${RESULTS_DIR}/efa-loopback-results.json"

    # Report degraded devices (below bandwidth threshold)
    if [[ ${degraded} -gt 0 ]]; then
        check_warn "${CHECK_NAME}" \
            "${degraded} device(s) below bandwidth threshold (${min_efa_bw} Gbps)"
    fi

    # Collect EFA statistics
    log_info "Collecting EFA statistics"
    if command -v rdma > /dev/null 2>&1; then
        local efa_stats
        if efa_stats=$(rdma -p statistic show 2>/dev/null); then
            echo "${efa_stats}" > "${RESULTS_DIR}/efa-statistics.txt"

            local rx_drops
            rx_drops=$(echo "${efa_stats}" | grep -oP 'rx_drops\s+\K[0-9]+' | awk '{sum+=$1} END {print sum+0}') || rx_drops=0
            local retrans_timeouts
            retrans_timeouts=$(echo "${efa_stats}" | grep -oP 'retrans_timeout_events\s+\K[0-9]+' | awk '{sum+=$1} END {print sum+0}') || retrans_timeouts=0

            if [[ "${rx_drops}" -gt 0 ]]; then
                check_warn "${CHECK_NAME}" "EFA rx_drops detected (${rx_drops}) -- possible network issues"
            fi
            if [[ "${retrans_timeouts}" -gt 0 ]]; then
                check_warn "${CHECK_NAME}" "EFA retransmission timeouts detected (${retrans_timeouts})"
            fi
            if [[ "${rx_drops}" -eq 0 && "${retrans_timeouts}" -eq 0 ]]; then
                log_verbose "EFA statistics clean -- no drops or retransmissions"
            fi
        else
            log_verbose "rdma statistic show failed -- EFA statistics skipped"
        fi
    else
        log_verbose "rdma tool not found -- EFA statistics skipped"
    fi

    if [[ ${failures} -gt 0 ]]; then
        check_fail "${CHECK_NAME}" \
            "${failures}/${device_count} EFA device(s) failed loopback test" "RESET"
        return 1
    fi

    check_pass "${CHECK_NAME}" \
        "EFA loopback OK: ${device_count} device(s) tested"
    return 0
}

# ─── Entry point ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

run_check
