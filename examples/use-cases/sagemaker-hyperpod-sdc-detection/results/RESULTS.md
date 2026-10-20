# Reference results

Results of two runs of `experiments/run_order.py` on one SageMaker HyperPod cluster, with example IDs in place of real ones (`experiments/sanitize.py`). Each run directory holds the raw records (`order.json`), every rank's local gradient norm on every step (`norms.json.gz`), the sanitized rank map and localization check, all pod logs, the job manifest, the image digests, and `MANIFEST.sha256`. `python3 experiments/analyze.py <run dir>` reproduces every number below.

> **All data is synthetic, and every fault was injected in software.** The results show that each check behaves as designed. They don't show how often real hardware fails, or how real faults look. Each scenario ran once, with one seed.

## Runs

| Run | Instances | Ranks | Directory | Started (UTC) | Image digest | Code |
|---|---|---|---|---|---|---|
| A | 4 × ml.p5.48xlarge | 32 | `results/run-a-4-instances` | 2026-10-12 12:37 | `sha256:c4685b080728…` | SHA-256 identical to the code in this directory |
| B | 3 × ml.p5.48xlarge | 24 | `results/run-b-3-instances` | 2026-10-12 14:42 | `sha256:c4685b080728…` | SHA-256 identical to the code in this directory |

Both runs used PyTorch 2.9.0 (CUDA 13.0), NCCL 2.27.7 over EFA, NVIDIA driver 580.178.04, and the 953M-parameter Llama-style model: 16 layers, hidden size 2,048, sequence length 2,048, 2 sequences per GPU, bf16 autocast, AdamW, 400 warm-up steps before the scenarios.

## Fault scenarios (run A, 32 ranks)

Faults were injected in `blocks.7.mlp.down` on a chosen rank and step. Unless noted, audits ran every 10 steps with deterministic kernels, weight checks every 10 steps, and a checkpoint every 20. Step numbers count from the snapshot. Pairs are (target, replayer). Saves were a stand-in that recorded the decision and its tags; nothing was written.

| # | Injected fault | Result | Caught by |
|---|---|---|---|
| 1 | None, 50 steps | No alarm. Checkpoints at steps 0, 20, and 40, each from a copy that matched the majority | — |
| 2 | NaN in one element of rank 13's forward output, on step 25 only (not an audit step) | Fired on step 25 and named rank 13. The ring replay also ran; confirmation by rank 21 and rank 13: *transient on rank 13*. Step 25 wasn't applied. Suspect window: steps 21–25 | Check 1 |
| 3 | One element of rank 13's forward output ×1,000, on every step from step 23 | Steps 23–29 passed check 1 and were applied. The audit at step 30 mismatched (13, 5) and (21, 13) and named rank 13. Step 30 wasn't applied. Suspect window: steps 21–30 | Check 2 |
| 4 | The same ×1,000 on audit step 30 only | One pair mismatched, (13, 5). Confirmation by rank 21, on a third node, and by rank 13: *transient on rank 13* | Check 2 |
| 5 | The persistent ×1,000 on rank 5, which replays rank 13's micro-batch | Pairs (13, 5) and (5, 29) mismatched; named rank 5. A single replay of rank 13 by rank 5 would have blamed the healthy rank 13 | Check 2 |
| 6 | One element of rank 13's forward output ×10,000, every step from step 23 | Named rank 13 at step 30 | Check 2 |
| 7 | 10% multiplicative noise on the whole output of rank 13's layer, every step from step 23 | Named rank 13 at step 30 | Check 2 |
| 8 | One element of the gradient flowing into rank 13's layer ×1,000, every step from step 23 (backward only) | Named rank 13 at step 30. Only the gradient fingerprints could differ | Check 2 |
| 9 | One element of rank 13's weight gradient ×1,000, every step from step 23 (backward only) | Named rank 13 at step 30, from the gradient fingerprints | Check 2 |
| 10 | The same, with default-kernel audits | **No alarm in 50 steps.** The checkpoints at steps 20 and 40 were tagged with passing audits and weight checks, because the loss was unaffected and every copy had applied the same corrupted updates | Not caught |
| 11 | Bit 3 flipped in one bf16 element of rank 13's forward output, every step from step 23 (both audit modes) | Named rank 13 at step 30, in both modes | Check 2 |
| 12 | One output column of rank 13's layer ×1.1, every step from step 23 (both audit modes) | Named rank 13 at step 30, in both modes | Check 2 |
| 13 | The persistent ×1,000 on ranks 13 and 22 at once | Pairs (13, 5), (21, 13), (22, 14) and (30, 22) mismatched; named ranks 13 and 22 | Check 2 |
| 14 | Bit 22 flipped in one fp32 weight element on rank 0 after the step-31 update; checkpoint every 5 steps | The forced weight check at checkpoint step 35 named rank 0, and the save didn't happen. Suspect window: steps 31–35 | Check 3 |
| 15 | The same, with `check_on_checkpoint=False` | **The save at step 35 went ahead from rank 0's corrupted copy.** Its tags showed the last passing weight check at step 30. The ring audit named rank 0 at step 40, from pairs (8, 0) and (0, 24) | Check 2, five steps late |
| 16 | Two values swapped in one weight tensor on rank 0 after the step-31 update; no audits, weight checks every 10 steps | The weight check at step 40 named rank 0, although the tensor's plain bit sum hadn't changed | Check 3 |
| 17 | +4,096 and −4,096 added to the bit patterns of two values in one weight tensor on rank 0, on the same schedule | The weight check at step 40 named rank 0, although the tensor's plain bit sum hadn't changed | Check 3 |
| 18 | Bit 22 flipped in one attention weight on rank 7, after restoring the snapshot (a stand-in for loading a checkpoint) | `find_divergent_ranks`, run before the first step, named rank 7 | Check 3 |

