#!/bin/bash
set -e

echo "================================="
echo "EFA Functionality Test"
echo "================================="
echo ""

echo "=== Checking EFA Device ==="
if fi_info -p efa &>/dev/null; then
    echo "✓ EFA provider detected"
    fi_info -p efa
else
    echo "✗ No EFA device found"
    echo "This is expected if running outside an EFA-enabled instance"
    exit 1
fi
echo ""

echo "=== Checking EFA Network Interfaces ==="
ip link show | grep -E "^[0-9]+: (efa|eth)" || echo "No EFA interfaces found"
echo ""

echo "=== Checking RDMA Devices ==="
ibv_devices || echo "No IB devices found (expected without EFA hardware)"
echo ""

echo "=== UCX Transport Check ==="
ucx_info -d | grep -A 5 "Transport:" || true
echo ""

echo "================================="
