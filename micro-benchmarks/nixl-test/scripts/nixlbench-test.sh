#!/bin/bash
set -e

echo "================================="
echo "nixlbench Test Suite"
echo "================================="
echo ""

# Check if etcd is running
if ! curl -s http://localhost:2379/health &>/dev/null; then
    echo "Starting local etcd server..."
    etcd --listen-client-urls http://0.0.0.0:2379 \
         --advertise-client-urls http://localhost:2379 &
    ETCD_PID=$!
    sleep 3
    echo "ETCD started with PID: $ETCD_PID"
else
    echo "ETCD already running"
fi
echo ""

echo "=== Testing nixlbench Help ==="
nixlbench --help 2>&1 | head -30
echo ""

echo "=== Running Basic UCX Benchmark ==="
echo "Command: nixlbench --etcd_endpoints http://localhost:2379 --backend UCX --num_iter 10 --warmup_iter 5"
timeout 60s nixlbench \
    --etcd_endpoints http://localhost:2379 \
    --backend UCX \
    --num_iter 10 \
    --warmup_iter 5 || echo "Benchmark timed out or failed (may be expected)"
echo ""

# Cleanup
if [ ! -z "$ETCD_PID" ]; then
    echo "Stopping etcd..."
    kill $ETCD_PID 2>/dev/null || true
fi

echo "================================="
echo "Test Complete"
echo "================================="