In every compute-path scenario where check 1 or 2 fired, the alarm step wasn't applied, and afterwards all 32 copies of the weights and of the optimizer state were finite and identical (`state_after` in each record).

## Run B: three instances

On three instances (24 ranks), all 18 fault scenarios and the check on resume raised the same alarm, at the same step, from the same check, and named the same ranks as on four. Only the peers changed: for example, the transient fault on rank 13 was confirmed by rank 21, on the third node. The topology check passed, and every one of the 24 ring pairs had its replayer, target, and confirming GPU on three different nodes.

## Checks of the checks

| What | Result |
|---|---|
| Fingerprints: Bit 0 flipped in one element | plain sum detects; fingerprints detect |
| Fingerprints: Bit 22 flipped in one element | plain sum detects; fingerprints detect |
| Fingerprints: Two independent bit flips | plain sum detects; fingerprints detect |
| Fingerprints: Two values swapped | plain sum **misses**; fingerprints detect |
| Fingerprints: +4,096 and −4,096 on two bit patterns | plain sum **misses**; fingerprints detect |
| Majority, all nodes: one bad copy (copies changed: [8] of [0, 8, 16, 24]) | suspects = [8] |
| Majority, all nodes: two two split (copies changed: [16, 24] of [0, 8, 16, 24]) | suspects = None |
| Majority, all nodes: no majority (copies changed: [16, 24] of [0, 8, 16, 24]) | suspects = None |
| Majority, three nodes: one bad copy (copies changed: [8] of [0, 8, 16]) | suspects = [8] |
| Majority, three nodes: three distinct (copies changed: [8, 16] of [0, 8, 16]) | suspects = None |
| Topology, real layout (4 instances) | passed; offset 4: rejected; offset 16: rejected |
| Confirmer, 3 instances | previous choice shares a node in 24 of 24 pairs; current choice in 0 |

## Healthy runs

| Run | Schedule | Length | Steps | Audit steps | Replay comparisons | Weight checks | Alarms |
|---|---|---|---|---|---|---|---|
| A | Deterministic audit every step | 45 min | 4,600 | 4,600 | 147,200 | 460 | 0 |
| A | Default-kernel audit every step | 22.5 min | 5,600 | 5,600 | 179,200 | 560 | 0 |
| A | Recommended schedule: deterministic audit and weight check every 10 steps | 45 min | 13,000 | 1,300 | 41,600 | 1,300 | 0 |
| B | Deterministic audit every step | 15 min | 1,600 | 1,600 | 38,400 | 160 | 0 |
| B | Default-kernel audit every step | 7.5 min | 2,000 | 2,000 | 48,000 | 200 | 0 |
| B | Recommended schedule: deterministic audit and weight check every 10 steps | 15 min | 4,400 | 440 | 10,560 | 440 | 0 |
| **Total** | | 2.5 h | 31,200 | 15,540 | 464,960 | 3,120 | **0** |

