# Spot-Resilient NVIDIA Dynamo — Disaggregated Inference on Spot

NVIDIA Dynamo (vLLM backend) **disaggregated** inference on EKS with GPU workers
on EC2 Spot Instances. Prefill and decode run as separate workers on separate
Spot nodes, connected by NIXL KV cache transfer. A real FIS Spot interruption
triggers NTH drain, ASG auto-replaces the node, and the decode worker recovers
with no manual intervention.

## Architecture

```
         ┌─────────────────────────────────────────────────────────────┐
         │  EKS Cluster — us-west-2                                    │
         │                                                             │
         │  ┌───────────────────────────────────────────┐              │
         │  │  System Node (m5.large, On-Demand)        │              │
         │  │                                           │              │
         │  │  • Dynamo Operator + etcd + NATS          │              │
         │  │  • Dynamo Frontend (OpenAI-compat API)    │              │
         │  │  • Dynamo Router (KV-cache-aware routing) │              │
         │  │  • AWS Node Termination Handler (IMDS)    │              │
         │  │  • Prometheus + Grafana                   │              │
         │  └───────────────────────────────────────────┘              │
         │                                                             │
         │   Request path:                                             │
         │   Client ──► Frontend ──► Router ──► Prefill Worker         │
         │                                        │                    │
         │                                  NIXL KV transfer           │
         │                                  (UCX / TCP)                │
         │                                        ▼                    │
         │                                    Decode Worker            │
         │                                        │                    │
         │                              tokens streamed back           │
         │                              via Frontend to Client         │
         │                                                             │
         │  ┌──────────────────────┐  ┌──────────────────────┐        │
         │  │ Prefill Node         │  │ Decode Node          │        │
         │  │ g7.2xlarge Spot      │  │ g7.2xlarge Spot      │        │
         │  │ RTX PRO 4500 (32 GB) │  │ RTX PRO 4500 (32 GB) │        │
         │  │                      │  │                      │        │
         │  │ Prefill Worker       │  │ Decode Worker        │        │
         │  │ (kv_role: kv_both)   │  │ (kv_role: kv_both)   │        │
         │  │                      │  │                      │        │
         │  │ ← Absorbs traffic    │  │ ← FIS interrupts     │        │
         │  │   via kv_both        │  │ ← NTH cordons+drains │        │
         │  │   failover           │  │ ← ASG auto-replaces  │        │
         │  └──────────────────────┘  └──────────────────────┘        │
         └─────────────────────────────────────────────────────────────┘
```

### Request Path (disaggregated)

```
1. Client sends POST /v1/chat/completions
2. Frontend accepts the request (OpenAI-compatible API)
3. Router selects a Prefill Worker (KV-cache-aware or load-balanced)
4. Prefill Worker computes KV cache, returns transfer metadata
5. Router injects metadata into decode request, selects a Decode Worker
6. Decode Worker pulls KV cache from Prefill via NIXL (UCX/TCP)
7. Decode Worker generates tokens, streams back through Frontend to Client
```

The Router runs inside the Frontend process but is an architecturally distinct
stage — it owns worker selection, KV-cache-aware routing, and the
prefill→decode orchestration.

## Scenario

| Scenario | Model | Pattern | Compute | Interruption |
|---|---|---|---|---|
| spot-resilient-disagg | Qwen2.5-3B-Instruct | Disaggregated (prefill + decode) | 2× g7.2xlarge Spot | Real FIS Spot interrupt + NTH drain + ASG auto-replace |

## Key Components

| Component | Purpose |
|---|---|
| **Dynamo Frontend** | OpenAI-compatible API gateway |
| **Dynamo Router** | KV-cache-aware worker selection; prefill→decode orchestration |
| **Prefill Worker** | Computes KV cache from prompt; transfers via NIXL |
| **Decode Worker** | Receives KV cache; generates tokens |
| **NIXL** | KV cache transfer prefill→decode (UCX/TCP on g7; no EFA) |
| **NTH** | Detects Spot ITN via IMDS; cordons + drains node |
| **Decode ASG** | Auto-replaces terminated Spot decode node |
| **etcd + NATS** | Dynamo service discovery + event transport |

## Prerequisites

| Requirement | Detail |
|---|---|
| AWS account | GPU Spot quota ≥ 16 vCPUs for G/VT Spot (2× g7.2xlarge) |
| Tools | `eksctl`, `kubectl`, `helm` (v3+), `aws` CLI v2 |
| HuggingFace token | **Not required** — Qwen2.5-3B-Instruct is public |
| Dynamo version | v1.5.1 (images pinned in the DGD manifest) |

## 0. Configure environment

```bash
cp env_vars.example env_vars
# edit env_vars: AWS_REGION, AWS_ACCOUNT_ID, EKS_CLUSTER_NAME
source env_vars
```

## 1. Create cluster + install Dynamo platform

```bash
./scripts/0-install-platform.sh
```

Creates an EKS cluster with:
- System node: m5.large On-Demand (Dynamo operator, Frontend, Router, NTH, Prometheus)
- GPU Spot nodes: 2× g7.2xlarge (one prefill, one decode), `capacity-optimized`
- Decode ASG for auto-replacement on Spot reclaim

