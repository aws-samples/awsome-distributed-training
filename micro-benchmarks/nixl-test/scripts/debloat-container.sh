#!/bin/bash
# debloat-container.sh - Remove unnecessary files from container to reduce size
# Run this inside the container or during Docker build

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "Container Debloat Script"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Function to show size before and after
show_size() {
    df -h / | tail -1 | awk '{print $3 " used of " $2}'
}

echo "Initial size: $(show_size)"
echo ""

# ============================================================================
# Keep essential editors and tools
# ============================================================================
KEEP_EDITORS=(nano vim less)
KEEP_NETWORK=(curl wget ssh openssh-client)
KEEP_DEBUG=(gdb strace lsof htop)
KEEP_BUILD_RUNTIME=(git)
KEEP_SHELL_TOOLS=(sed grep find awk bash coreutils)

echo "✅ Keeping essential tools:"
echo "   Editors: ${KEEP_EDITORS[@]}"
echo "   Network: ${KEEP_NETWORK[@]}"
echo "   Debug:   ${KEEP_DEBUG[@]}"
echo "   Shell:   sed, grep, find, awk (required for scripts)"
echo ""

# Mark essential packages as manually installed to prevent removal
apt-mark manual sed grep findutils gawk coreutils bash 2>/dev/null || true

# ============================================================================
# 1. Remove build artifacts and object files
# ============================================================================
echo "🧹 Removing build artifacts..."
find / -type f -name "*.o" -delete 2>/dev/null || true
find / -type f -name "*.a" -delete 2>/dev/null || true
find / -type f -name "*.la" -delete 2>/dev/null || true
find / -type d -name "CMakeFiles" -exec rm -rf {} + 2>/dev/null || true
find / -type f -name "CMakeCache.txt" -delete 2>/dev/null || true
echo "   Removed object files and CMake artifacts"

# ============================================================================
# 2. Remove Python cache and compiled files
# ============================================================================
echo "🧹 Removing Python cache files..."
find / -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find / -type f -name "*.pyc" -delete 2>/dev/null || true
find / -type f -name "*.pyo" -delete 2>/dev/null || true
find / -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
echo "   Removed Python cache"

# ============================================================================
# 3. Clean apt cache
# ============================================================================
echo "🧹 Cleaning apt cache..."
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
rm -rf /var/cache/apt/* 2>/dev/null || true
echo "   Cleaned apt cache"

# ============================================================================
# 4. Remove pip/uv cache (if not using mounted cache)
# ============================================================================
echo "🧹 Cleaning pip/uv cache..."
rm -rf /root/.cache/pip 2>/dev/null || true
rm -rf /root/.cache/uv 2>/dev/null || true
rm -rf /root/.cargo/registry 2>/dev/null || true
echo "   Cleaned pip/uv cache"

# ============================================================================
# 5. Remove build-only tools (CAREFUL - only remove if not needed)
# ============================================================================
echo "🧹 Removing build-only tools..."
REMOVE_BUILD_TOOLS=(
    # Keep gcc/g++ if you might need to build Python extensions at runtime
    # Uncomment to remove:
    # gcc
    # g++
    # make
    cmake
    ninja-build
    autoconf
    automake
    libtool
    pkg-config
)

# Only remove if they exist
for tool in "${REMOVE_BUILD_TOOLS[@]}"; do
    if dpkg -l | grep -q "^ii  $tool"; then
        apt-get remove -y --purge "$tool" 2>/dev/null || true
        echo "   Removed: $tool"
    fi
done
apt-get autoremove -y 2>/dev/null || true
echo "   Removed build tools"

# ============================================================================
# 6. Remove documentation and man pages
# ============================================================================
echo "🧹 Removing documentation..."
rm -rf /usr/share/man/* 2>/dev/null || true
rm -rf /usr/share/doc/* 2>/dev/null || true
rm -rf /usr/share/info/* 2>/dev/null || true
rm -rf /usr/share/gtk-doc/* 2>/dev/null || true
echo "   Removed documentation"

# ============================================================================
# 7. Clean temporary files
# ============================================================================
echo "🧹 Cleaning temporary files..."
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true
echo "   Cleaned /tmp and /var/tmp"

# ============================================================================
# 8. Remove git repositories used for building
# ============================================================================
echo "🧹 Removing git build repositories..."
# Only remove if they exist and are in /tmp or /opt/build
rm -rf /tmp/vllm 2>/dev/null || true
rm -rf /tmp/nccl 2>/dev/null || true
rm -rf /tmp/ucx 2>/dev/null || true
rm -rf /opt/build/* 2>/dev/null || true
echo "   Removed build repositories"

# ============================================================================
# 9. Strip debug symbols from binaries (OPTIONAL - reduces debugging capability)
# ============================================================================
# Uncomment to strip debug symbols (saves significant space but makes debugging harder)
# echo "🧹 Stripping debug symbols..."
# find /usr/local -type f -executable -exec strip --strip-debug {} \; 2>/dev/null || true
# find /opt -type f -executable -exec strip --strip-debug {} \; 2>/dev/null || true
# echo "   Stripped debug symbols"

# ============================================================================
# 10. Remove source code directories (keep compiled libraries)
# ============================================================================
echo "🧹 Removing source directories..."
rm -rf /opt/nixl 2>/dev/null || true  # Source code, keep /opt/nvidia/nvda_nixl
echo "   Removed source directories"

# ============================================================================
# 11. Optimize shared libraries
# ============================================================================
echo "🧹 Removing static libraries (keep shared)..."
find /usr/local/lib -name "*.a" -delete 2>/dev/null || true
find /opt -name "*.a" -delete 2>/dev/null || true
echo "   Removed static libraries"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Debloat Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Final size: $(show_size)"
echo ""
echo "Kept essential tools:"
echo "  ✅ Editors: nano, vim"
echo "  ✅ Network: curl, wget, ssh"
echo "  ✅ Debug: htop, strace"
echo "  ✅ Git (for version control)"
echo ""
echo "Removed:"
echo "  🗑️  Build artifacts (*.o, *.a, CMake files)"
echo "  🗑️  Python cache (__pycache__, *.pyc)"
echo "  🗑️  Apt cache and lists"
echo "  🗑️  Documentation and man pages"
echo "  🗑️  Build-only tools (cmake, ninja, etc.)"
echo "  🗑️  Temporary files"
echo ""