With 0 alarms in 15,540 audit steps, the rule of three puts a 95% upper bound of 3 / 15,540, about 1 in 5,200, on the false-alarm rate per audit step. Check 1 didn't fire on any healthy step either.

## Gradient-norm outlier test

Evaluated offline on run A's recorded local gradient norms: each rank's score on a step is |norm − median| / MAD across the 32 ranks. The threshold is calibrated on healthy steps: k = ⌈1.5 × the highest score in the first 800 steps of `healthy_production_schedule`⌉ = 160.

| Healthy run | Steps | Highest score | Steps over k (held-out steps) |
|---|---|---|---|
| healthy_det_audit_every_step | 4,600 | 476 | 28 (4,600) |
| healthy_default_audit_every_step | 5,600 | 519 | 35 (5,600) |
| healthy_production_schedule | 13,000 | 628 | 38 (12,200) |

| Fault scenario | Fault steps seen | Faulty rank's highest score | Steps over k | Caught by the workflow at step |
|---|---|---|---|---|
| nan_fwd_r13_once_nonaudit | 1 | inf | 1 | 25 |
| fwd_x1000_r13_persistent | 8 | 3.6 | 0 | 30 |
| fwd_x1000_r13_transient_at_audit | 1 | 2.5 | 0 | 30 |
| fwd_x1000_r5_persistent_faulty_replayer | 8 | 2.8 | 0 | 30 |
| fwd_x10000_r13_persistent | 8 | 3.5 | 0 | 30 |
| fwd_noise10pct_r13_persistent | 8 | 3.7 | 0 | 30 |
| dgrad_x1000_r13_persistent_det | 8 | 3.5 | 0 | 30 |
| wgrad_x1000_r13_persistent_det | 8 | 2.6 | 0 | 30 |
| wgrad_x1000_r13_persistent_default | 27 | 3.3 | 0 | not caught |
| fwd_bf16bit3_r13_persistent_det | 8 | 2.6 | 0 | 30 |
| fwd_lane_x1.1_r13_persistent_det | 8 | 4.1 | 0 | 30 |
| fwd_bf16bit3_r13_persistent_default | 8 | 3.6 | 0 | 30 |
| fwd_lane_x1.1_r13_persistent_default | 8 | 3.5 | 0 | 30 |
| two_faulty_ranks_fwd_x1000_r13_r22 | 8 | 3.2 | 0 | 30 |

## Step times (run A)

| Step | Median |
|---|---|
| Plain DDP | 157.8 ms |
| Deterministic kernels on every step, no audits | 276.6 ms |
| Non-audit step: hook and NaN/Inf check | 167.0 ms |
| Audit step, default kernels | 250.5 ms |
| Audit step, deterministic kernels | 603.5 ms |
| Fingerprints of all 953M weights, one rank | 30.4 ms |
| Plain bit sum of all weights, one rank (previous check) | 8.2 ms |
| Weight check: fingerprints, gather, and vote | 31.1 ms |

Method: step times: medians over 30 (plain, deterministic-only), 35 (non-audit) and 27 (audit) steps after warm-up; fingerprint and weight-check times: medians of 20 calls after 3 warm-up calls.

Estimated averages, from those medians, including a weight check every 10 steps (not measured as separate runs):

| Schedule | Estimated average step time (953M model, 32 H100s) | Over plain DDP |
|---|---|---|
| Deterministic audits every 10 steps | 213.7 ms | +35% |
| Default-kernel audits every 10 steps | 178.4 ms | +13% |
| Deterministic audits every 50 steps | 178.8 ms | +13% |
| Deterministic audits every 100 steps | 174.4 ms | +11% |
| Default-kernel audits every 100 steps | 170.9 ms | +8% |
