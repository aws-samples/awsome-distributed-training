#!/bin/bash

set -ex

LOG_FILE="/var/log/provision/provisioning.log"
mkdir -p "/var/log/provision"
touch "$LOG_FILE"

logger() {
  echo "$@" | tee -a "$LOG_FILE"
}

logger "[start] on_create.sh"

if ! bash ./on_create_main.sh >> "$LOG_FILE" 2>&1; then
  logger "[error] on_create_main.sh failed, waiting 60 seconds before exit, to make sure logs are uploaded"
  sync
  sleep 60
  logger "[stop] on_create.sh with error"
  exit 1
fi

# ===== EFA FSx LUSTRE CLIENT SETUP =====

setup_efa_fsx_client() {
    logger "[INFO] Starting EFA FSx client setup"

    # Step 1: OS compatibility check
    source /etc/os-release 2>/dev/null || { logger "[INFO] Cannot detect OS, skipping"; return 0; }

    case "$ID-$VERSION_ID" in
        "amzn-2023")
            logger "[INFO] Amazon Linux 2023 - supported" ;;
        "rhel-9."[5-9]* | "rhel-1"[0-9]*)
            logger "[INFO] RHEL $VERSION_ID - supported" ;;
        "ubuntu-22.04" | "ubuntu-2"[3-9]*)
            # Proper kernel version check for Ubuntu
            local kernel_major=$(uname -r | cut -d'.' -f1)
            local kernel_minor=$(uname -r | cut -d'.' -f2)
            if [[ "$kernel_major" -gt 6 ]] || [[ "$kernel_major" -eq 6 && "$kernel_minor" -ge 8 ]]; then
                logger "[INFO] Ubuntu $VERSION_ID kernel ${kernel_major}.${kernel_minor} - supported"
            else
                logger "[INFO] Ubuntu needs kernel 6.8+, found ${kernel_major}.${kernel_minor}, skipping"
                return 0
            fi ;;
        *)
            logger "[INFO] OS $ID $VERSION_ID not supported, skipping"
            return 0 ;;
    esac

    # Step 2: EFA availability check
    if [[ ! -x "/opt/amazon/efa/bin/fi_info" ]]; then
        logger "[INFO] EFA tools not found, skipping"
        return 0
    fi

    if ! /opt/amazon/efa/bin/fi_info -p efa >/dev/null 2>&1; then
        logger "[INFO] EFA not available on this instance, skipping"
        return 0
    fi

    logger "[INFO] EFA detected - configuring for FSx Lustre"

    # Step 3: Download and setup
    cd /tmp || { logger "[ERROR] Cannot access /tmp directory"; return 1; }

    logger "[INFO] Downloading EFA FSx client setup..."
    if ! curl --fail --silent --show-error --max-time 30 -o efa-setup.zip \
         "https://docs.aws.amazon.com/fsx/latest/LustreGuide/samples/configure-efa-fsx-lustre-client.zip"; then
        logger "[ERROR] Download failed"
        return 1
    fi

    logger "[INFO] Extracting setup files..."
    if ! unzip -q efa-setup.zip; then
        logger "[ERROR] Extract failed"
        rm -f efa-setup.zip
        return 1
    fi

    if [[ ! -f "configure-efa-fsx-lustre-client/setup.sh" ]]; then
        logger "[ERROR] Setup script not found in package"
        rm -rf configure-efa-fsx-lustre-client* efa-setup.zip
        return 1
    fi

    chmod +x configure-efa-fsx-lustre-client/setup.sh

    logger "[INFO] Running EFA FSx client setup..."
    if ./configure-efa-fsx-lustre-client/setup.sh; then
        logger "[SUCCESS] EFA FSx client configured successfully"
    else
        logger "[ERROR] EFA FSx client setup failed"
        rm -rf configure-efa-fsx-lustre-client* efa-setup.zip
        return 1
    fi

    # Cleanup
    rm -rf configure-efa-fsx-lustre-client* efa-setup.zip
    return 0
}

# Load Lustre modules
load_lustre_modules() {
    logger "[INFO] Loading Lustre kernel modules"

    # Load lnet module
    if modprobe lnet 2>/dev/null; then
        logger "[INFO] lnet module loaded"
    else
        logger "[WARN] lnet module load failed or already loaded"
    fi

    # Load lustre module
    if modprobe lustre 2>/dev/null; then
        logger "[INFO] lustre module loaded"
    else
        logger "[WARN] lustre module load failed or already loaded"
    fi

    # Initialize LNet network
    if command -v lctl >/dev/null 2>&1; then
        if lctl network up 2>/dev/null; then
            logger "[INFO] LNet network initialized"
        else
            logger "[INFO] LNet network already active or initialization attempted"
        fi
    fi
}

# Execute EFA FSx client setup
if setup_efa_fsx_client; then
    logger "[INFO] EFA FSx client setup completed successfully"
else
    logger "[INFO] EFA FSx client setup skipped or failed - continuing with standard Lustre"
fi

# Load Lustre modules (always execute)
load_lustre_modules

logger "[INFO] FSx client setup complete"

logger "no more steps to run"
logger "[stop] on_create.sh"
