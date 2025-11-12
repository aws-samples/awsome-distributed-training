#!/usr/bin/env bash
# validate-build.sh - Comprehensive build-time library validation
# Detects all installed libraries and verifies their paths

set -e

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "            BUILD-TIME LIBRARY PATH VALIDATION"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation counters
CRITICAL_MISSING=0
OPTIONAL_MISSING=0
FOUND_COUNT=0

# Detect container type based on what's installed
CONTAINER_TYPE="unknown"
if [ -d "/opt/dynamo/venv" ] || python3 -c "import vllm" 2>/dev/null; then
    CONTAINER_TYPE="vllm"
elif [ -d "/usr/local/lib/python3.12/dist-packages/tensorrt_llm" ] || python3 -c "import tensorrt_llm" 2>/dev/null; then
    CONTAINER_TYPE="trtllm"
elif [ -d "/opt/nvidia/nvda_nixl" ]; then
    CONTAINER_TYPE="production"
fi

echo "  Detected container type: ${CONTAINER_TYPE}"
echo ""

# Helper function to check critical library (supports multiple possible paths)
check_critical() {
    local name="$1"
    shift
    local paths=("$@")
    local found_path=""

    # Check all possible paths
    for path in "${paths[@]}"; do
        if [ -e "$path" ]; then
            found_path="$path"
            break
        fi
    done

    echo -n "  [CRITICAL] ${name}: "
    if [ -n "$found_path" ]; then
        echo -e "${GREEN}✓ FOUND${NC} at $found_path"
        FOUND_COUNT=$((FOUND_COUNT + 1))

        # List all related files
        if [ -d "$found_path" ]; then
            echo "             Contents: $(ls -1 $found_path 2>/dev/null | wc -l) files"
        else
            # If it's a symlink, show target
            if [ -L "$found_path" ]; then
                echo "             → $(readlink -f $found_path)"
            fi
        fi
    else
        echo -e "${RED}✗ MISSING${NC} (expected at: ${paths[*]})"
        CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
    fi
}

# Helper function to check optional library (supports multiple possible paths)
check_optional() {
    local name="$1"
    shift
    local paths=("$@")
    local found_path=""

    # Check all possible paths
    for path in "${paths[@]}"; do
        if [ -e "$path" ]; then
            found_path="$path"
            break
        fi
    done

    echo -n "  [OPTIONAL] ${name}: "
    if [ -n "$found_path" ]; then
        echo -e "${GREEN}✓ FOUND${NC} at $found_path"
        FOUND_COUNT=$((FOUND_COUNT + 1))

        # List all related files
        if [ -d "$found_path" ]; then
            echo "             Contents: $(ls -1 $found_path 2>/dev/null | wc -l) files"
        else
            if [ -L "$found_path" ]; then
                echo "             → $(readlink -f $found_path)"
            fi
        fi
    else
        echo -e "${YELLOW}⊘ NOT INSTALLED${NC} (expected at: ${paths[*]})"
        OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1))
    fi
}

