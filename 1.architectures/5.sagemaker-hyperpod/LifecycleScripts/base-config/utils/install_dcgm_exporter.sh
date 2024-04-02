#!/bin/bash
if nvidia-smi; then
    echo "NVIDIA GPU found. Proceeding with script..."
    
    ### Create directory if it doesn't exist
    sudo mkdir -p /opt/dcgm-exporter/
    ### write a csv file to define dcgm metric collection (includes more metrics than default file)

    sudo tee /opt/dcgm-exporter/dcgm-golden-metrics.csv > /dev/null <<EOF
# Format
# If line starts with a '#' it is considered a comment
# DCGM FIELD, Prometheus metric type, help message

# Clocks
DCGM_FI_DEV_SM_CLOCK,  gauge, SM clock frequency (in MHz).
DCGM_FI_DEV_MEM_CLOCK, gauge, Memory clock frequency (in MHz).

# Temperature
DCGM_FI_DEV_MEMORY_TEMP, gauge, Memory temperature (in C).
DCGM_FI_DEV_GPU_TEMP,    gauge, GPU temperature (in C).

# Power
DCGM_FI_DEV_POWER_USAGE,              gauge, Power draw (in W).
DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION, counter, Total energy consumption since boot (in mJ).

# PCIE
# DCGM_FI_DEV_PCIE_TX_THROUGHPUT,  counter, Total number of bytes transmitted through PCIe TX (in KB) via NVML.
# DCGM_FI_DEV_PCIE_RX_THROUGHPUT,  counter, Total number of bytes received through PCIe RX (in KB) via NVML.
DCGM_FI_DEV_PCIE_REPLAY_COUNTER, counter, Total number of PCIe retries.

# Utilization (the sample period varies depending on the product)
DCGM_FI_DEV_GPU_UTIL,      gauge, GPU utilization (in %).
DCGM_FI_DEV_MEM_COPY_UTIL, gauge, Memory utilization (in %).
DCGM_FI_DEV_ENC_UTIL,      gauge, Encoder utilization (in %).
DCGM_FI_DEV_DEC_UTIL ,     gauge, Decoder utilization (in %).

# Errors and violations
DCGM_FI_DEV_XID_ERRORS,            gauge,   Value of the last XID error encountered.
DCGM_FI_DEV_POWER_VIOLATION,       counter, Throttling duration due to power constraints (in us).
DCGM_FI_DEV_THERMAL_VIOLATION,     counter, Throttling duration due to thermal constraints (in us).
DCGM_FI_DEV_SYNC_BOOST_VIOLATION,  counter, Throttling duration due to sync-boost constraints (in us).
DCGM_FI_DEV_BOARD_LIMIT_VIOLATION, counter, Throttling duration due to board limit constraints (in us).
DCGM_FI_DEV_LOW_UTIL_VIOLATION,    counter, Throttling duration due to low utilization (in us).
DCGM_FI_DEV_RELIABILITY_VIOLATION, counter, Throttling duration due to reliability constraints (in us).

# Memory usage
DCGM_FI_DEV_FB_FREE, gauge, Framebuffer memory free (in MiB).
DCGM_FI_DEV_FB_USED, gauge, Framebuffer memory used (in MiB).

# ECC
DCGM_FI_DEV_ECC_SBE_VOL_TOTAL, counter, Total number of single-bit volatile ECC errors.
DCGM_FI_DEV_ECC_DBE_VOL_TOTAL, counter, Total number of double-bit volatile ECC errors.
DCGM_FI_DEV_ECC_SBE_AGG_TOTAL, counter, Total number of single-bit persistent ECC errors.
DCGM_FI_DEV_ECC_DBE_AGG_TOTAL, counter, Total number of double-bit persistent ECC errors.

# Retired pages
DCGM_FI_DEV_RETIRED_SBE,     counter, Total number of retired pages due to single-bit errors.
DCGM_FI_DEV_RETIRED_DBE,     counter, Total number of retired pages due to double-bit errors.
DCGM_FI_DEV_RETIRED_PENDING, counter, Total number of pages pending retirement.

# NVLink
DCGM_FI_DEV_NVLINK_CRC_FLIT_ERROR_COUNT_TOTAL, counter, Total number of NVLink flow-control CRC errors.
DCGM_FI_DEV_NVLINK_CRC_DATA_ERROR_COUNT_TOTAL, counter, Total number of NVLink data CRC errors.
DCGM_FI_DEV_NVLINK_REPLAY_ERROR_COUNT_TOTAL,   counter, Total number of NVLink retries.
DCGM_FI_DEV_NVLINK_RECOVERY_ERROR_COUNT_TOTAL, counter, Total number of NVLink recovery errors.
DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL,            counter, Total number of NVLink bandwidth counters for all lanes.
# DCGM_FI_DEV_NVLINK_BANDWIDTH_L0,               counter, The number of bytes of active NVLink rx or tx data including both header and payload.

# VGPU License status
DCGM_FI_DEV_VGPU_LICENSE_STATUS, gauge, vGPU License status

# Remapped rows
DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS, counter, Number of remapped rows for uncorrectable errors
DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS,   counter, Number of remapped rows for correctable errors
DCGM_FI_DEV_ROW_REMAP_FAILURE,           gauge,   Whether remapping of rows has failed
DCGM_FI_DEV_ROW_REMAP_PENDING,           gauge,   Whether remapping of rows is pending.

