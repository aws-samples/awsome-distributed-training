# Benchmarks — Spot-Resilient NVIDIA Dynamo (Disaggregated)

**Cluster:** EKS `dynamo-spot`, us-west-2
**GPU nodes:** 2× g7.2xlarge Spot (RTX PRO 4500, 32 GB VRAM each)
**Model:** Qwen2.5-3B-Instruct (BF16, ~6 GB)
**Dynamo:** v1.5.1 (vLLM v0.28.0, disaggregated prefill/decode, NIXL KV transfer over TCP)
**Date:** 2026-10-22

## Architecture

| Component | Node | Config |
|---|---|---|
| Frontend | System (m5.large On-Demand) | Dynamo Frontend v1.5.1, `DYN_MIGRATION_LIMIT=3` |
| Prefill worker | GPU Spot #1 (g7.2xlarge) | vLLM, `type=prefill`, `kv_role=kv_both` |
| Decode worker | GPU Spot #2 (g7.2xlarge) | vLLM, `type=decode`, `kv_role=kv_both` |
| Decode ASG | — | Auto-replaces terminated decode Spot node |

**Note on `kv_role: kv_both`:** This configuration means each worker can serve as
a complete aggregated engine (both prefill and decode). This has a significant
impact on the interruption test results — see the diagnosis section below.

---

## Concurrent Load Test (10 workers, ~10 min, real FIS interruption)

### Method

1. 10 concurrent Python workers sending requests continuously for 600 seconds
2. Mixed: every 3rd request uses `max_tokens=2048` (long), others `max_tokens=256` (short)
3. At T+30s, AWS FIS fires `aws:ec2:send-spot-instance-interruptions` against the
   decode Spot instance
4. NTH (IMDS DaemonSet) detects the Spot ITN, cordons and drains the decode node
5. ASG auto-launches a replacement g7.2xlarge Spot instance
6. Decode pod reschedules on the new node, re-registers with discovery

### Raw Results

| Metric | Value |
|---|---|
| Load duration | ~10 min (19:39:37Z – 19:49:36Z) |
| Total requests | **1098** |
| Concurrency | 10 workers |
| **Success (200)** | **1098 (100%)** |
| **Dropped** | **0** |
| Short request avg latency | ~2.8s |
| Long request avg latency | ~12s |
| Max latency (any request) | 15.1s |

### Latency by Minute (wall clock)

```
19:39: n=49  avg=5737ms  max=12409ms
19:40: n=117 avg=5144ms  max=13046ms  ← FIS fires at 19:40:08
19:41: n=109 avg=5413ms  max=12587ms
19:42: n=107 avg=5468ms  max=13792ms  ← EC2 terminates decode at 19:42:24
19:43: n=113 avg=5394ms  max=12833ms  ← decode GONE; prefill absorbs traffic
19:44: n=113 avg=5420ms  max=12959ms  ← ASG launches replacement at 19:44:04
19:45: n=103 avg=5748ms  max=15120ms  ← replacement node joining
19:46: n=104 avg=5598ms  max=14266ms
19:47: n=109 avg=5640ms  max=14610ms
19:48: n=106 avg=5718ms  max=14586ms
19:49: n=68  avg=5176ms  max=14030ms
                                        (new decode registers at 19:53:29)
```

**Throughput was flat at ~110 req/min throughout. No latency spike, no gap, no errors.**

---

## What Zero-Dropped Does and Does Not Prove

### The finding

Zero requests dropped — but the deployment was **never actually degraded**.

### The diagnosis

The no-decode-available window was **~11 minutes** (from EC2 termination of the
old decode instance at 19:42:24Z to the new decode worker registering with
discovery at 19:53:43Z). During that entire window:

- Request latency stayed at 2.7–15.1s (avg 5.4s)
- Throughput held steady at ~110 req/min
- Zero 404s, zero 503s, zero connection errors

This is physically impossible if requests needed a decode worker that wasn't there.
If the Frontend had been queuing requests for 11 minutes, latencies would be hundreds
of seconds. The max observed was 15.1s.

### Root cause: `kv_role: kv_both` implicit failover

Both workers were configured with `kv_role: kv_both` (in `--kv-transfer-config`).
This means the prefill worker is a **complete aggregated engine** that can handle
both prefill and decode phases. When the decode worker deregistered from Dynamo's
service discovery, the Frontend kept routing requests to the prefill worker — which
served them at normal throughput and latency.

**Supporting evidence:**
- Frontend logs during the gap: `KubeDiscoveryClient::list returning 3 instances
  for AllEndpoints` (the prefill worker's 3 endpoints: generate, clear_kv_blocks,
  get_perf_metrics)
- Prefill worker: 91.4% prefix cache hit rate (consistent with serving repeated prompts)
- No 404/503 in Frontend logs at any point during the gap

### Theories ruled out

| Theory | Verdict | Evidence |
|---|---|---|
| **Migration** (DYN_MIGRATION_LIMIT=3) | **Void** | Only 1 decode worker; migration requires a second healthy worker to migrate to. No target. |
| **Frontend queueing** | **Refuted** | Max latency 15.1s across an 11-min gap. Queueing → hundreds of seconds. |
| **Prefill aggregated fallback** | **Confirmed** | `kv_role: kv_both` + flat latency + Frontend routing to prefill endpoints + zero errors |