# Helper function to check library in ld cache
check_ldcache() {
    local libname="$1"
    echo -n "  [LDCONFIG] ${libname}: "
    local found=$(ldconfig -p | grep "$libname" | head -1 | awk '{print $NF}')
    if [ -n "$found" ]; then
        echo -e "${GREEN}✓ FOUND${NC} at $found"
    else
        echo -e "${YELLOW}⊘ Not in ld cache${NC}"
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. CORE SYSTEM LIBRARIES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# CUDA
check_critical "CUDA Toolkit" "/usr/local/cuda"
check_critical "CUDA Libraries" "/usr/local/cuda/lib64"
check_ldcache "libcudart.so"

# GDRCopy
check_critical "GDRCopy" "/opt/gdrcopy"
# GDRCopy library check - if directory exists but lib not in expected location, check ldconfig
if [ -d "/opt/gdrcopy" ]; then
    if ldconfig -p 2>/dev/null | grep -q "libgdrapi.so"; then
        echo "  [INFO] GDRCopy Library: ✓ Found via ldconfig (runtime accessible)"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    else
        check_optional "GDRCopy Library" "/usr/lib/libgdrapi.so" "/lib/x86_64-linux-gnu/libgdrapi.so" "/lib/x86_64-linux-gnu/libgdrapi.so.2" "/opt/gdrcopy/lib64/libgdrapi.so"
    fi
else
    check_critical "GDRCopy Library" "/usr/lib/libgdrapi.so" "/lib/x86_64-linux-gnu/libgdrapi.so" "/lib/x86_64-linux-gnu/libgdrapi.so.2"
fi
check_ldcache "libgdrapi.so"

# UCX
check_critical "UCX" "/usr/local/ucx"
check_critical "UCX Libraries" "/usr/local/ucx/lib"
# Only check pkg-config if it doesn't work via PKG_CONFIG_PATH
if ! pkg-config --exists ucx 2>/dev/null; then
    check_critical "UCX pkg-config" "/usr/local/lib/pkgconfig/ucx.pc" "/usr/local/ucx/lib/pkgconfig/ucx.pc"
fi
check_ldcache "libucp.so"

# libfabric
check_critical "libfabric" "/usr/local/libfabric"
check_critical "libfabric Libraries" "/usr/local/libfabric/lib"
# Only check pkg-config if it doesn't work via PKG_CONFIG_PATH
if ! pkg-config --exists libfabric 2>/dev/null; then
    check_critical "libfabric pkg-config" "/usr/local/lib/pkgconfig/libfabric.pc" "/usr/local/libfabric/lib/pkgconfig/libfabric.pc"
fi
check_critical "libfabric symlink" "/usr/local/lib/libfabric.so"
check_ldcache "libfabric.so"

# EFA
# EFA can come from installer or from framework base image
if ldconfig -p 2>/dev/null | grep -q "libefa.so"; then
    echo "  [INFO] EFA: ✓ Found via ldconfig (runtime accessible)"
    FOUND_COUNT=$((FOUND_COUNT + 1))
    # Check for installer directory (optional)
    if [ -d "/opt/amazon/efa" ]; then
        check_optional "EFA Installer" "/opt/amazon/efa"
    fi
    check_optional "EFA Library" "/opt/amazon/efa/lib/libefa.so" "/usr/lib/x86_64-linux-gnu/libefa.so" "/lib/x86_64-linux-gnu/libefa.so"
else
    check_critical "EFA Installer" "/opt/amazon/efa"
    check_critical "EFA Library" "/opt/amazon/efa/lib/libefa.so" "/usr/lib/x86_64-linux-gnu/libefa.so"
fi
check_ldcache "libefa.so"

# PMIx (optional in production base, may be provided by HPC-X in vllm/trtllm)
PMIX_VERSION="${PMIX_VERSION:-4.2.6}"
if [ "$CONTAINER_TYPE" = "production" ]; then
    check_optional "PMIx" "/opt/pmix-${PMIX_VERSION}" "/opt/pmix"
    check_optional "PMIx Library" "/opt/pmix-${PMIX_VERSION}/lib/libpmix.so" "/opt/pmix/lib/libpmix.so"
elif [ "$CONTAINER_TYPE" = "vllm" ] || [ "$CONTAINER_TYPE" = "trtllm" ]; then
    # In derived containers, PMIx often comes from HPC-X (bundled with OpenMPI)
    # Check if standalone PMIx exists, otherwise it's provided by HPC-X
    if [ -d "/opt/pmix-${PMIX_VERSION}" ] || [ -d "/opt/pmix" ]; then
        check_optional "PMIx (standalone)" "/opt/pmix-${PMIX_VERSION}" "/opt/pmix"
    elif [ -f "/opt/hpcx/ompi/lib/libmpi.so" ]; then
        echo "  [INFO] PMIx: ✓ Provided by HPC-X OpenMPI"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    else
        check_critical "PMIx" "/opt/pmix-${PMIX_VERSION}" "/opt/pmix" "/opt/hpcx/pmix"
    fi
fi

# HPC-X OpenMPI (only in vllm/trtllm from framework image)
if [ "$CONTAINER_TYPE" = "vllm" ] || [ "$CONTAINER_TYPE" = "trtllm" ]; then
    check_critical "OpenMPI (HPC-X)" "/usr/local/lib/libmpi.so" "/opt/hpcx/ompi/lib/libmpi.so"
    check_ldcache "libmpi.so"
else
    check_optional "OpenMPI (HPC-X)" "/usr/local/lib/libmpi.so" "/opt/hpcx/ompi/lib/libmpi.so"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. NIXL COMMUNICATION STACK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

check_critical "NIXL" "/opt/nvidia/nvda_nixl"
check_critical "NIXL Headers" "/opt/nvidia/nvda_nixl/include"
check_critical "NIXL Libraries" "/opt/nvidia/nvda_nixl/lib" "/opt/nvidia/nvda_nixl/lib/x86_64-linux-gnu"
# NIXL pkg-config is optional
if ! pkg-config --exists nvda-nixl 2>/dev/null; then
    check_optional "NIXL pkg-config" "/usr/local/lib/pkgconfig/nvda-nixl.pc" "/opt/nvidia/nvda_nixl/lib/pkgconfig/nvda-nixl.pc"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. NCCL STACK (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# NCCL
if [ -f /usr/local/lib/libnccl.so ] || [ -f /usr/lib/x86_64-linux-gnu/libnccl.so ]; then
    check_optional "NCCL" "/usr/local/lib/libnccl.so" "/usr/lib/x86_64-linux-gnu/libnccl.so"
    check_ldcache "libnccl.so"

    # aws-ofi-nccl
    check_optional "aws-ofi-nccl" "/opt/aws-ofi-nccl"
    check_optional "aws-ofi-nccl plugin" "/opt/aws-ofi-nccl/lib/libnccl-net.so"

    # Check if aws-ofi-nccl is in ld cache
    if [ -f /etc/ld.so.conf.d/aws-ofi-nccl.conf ]; then
        echo "  [CONFIG] aws-ofi-nccl ld.so.conf: ${GREEN}✓ EXISTS${NC}"
    else
        echo "  [CONFIG] aws-ofi-nccl ld.so.conf: ${YELLOW}⊘ MISSING${NC}"
    fi
else
    echo "  ${YELLOW}NCCL not installed (INSTALL_NCCL != 1)${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. NVSHMEM (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "${INSTALL_NVSHMEM:-0}" = "1" ]; then
    check_optional "NVSHMEM" "/opt/nvshmem" "Version: ${NVSHMEM_VERSION:-unknown}"
    check_optional "NVSHMEM Library" "/opt/nvshmem/lib/libnvshmem.so"
else
    echo "  ${YELLOW}NVSHMEM not installed (INSTALL_NVSHMEM != 1)${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. SERVICE MESH DEPENDENCIES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Service mesh components (critical in production, optional in derived containers)
if [ "$CONTAINER_TYPE" = "production" ]; then
    # Full Dynamo needs these components
    check_critical "cpprestsdk" "/usr/local/lib/libcpprest.so"
    check_critical "gflags" "/usr/local/lib/libgflags.so"
    check_critical "ETCD" "/usr/local/bin/etcd" "/usr/bin/etcd"
    check_critical "ETCD C++ Client" "/usr/local/lib/libetcd-cpp-api.so"
    check_critical "AWS SDK C++ (s3)" "/usr/local/lib/libaws-cpp-sdk-s3.so"
    check_critical "NATS Server" "/usr/local/bin/nats-server" "/usr/bin/nats-server"
else
    # In derived containers, these are copied from dynamo_base if available
    check_optional "cpprestsdk" "/usr/local/lib/libcpprest.so"
    check_optional "gflags" "/usr/local/lib/libgflags.so"
    check_optional "ETCD" "/usr/local/bin/etcd" "/usr/bin/etcd" "/usr/local/bin/etcd/etcd"
    check_optional "ETCD C++ Client" "/usr/local/lib/libetcd-cpp-api.so"
    check_optional "AWS SDK C++ (s3)" "/usr/local/lib/libaws-cpp-sdk-s3.so"
    check_optional "NATS Server" "/usr/local/bin/nats-server" "/usr/bin/nats-server"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. PYTHON ENVIRONMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Python is always critical
PYTHON_PATH=$(which python3 2>/dev/null || echo "")
if [ -n "$PYTHON_PATH" ]; then
    check_critical "Python" "$PYTHON_PATH"
    echo "             Version: $(python3 --version 2>&1 | cut -d' ' -f2)"
else
    check_critical "Python" "/usr/bin/python3" "/bin/python3"
fi

# pip is only critical in vllm/trtllm containers
PIP_PATH=$(which pip3 2>/dev/null || which pip 2>/dev/null || echo "")
if [ "$CONTAINER_TYPE" = "vllm" ] || [ "$CONTAINER_TYPE" = "trtllm" ]; then
    if [ -n "$PIP_PATH" ]; then
        check_critical "pip" "$PIP_PATH"
    else
        check_optional "pip" "/usr/bin/pip3" "/usr/local/bin/pip3"
    fi
else
    # Production base doesn't need pip
    if [ -n "$PIP_PATH" ]; then
        check_optional "pip" "$PIP_PATH"
    fi
fi

# Check key Python packages (only for vllm/trtllm)
if [ "$CONTAINER_TYPE" = "vllm" ] || [ "$CONTAINER_TYPE" = "trtllm" ]; then
    echo "  [PACKAGES] Installed Python packages:"
    for pkg in torch transformers huggingface_hub; do
        if python3 -c "import $pkg" 2>/dev/null; then
            version=$(python3 -c "import $pkg; print($pkg.__version__)" 2>/dev/null || echo "unknown")
            echo "             - ${pkg}: ${GREEN}${version}${NC}"
        else
            echo "             - ${pkg}: ${YELLOW}not installed${NC}"
        fi
    done
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. PKG-CONFIG DATABASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "  Available pkg-config modules:"
for pc in ucx libfabric nvda-nixl cuda cudart; do
    if pkg-config --exists "$pc" 2>/dev/null; then
        version=$(pkg-config --modversion "$pc" 2>/dev/null || echo "unknown")
        echo "    - ${pc}: ${GREEN}${version}${NC}"
    else
        echo "    - ${pc}: ${YELLOW}not found${NC}"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. LD LIBRARY CACHE SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "  Key libraries in ld cache:"
for lib in libcudart.so libgdrapi.so libucp.so libfabric.so libefa.so libnccl.so libmpi.so; do
    count=$(ldconfig -p 2>/dev/null | grep -c "$lib" 2>/dev/null || true)
    # Ensure count is a valid integer
    if [ -z "$count" ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    if [ "$count" -gt 0 ]; then
        echo "    - ${lib}: ${GREEN}${count} entries${NC}"
    else
        echo "    - ${lib}: ${YELLOW}0 entries${NC}"
    fi
done

echo ""
echo "  /etc/ld.so.conf.d/ configuration files:"
ls -1 /etc/ld.so.conf.d/*.conf 2>/dev/null | while read conf; do
    echo "    - $(basename $conf)"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. VALIDATION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL_CHECKS=$((CRITICAL_MISSING + OPTIONAL_MISSING + FOUND_COUNT))
echo "  Total components checked: ${TOTAL_CHECKS}"
echo "  Found: ${GREEN}${FOUND_COUNT}${NC}"
echo "  Critical missing: ${RED}${CRITICAL_MISSING}${NC}"
echo "  Optional missing: ${YELLOW}${OPTIONAL_MISSING}${NC}"
echo ""

if [ $CRITICAL_MISSING -gt 0 ]; then
    echo -e "${RED}✗ BUILD VALIDATION FAILED${NC}"
    echo "  ${CRITICAL_MISSING} critical component(s) are missing!"
    echo "  Please review the build logs and ensure all dependencies are installed correctly."
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════"
    exit 1
else
    echo -e "${GREEN}✓ BUILD VALIDATION PASSED${NC}"
    echo "  All critical components are installed and accessible."
    if [ $OPTIONAL_MISSING -gt 0 ]; then
        echo "  Note: ${OPTIONAL_MISSING} optional component(s) not installed (expected)."
    fi
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════"
    echo ""
    exit 0
fi