Installs:
- NVIDIA device plugin (auto-installed by eksctl for GPU AMI)
- EBS CSI driver (for etcd/NATS persistent volumes)
- Dynamo Platform v1.5.1 (operator + etcd + NATS)

**Spot capacity note:** In our testing (us-west-2, Oct 2026), g5/g6 small sizes had no
Spot capacity. **g7.2xlarge** (RTX PRO 4500, 32 GB) was the only full-GPU type that
actually launched. Include g7 in your instance pool.

## 2. Download model (optional — vLLM downloads on startup)

```bash
./scripts/1-download-model.sh
```

Qwen2.5-3B-Instruct is public and small (~6 GB). vLLM downloads it automatically.

## 3. Deploy the disaggregated workers

```bash
./scripts/2-deploy-disaggregated.sh
```

Applies the `DynamoGraphDeployment` (v1beta1, disaggregated):
- **Frontend** on the system node (with Router embedded)
- **Prefill Worker** (`type: prefill`) on GPU Spot node 1
- **Decode Worker** (`type: decode`) on GPU Spot node 2
- NIXL KV transfer (`NixlConnector`, UCX/TCP backend)
- Grace periods: `terminationGracePeriodSeconds=90`,
  `DYN_RUNTIME_GRACEFUL_SHUTDOWN_TIMEOUT_SECS=60`

Smoke test:
```bash
kubectl port-forward -n dynamo svc/qwen-disagg-frontend 8000:8000 &
curl localhost:8000/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","messages":[{"role":"user","content":"Hello"}],"max_tokens":64}'
```

## 4. Install Node Termination Handler

```bash
./scripts/3-install-nth.sh
```

Deploys AWS NTH as an IMDS-mode DaemonSet. It polls instance metadata for Spot
interruption notices and cordons + drains the node before EC2 terminates it.

## 5. Install observability

```bash
./scripts/4-install-observability.sh
```

Installs Prometheus + Grafana via `kube-prometheus-stack`. See
[OBSERVABILITY.md](OBSERVABILITY.md) for details.

## 6. Baseline load test

```bash
./scripts/5-baseline-load.sh
```

60 seconds, 10 concurrent workers, mixed short (256) and long (2048) token
generations. Captures request success rate and throughput.

## 7. FIS Spot interruption test

```bash
./scripts/6-fis-interrupt.sh
```

Starts sustained concurrent load, then fires a **real** FIS Spot interruption
(`aws:ec2:send-spot-instance-interruptions`, `PT2M`) against the decode Spot node.

What happens:
1. FIS sends the Spot ITN (2-minute warning)
2. NTH detects it via instance metadata polling
3. NTH cordons the node and drains it (SIGTERM → Dynamo graceful shutdown)
4. In-flight requests on the decode worker drain cleanly
5. **kv_both failover**: the prefill worker absorbs all traffic transparently
6. EC2 terminates the instance at T+2min
7. ASG auto-launches a replacement Spot node (~2s after termination)
8. Decode pod reschedules, re-registers with discovery
9. Full disaggregated capacity restored

See [BENCHMARKS.md](BENCHMARKS.md) for the measured results and the honest
diagnosis of what zero-dropped does and does not prove.

## 8. Cleanup

```bash
./scripts/7-cleanup.sh          # scale GPU ASGs to zero
./scripts/teardown.sh            # delete the entire cluster
```

## Grace-Period Arithmetic

```
Dynamo drain budget  = grace_period (5s) + drain_timeout (60s) = 65s
K8s SIGKILL          = terminationGracePeriodSeconds = 90s
Spot kill            = 120s

drain (65s) < SIGKILL (90s) < Spot kill (120s) ✓
```

## Note on Request Migration

`DYN_MIGRATION_LIMIT=3` is set on the Frontend. Migration replays in-flight token
state to a healthy worker when the original fails. However, with only 1 decode
worker, there is no second decode worker to migrate to — migration has no target.
The zero-dropped result comes from `kv_role: kv_both` implicit failover (prefill
absorbs decode traffic), not from migration. See [BENCHMARKS.md](BENCHMARKS.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| EKS managed node group hangs 20+ min, `resources: null` | EKS API bug with GPU Spot MNGs | Use a custom ASG with correct launch template, or direct `run-instances` |
| `UnfulfillableCapacity` on self-managed node group | Launch template `NetworkInterfaces` missing `SubnetId` | Set `SubnetId` on the network interface |
| `InsufficientInstanceCapacity` for g5/g6 in all AZs | Spot exhaustion for small G-family | Use **g7.2xlarge** — had capacity when g5/g6 didn't |
| `DiskPressure` taint after image pull | Default 20 GB root volume too small | Use 100 GB gp3 root volume |
| etcd/NATS stuck in Pending | No EBS CSI driver | Install `aws-ebs-csi-driver` addon + gp3 StorageClass |
| Frontend returns 404 after worker eviction | Dynamo reports "model not found" when 0 workers registered | Handle 404 in client retry logic (not just 503) |
| g6f: GPU not in allocatable | Fractional vGPU; device plugin doesn't expose it | Use full-GPU types (g7.2xlarge+) |