### What this means

**Proven:**
- Dynamo's graceful shutdown drains in-flight requests cleanly at SIGTERM
- `kv_role: kv_both` provides implicit failover — the remaining worker absorbs
  all traffic transparently when the other worker disappears
- ASG auto-replacement works (2s relaunch after termination)
- The full recovery chain (FIS → NTH → drain → ASG → new node → pod reschedule →
  re-register) works end-to-end with no manual intervention

**Not proven:**
- That a strictly-roled deployment (`kv_role: kv_producer` on prefill,
  `kv_role: kv_consumer` on decode) would survive with zero drops. In that
  configuration, the prefill worker cannot serve decode requests, and the
  ~11-minute gap would produce real failures.

---

## FIS Evidence

| Event | Timestamp | Source |
|---|---|---|
| FIS experiment started | 19:40:08Z | Experiment `EXTUwAo3KRduPrgQ` |
| NTH detects Spot ITN | 19:40:08Z | K8s event: `Spot ITN received. Instance will be interrupted at 19:42:21Z` |
| NTH PreDrain executed | ~19:40:10Z | K8s event: `Pre-drain task successfully executed` |
| Decode pod evicted | ~19:40:10Z | K8s event: `Pod evicted due to node drain` |
| Decode container killed | ~19:40:10Z | K8s event: `Stopping container main` |
| EC2 terminates instance | 19:42:24Z | EC2 StateTransitionReason: `User initiated (2026-10-22 19:42:24 GMT)` |
| Node cordoned + drained | ~19:42:30Z | K8s event: `Node successfully cordoned and drained` |
| **ASG launches replacement** | **19:44:04Z** | ASG: `Launching a new EC2 instance: i-055517e6a1ef7aef4` (2s after termination logged) |
| Replacement node Ready | ~19:45:00Z | Pod events: scheduling attempts begin |
| Image pulled | ~19:49:00Z | `Successfully pulled image ... in 3m33.901s` |
| Container started | ~19:49:04Z | `Started container main` |
| **New decode registered** | **19:53:29Z** | Decode log: `Registering endpoint: ...component=backend, endpoint=generate` |
| Frontend discovers new decode | 19:53:43Z | Frontend log: `Snapshot (seq=20): 2 instances, added=["5312c2de5588e"]` |

### Auto-Replacement Timeline

| Phase | Duration |
|---|---|
| FIS → EC2 terminates instance | 2m 16s |
| Termination → ASG launches replacement | ~2s |
| ASG launch → node Ready | ~1 min |
| Node Ready → image pulled | ~3m 34s |
| Image pulled → decode registered | ~4m 25s |
| **Total: FIS → decode serving again** | **~13 min 21s** |

---

## Grace-Period Configuration

| Setting | Value |
|---|---|
| `terminationGracePeriodSeconds` | 90 |
| `DYN_RUNTIME_GRACEFUL_SHUTDOWN_TIMEOUT_SECS` | 60 |
| `DYN_GRACEFUL_SHUTDOWN_GRACE_PERIOD_SECS` | 5 (default) |
| `DYN_MIGRATION_LIMIT` | 3 (Frontend — but ineffective with 1 decode worker) |

```
drain budget (65s) < K8s SIGKILL (90s) < Spot kill (120s) ✓
```

---

## Open Item: Strict-Role Re-Run

To measure a **true degraded window** with real dropped requests, re-run with
strict role separation:

- Prefill worker: `kv_role: kv_producer`
- Decode worker: `kv_role: kv_consumer`

This removes the implicit fallback and forces requests to fail during the gap
(no decode worker = no token generation). The expected result is a non-zero
dropped-request count during the ~11-minute recovery window, which would be the
honest measurement Daniel's requirement #3 asks for.

---

## Cost

| Component | Duration | Estimated Cost |
|---|---|---|
| 2× g7.2xlarge Spot | ~1.5 hr | ~$0.90–1.20 |
| m5.large On-Demand (system) | ~2 hr | ~$0.20 |
| EBS volumes (gp3, 100GB × 2) | ~2 hr | ~$0.03 |
| **Total session** | | **~$1.13–1.43** |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| EKS managed node group hangs 20+ min, `resources: null` | EKS API bug with GPU Spot mixed-instance MNGs | Use a custom ASG with a correct launch template, or direct `aws ec2 run-instances` |
| eksctl self-managed: `UnfulfillableCapacity` | Launch template has `NetworkInterfaces` without `SubnetId` | Set `SubnetId` on the network interface in the launch template |
| `InsufficientInstanceCapacity` for g5/g6 in all AZs | Spot exhaustion for small G-family types in us-west-2 | Use **g7.2xlarge** (RTX PRO 4500) — had real Spot capacity when g5/g6 didn't |
| `DiskPressure` taint on GPU node | Default 20 GB root volume too small for vLLM image (~12 GB) + model (~6 GB) | Specify `--block-device-mappings` with 100 GB gp3 |
| Frontend returns 404 (not 503) after worker eviction | Dynamo reports "model not found" when 0 workers registered, not "service unavailable" | Handle 404 in client retry logic |
| g6f instances: GPU not in allocatable | g6f uses fractional vGPU; standard device plugin doesn't expose it | Use full-GPU types (g6.xlarge+, g5.xlarge+, g7.2xlarge+) |
