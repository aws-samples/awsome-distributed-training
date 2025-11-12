#!/bin/bash
# sccache wrapper for distributed compilation caching

set -e

SCCACHE_VERSION="0.8.1"
ARCH=$(uname -m)

case "$1" in
    install)
        echo "=== Installing sccache v${SCCACHE_VERSION} ==="
        cd /tmp
        wget -q "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${ARCH}-unknown-linux-musl.tar.gz"
        tar xzf sccache-*.tar.gz
        mv sccache-*/sccache /usr/local/bin/
        chmod +x /usr/local/bin/sccache
        rm -rf sccache-*
        sccache --version
        echo "✅ sccache installed"
        ;;
    
    show-stats)
        echo "=== sccache statistics for $2 ==="
        if command -v sccache >/dev/null 2>&1; then
            sccache --show-stats
        else
            echo "sccache not installed"
        fi
        ;;
    
    *)
        echo "Usage: $0 {install|show-stats}"
        exit 1
        ;;
esac
