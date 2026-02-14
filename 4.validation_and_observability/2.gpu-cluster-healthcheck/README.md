# GPU Cluster Health Check Suite

A comprehensive, open-source health check suite for self-managed GPU clusters running Slurm on AWS. This suite leverages publicly available tools (DCGM, NCCL tests, EFA utilities, nvidia-smi) to validate GPU, network, and interconnect health on Slurm-based clusters.

The suite provides two operational modes: **lightweight checks** for regular use (prolog/epilog, cron) and **intensive checks** for quarantine and post-mortem scenarios. It follows a **replace, don't repair** operational model -- on AWS, the primary remediation for confirmed hardware faults is instance replacement rather than on-node repair.

## Quick Start

### Prerequisites

| Tool | Required For | Installation |
|------|-------------|-------------|
| NVIDIA Driver | All GPU checks | Pre-installed on GPU AMIs |
| [DCGM Toolkit](https://developer.nvidia.com/dcgm) | Checks 1, 4 | `apt install datacenter-gpu-manager` or via NVIDIA repo |
| EFA Installer | Checks 2, 6 | [AWS EFA Installer](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start.html) |
| NCCL Tests Container | Check 5 | `public.ecr.aws/hpc-cloud/nccl-tests:latest` |
| [Pyxis](https://github.com/NVIDIA/pyxis) + [Enroot](https://github.com/NVIDIA/enroot) | Check 5 (container) | Optional -- falls back to local `all_reduce_perf` |
| Python 3.6+ | Result parsing | Pre-installed on most Linux distributions |

### Installation

```bash
# Clone the repository
git clone https://github.com/aws-samples/awsome-distributed-training.git
cd awsome-distributed-training/4.validation_and_observability/2.gpu-cluster-healthcheck

# Make all scripts executable
chmod +x gpu-healthcheck.sh checks/*.sh slurm/*.sh examples/*.sh

# Run a quick validation (dry-run mode, no GPU required)
./gpu-healthcheck.sh --suite lightweight --dry-run
```

### First Check

```bash
# Run lightweight suite on a GPU node
./gpu-healthcheck.sh --suite lightweight

# Run a single check
./gpu-healthcheck.sh --check nvidia-smi

# View results
cat /tmp/gpu-healthcheck-*/summary.json | python3 -m json.tool
```

## Architecture

### Directory Structure

```
2.gpu-cluster-healthcheck/
├── README.md                          # This documentation
├── gpu-healthcheck.sh                 # Master orchestrator
├── instance-profiles.conf             # Per-instance-type hardware expectations
├── lib/
│   ├── common.sh                      # Shared utilities (logging, detection, formatting)
│   ├── parse-dcgm-results.py          # DCGM JSON → severity classification
│   └── aggregate-results.py           # Per-node → cluster summary aggregation
├── checks/
│   ├── 0-nvidia-smi-check.sh          # Quick nvidia-smi validation (~5s)
│   ├── 1-dcgm-diag-l2.sh             # DCGM Level 2 diagnostics (2.5-10.5 min)
│   ├── 2-efa-enumeration.sh           # EFA device + provider validation (~3s)
│   ├── 3-topology-check.sh            # GPU/NVLink/PCIe topology (~10s)
│   ├── 4-dcgm-diag-l4.sh             # DCGM Level 4 diagnostics (45 min-2.25 hr)
│   ├── 5-nccl-allreduce.sh           # Multi-node NCCL all_reduce (10-20 min)
│   └── 6-efa-loopback.sh             # Per-device EFA loopback (5-15 min)
├── slurm/
│   ├── prolog-gpu-healthcheck.sh      # Slurm prolog (checks 0-2)
│   ├── sbatch-lightweight.sh          # sbatch job for lightweight suite
│   ├── sbatch-intensive.sh            # sbatch job for intensive suite
│   └── sbatch-quarantine-workflow.sh  # Full quarantine decision workflow
└── examples/
    ├── cron-rolling-sweep.sh          # Periodic sweep across idle nodes
    └── slurm-epilog-example.sh        # Epilog with exit-code routing
```

### Check Levels

The suite organizes checks into two suites based on operational impact and runtime:

| Suite | Checks | Runtime | Use Case | Node Access |
|-------|--------|---------|----------|-------------|
| **Lightweight** | 0-3 | ~15 minutes | Prolog/epilog, periodic sweeps, triage | Shared OK |
| **Intensive** | 4-6 | 1-3 hours | Quarantine, post-mortem, deep diagnostics | Exclusive required |

### Severity Classification

All check results are classified into three severity levels that map directly to operational actions:

| Severity | Meaning | Action |
|----------|---------|--------|
| **ISOLATE** | Critical hardware fault confirmed | Drain node from Slurm, initiate instance replacement |
| **RESET** | Potentially recoverable issue | Reboot node, rerun lightweight suite |
| **MONITOR** | Minor anomaly, not service-affecting | Keep in service, flag for review |

## Instance Profiles

The file `instance-profiles.conf` defines expected hardware counts per instance type. Check scripts auto-detect the instance type via IMDS and look up the expected configuration.

| Instance Type | GPUs | EFA Devices | NVLink | Provider |
|--------------|------|-------------|--------|----------|
| p4d.24xlarge | 8 | 4 | Yes | efa |
| p4de.24xlarge | 8 | 4 | Yes | efa |
| p5.48xlarge | 8 | 32 | Yes | efa |
| p5e.48xlarge | 8 | 32 | Yes | efa |
| p5en.48xlarge | 8 | 16 | Yes | efa |
| p6-b200.48xlarge | 8 | 8 | Yes | efa |

To add a new instance type, append a line to `instance-profiles.conf`:
```
<instance-type>|<gpu-count>|<efa-count>|<nvlink-expected>|<efa-provider>
```

## Check Reference

### Check 0: nvidia-smi Validation

**Runtime:** ~5 seconds | **Suite:** Lightweight

Verifies basic GPU driver functionality:
- Confirms `nvidia-smi` executes and returns zero exit code
- Counts detected GPUs and compares against the instance profile
- Scans `dmesg` for Xid errors from the last 10 minutes
- Checks GPU persistence mode status

```bash
./gpu-healthcheck.sh --check 0
# or
./gpu-healthcheck.sh --check nvidia-smi
```

### Check 1: DCGM Level 2 Diagnostics

**Runtime:** 2.5 - 10.5 minutes | **Suite:** Lightweight

Runs medium-depth NVIDIA Data Center GPU Manager diagnostics:
- Deployment readiness validation
- PCIe bandwidth verification
- GPU memory stress test (short)
- SM stress test (short)

Pre-flight: Verifies `nv-hostengine` is running and starts it if needed, with awareness of systemd-managed DCGM services.

```bash
./gpu-healthcheck.sh --check 1
# or
./gpu-healthcheck.sh --check dcgm-l2

# Override timeout (default: 15 min)
DCGM_TIMEOUT=600 ./gpu-healthcheck.sh --check dcgm-l2
```

### Check 2: EFA Enumeration

**Runtime:** ~3 seconds | **Suite:** Lightweight

Validates EFA network infrastructure:
- Counts EFA PCI devices via `lspci` and compares against instance profile
- Lists RDMA devices via `ibv_devices`
- Verifies libfabric EFA provider via `fi_info -p efa`
- Checks `/dev/infiniband/uverbs*` device node presence

```bash
./gpu-healthcheck.sh --check 2
# or
./gpu-healthcheck.sh --check efa-enumeration
```

### Check 3: Topology Validation

**Runtime:** ~10 seconds | **Suite:** Lightweight

Validates GPU interconnect topology:
- Captures `nvidia-smi topo -m` matrix and checks for disconnected links
- Validates NVLink presence and status per GPU pair
- Verifies PCIe switch groupings
- On B200 instances: additional `nvidia-smi topo -p2p rwn` check

```bash
./gpu-healthcheck.sh --check 3
# or
./gpu-healthcheck.sh --check topology
```

### Check 4: DCGM Level 4 Diagnostics

**Runtime:** 45 minutes - 2.25 hours | **Suite:** Intensive | **Requires:** Exclusive access

The most comprehensive GPU diagnostic available. Includes everything in L2 plus Extended Utility Diagnostics (EUD) and pulse power testing.

**Pre-flight requirements** (all validated automatically):
1. Node must be exclusively allocated (no other GPU processes)
2. MIG must be disabled
3. Concurrent GPU telemetry services are stopped for the duration
4. `nv-hostengine` must be running

**Operational warnings:**
- Pulse power test draws variable power -- inform facility operators
- EUD cannot run with MIG enabled
- Do not run concurrent GPU monitoring during the test
- systemd may auto-restart DCGM services mid-test

```bash
./gpu-healthcheck.sh --check 4 --exclusive
# or
./gpu-healthcheck.sh --check dcgm-l4 --exclusive
```

### Check 5: Multi-Node NCCL all_reduce

**Runtime:** 10-20 minutes | **Suite:** Intensive | **Requires:** Minimum 2 nodes

Runs `all_reduce_perf` from the NCCL tests container to validate multi-node GPU communication over EFA:
- Message sizes: 8B to 128MB (power-of-2 sweep)
- Verifies EFA provider selection via `NCCL_DEBUG=INFO`
- Compares measured bus bandwidth against per-instance-type thresholds

Environment variables set automatically:
```bash
FI_PROVIDER=efa
FI_EFA_USE_DEVICE_RDMA=1
NCCL_NET_GDR_LEVEL=2
NCCL_DEBUG=INFO
```

```bash
# Must be run within a multi-node Slurm allocation
salloc -N 2 --exclusive
./gpu-healthcheck.sh --check 5
```

### Check 6: EFA Loopback Bandwidth/Latency

**Runtime:** 5-15 minutes | **Suite:** Intensive

Tests each EFA device individually:
- Iterates over all RDMA devices discovered via `ibv_devices`
- Runs `fi_pingpong` or `ib_write_bw` in loopback mode per device
- Reports bandwidth and latency per device
- Flags devices performing below instance-type thresholds

```bash
./gpu-healthcheck.sh --check 6
# or
./gpu-healthcheck.sh --check efa-loopback
```

## DCGM Operational Guide

### Level 2 vs Level 4 Positioning

| Aspect | Level 2 (`dcgmi diag -r 2`) | Level 4 (`dcgmi diag -r 4`) |
|--------|------|------|
| **Purpose** | Production gate / fast triage | Deep post-mortem / quarantine |
| **Runtime** | 2.5 - 10.5 min | 45 min - 2.25 hr |
| **When to run** | Prolog, epilog, periodic sweep | Node drained, exclusive access only |
| **EUD included** | No | Yes (~20 min, requires MIG disabled) |
| **Pulse test** | No | Yes (variable power draw) |
| **Safe for production** | Yes (with timeout guard) | No -- requires exclusive node access |
| **hostengine** | Must be running | Must be running; beware systemd auto-restart |

### Pre-flight Checklist (L4)

Before running DCGM Level 4:

- [ ] Node is drained from Slurm (`scontrol update NodeName=X State=DRAIN`)
- [ ] No other GPU processes running (`nvidia-smi --query-compute-apps=pid --format=csv`)
- [ ] MIG is disabled (`nvidia-smi -i 0 --query-gpu=mig.mode.current --format=csv,noheader`)
- [ ] DCGM exporter stopped (`systemctl stop dcgm-exporter` or container stopped)
- [ ] `nv-hostengine` running (check 4 handles this automatically)
- [ ] Facility operators aware of variable power draw during pulse test

### Severity Classification from DCGM Results

DCGM diagnostic results include a `warning_level` field per test per GPU:

| Warning Level | Severity | Action |
|--------------|----------|--------|
| 3 | **ISOLATE** | Drain node, initiate instance replacement |
| 2 | **RESET** | Reboot node, rerun lightweight suite |
| 1 | **MONITOR** | Keep in service, log for review |
| 0 | **PASS** | No action required |

The `parse-dcgm-results.py` script converts raw DCGM JSON into this classification automatically.

### hostengine Management

The DCGM host engine (`nv-hostengine`) must be running for diagnostics. Be aware of these interactions:

- If managed by systemd (`nvidia-dcgm.service`), systemd may auto-restart monitoring services that were stopped for L4
- The check scripts handle starting `nv-hostengine` if it is not running
- For L4, consider: `systemctl stop nvidia-dcgm && nv-hostengine` to avoid systemd interference

### NVIDIA Documentation References

- [DCGM Diagnostics Overview](https://docs.nvidia.com/dcgm/latest/user-guide/dcgm-diagnostics.html)
- [DCGM Run Levels](https://docs.nvidia.com/dcgm/latest/user-guide/dcgm-diagnostics.html#run-levels)
- [DCGM JSON Output](https://docs.nvidia.com/dcgm/latest/user-guide/dcgm-diagnostics.html#json-output)
- [DCGM Policy Management](https://docs.nvidia.com/dcgm/latest/user-guide/dcgm-policy-management.html)

## Slurm Integration

### Prolog Setup

Add to `slurm.conf`:

```conf
Prolog=/path/to/2.gpu-cluster-healthcheck/slurm/prolog-gpu-healthcheck.sh
PrologTimeout=900   # 15 minutes
```

By default, the prolog runs only checks 0 (nvidia-smi) and 2 (EFA enumeration) -- completing in ~8 seconds. DCGM L2 is **off by default** in prolog because it adds minutes of silence before job output appears.

> **Note:** Prolog output goes to syslog / slurmd logs, not to job output files.

To enable DCGM L2 in the prolog (adds 2-10 minutes):

```conf
PrologFlags=Contain
PrologSlurmctld=
# In the prolog environment:
# GPU_HEALTHCHECK_PROLOG_ENABLE_DCGM=1
```

Or set globally in `/etc/default/gpu-healthcheck`:
```bash
GPU_HEALTHCHECK_PROLOG_ENABLE_DCGM=1
```

A non-zero exit code from the prolog causes Slurm to drain the node and requeue the job.

### sbatch Examples

```bash
# Lightweight suite across 4 nodes
sbatch -N 4 -p gpu slurm/sbatch-lightweight.sh

# Intensive suite on 2 nodes (exclusive)
sbatch -N 2 -p maintenance --exclusive slurm/sbatch-intensive.sh

# Quarantine workflow on a suspect node
sbatch -N 1 -w suspect-node-001 --exclusive slurm/sbatch-quarantine-workflow.sh
```

### Cron Sweep

Set up a periodic sweep of idle GPU nodes:

```bash
# Check up to 10 idle nodes every 4 hours
echo "0 */4 * * * /path/to/examples/cron-rolling-sweep.sh >> /var/log/gpu-sweep.log 2>&1" | crontab -
```

### Epilog Pattern

The `examples/slurm-epilog-example.sh` demonstrates exit-code routing after job completion:
- Normal exit (0): quick nvidia-smi check only
- Signal kills (137, 139): full prolog-level check
- Any nvidia-smi failure: immediate node drain

## Decision Flow

The recommended operational workflow for handling suspected GPU issues:

```
               Monitoring / Job Failure
                       │
                       ▼
              ┌─────────────┐
              │  Drain Node  │  scontrol update NodeName=X State=DRAIN
              │  from Slurm  │
              └──────┬──────┘
                     │
                     ▼
              ┌─────────────┐
              │ Lightweight  │  gpu-healthcheck.sh --suite lightweight
              │ Suite (0-3)  │
              └──────┬──────┘
                     │
              ┌──────┴──────┐
              │             │
          PASS ▼         FAIL ▼
     ┌──────────┐    ┌──────────────┐
     │ Return to│    │Check Severity│
     │ Service  │    └──────┬───────┘
     └──────────┘           │
                    ┌───────┼──────┐
                    │       │      │
              ISOLATE   RESET   MONITOR
                    │       │      │
                    ▼       ▼      ▼
              ┌────────┐ ┌─────┐ ┌────────┐
              │Replace │ │Reboot│ │Return +│
              │Instance│ │Node  │ │ Flag   │
              └────────┘ └──┬──┘ └────────┘
                            │
                            ▼
                     ┌─────────────┐
                     │ Intensive   │  gpu-healthcheck.sh --suite intensive
                     │ Suite (4-6) │
                     └──────┬──────┘
                            │
                     ┌──────┴──────┐
                     │             │
                 PASS ▼         FAIL ▼
            ┌──────────┐    ┌──────────┐
            │ Return to│    │ Replace  │
            │ Service  │    │ Instance │
            └──────────┘    └──────────┘
```

The guiding principle is **replace, don't repair**. On AWS, the primary remediation for confirmed hardware faults is instance replacement. The intensive suite exists to confirm whether a fault is real (warranting replacement) or transient (safe to return to service after reboot).

## Troubleshooting

### nvidia-smi fails to execute

- Verify NVIDIA driver is loaded: `lsmod | grep nvidia`
- Check for driver/kernel mismatch: `dmesg | grep -i nvidia`
- Verify GPU device nodes exist: `ls /dev/nvidia*`

### DCGM diagnostics timeout

- L2 can take up to 10.5 minutes on 8-GPU instances -- set `DCGM_TIMEOUT` accordingly
- L4 can take up to 2.25 hours -- set `DCGM_L4_TIMEOUT` accordingly
- Verify `nv-hostengine` did not crash: `pgrep nv-hostengine`

### nv-hostengine won't start

- Check if another instance is running: `pgrep -a nv-hostengine`
- Check systemd status: `systemctl status nvidia-dcgm`
- Verify DCGM is installed: `dcgmi --version`

### EFA devices not detected

- Verify EFA installer ran successfully: `fi_info -p efa`
- Check kernel modules: `lsmod | grep efa`
- Verify PCI devices: `lspci | grep -i EFA`
- Check for EFA-compatible instance type

### NCCL all_reduce fails

- Verify EFA provider: ensure `NCCL_DEBUG=INFO` output shows "Selected Provider is EFA"
- Check container image availability: `enroot import docker://public.ecr.aws/hpc-cloud/nccl-tests:latest`
- Verify inter-node connectivity: security groups must allow all traffic between nodes
- Check for NCCL version compatibility with driver version

### Topology shows disconnected GPUs

- Check NVSwitch status (p5/p5e): `nvidia-smi nvlink --status`
- Verify PCIe ACS is disabled (can interfere with P2P): `setpci -s '*:*' ECAP_ACS+6.w`
- Check for recent Xid errors indicating NVLink failures: `dmesg | grep -i xid`

### MIG prevents DCGM L4

Disable MIG before running L4 diagnostics:
```bash
sudo nvidia-smi -i 0 -mig 0    # Disable MIG on GPU 0
sudo nvidia-smi --gpu-reset     # Reset GPUs (requires no running processes)
```