# Static configuration information. These appear as labels on the other metrics
DCGM_FI_DRIVER_VERSION,        label, Driver Version
# DCGM_FI_NVML_VERSION,          label, NVML Version
# DCGM_FI_DEV_BRAND,             label, Device Brand
DCGM_FI_DEV_SERIAL,            label, Device Serial Number
# DCGM_FI_DEV_OEM_INFOROM_VER,   label, OEM inforom version
# DCGM_FI_DEV_ECC_INFOROM_VER,   label, ECC inforom version
# DCGM_FI_DEV_POWER_INFOROM_VER, label, Power management object inforom version
# DCGM_FI_DEV_INFOROM_IMAGE_VER, label, Inforom image version
# DCGM_FI_DEV_VBIOS_VERSION,     label, VBIOS version of the device

# DCP metrics
DCGM_FI_PROF_GR_ENGINE_ACTIVE,   gauge, Ratio of time the graphics engine is active (in %).
# DCGM_FI_PROF_SM_ACTIVE,          gauge, The ratio of cycles an SM has at least 1 warp assigned (in %).
# DCGM_FI_PROF_SM_OCCUPANCY,       gauge, The ratio of number of warps resident on an SM (in %).
DCGM_FI_PROF_PIPE_TENSOR_ACTIVE, gauge, Ratio of cycles the tensor (HMMA) pipe is active (in %).
DCGM_FI_PROF_DRAM_ACTIVE,        gauge, Ratio of cycles the device memory interface is active sending or receiving data (in %).
# DCGM_FI_PROF_PIPE_FP64_ACTIVE,   gauge, Ratio of cycles the fp64 pipes are active (in %).
# DCGM_FI_PROF_PIPE_FP32_ACTIVE,   gauge, Ratio of cycles the fp32 pipes are active (in %).
# DCGM_FI_PROF_PIPE_FP16_ACTIVE,   gauge, Ratio of cycles the fp16 pipes are active (in %).
DCGM_FI_PROF_PCIE_TX_BYTES,      gauge, The rate of data transmitted over the PCIe bus - including both protocol headers and data payloads - in bytes per second.
DCGM_FI_PROF_PCIE_RX_BYTES,      gauge, The rate of data received over the PCIe bus - including both protocol headers and data payloads - in bytes per second.
EOF
    #chmod +x /opt/dcgm-exporter/dcgm-golden-metrics.csv
    
    ### write script to /opt/dcgm that is used to run nvidia dcgm exporter docker container
    sudo tee /opt/dcgm-exporter/install-dcgm.sh > /dev/null <<EOF
#!/bin/bash

# Check if Nvidia GPU is present
if nvidia-smi; then
    echo "NVIDIA GPU found. Proceeding with script..."
    # Set DCGM Exporter version
    DCGM_EXPORTER_VERSION=3.3.5-3.4.0-ubuntu22.04

    # Run the DCGM Exporter Docker container
    sudo docker run -d --rm \
       --gpus all \
       --net host \
       --cap-add SYS_ADMIN \
       -v /opt/dcgm-exporter/dcgm-golden-metrics.csv:/etc/dcgm-exporter/dcgm-golden-metrics.csv \
       nvcr.io/nvidia/k8s/dcgm-exporter:\${DCGM_EXPORTER_VERSION} \
       -f /etc/dcgm-exporter/dcgm-golden-metrics.csv || { echo "Failed to run DCGM Exporter Docker container"; exit 1; }

    echo "Running DCGM exporter in a Docker container on port 9400..."
else
    echo "NVIDIA GPU not found. DCGM Exporter was not installed. If this is a controller node, you can safely ignore this warning. Exiting gracefully..."
    exit 0
fi

EOF

    # Confirm successful writing of the script
    echo "Script '/opt/dcgm-exporter/install-dcgm.sh' has been successfully written."

    # Change read/write permissions
    sudo chmod +x /opt/dcgm-exporter/install-dcgm.sh

    # Write service file for dcgm-exporter
    sudo tee /etc/systemd/system/dcgm-exporter.service > /dev/null <<EOF
[Unit]
Description=DCGM Exporter Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/dcgm-exporter/install-dcgm.sh

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now dcgm-exporter.service

else
    echo "NVIDIA GPU not found. DCGM Exporter was not installed. If this is a controller node, you can safely ignore this warning. Exiting gracefully..."
    exit 0
fi
EOF

    # Confirm successful writing of the script
    echo "Script '/opt/dcgm-exporter/install-dcgm.sh' has been successfully written."

    # Change read/write permissions
    sudo chmod +x /opt/dcgm-exporter/install-dcgm.sh

    # Write service file for dcgm-exporter
    sudo tee /etc/systemd/system/dcgm-exporter.service > /dev/null <<EOF
[Unit]
Description=DCGM Exporter Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/dcgm-exporter/install-dcgm.sh

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now dcgm-exporter.service

else
    echo "NVIDIA GPU not found. DCGM Exporter was not installed. If this is a controller node, you can safely ignore this warning. Exiting gracefully..."
    exit 0
fi