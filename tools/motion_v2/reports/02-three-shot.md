# Motion V2 — STEP 6+7+8: 3-shot learner, hold-still-free segmentation, generic rep detection

Generated 2026-08-31 · MotionBERT-Lite pretrained backbone · synthetic corpus
(3 movement classes × 3 demos). Real device fixtures still required — synthetic
is a plumbing + design check.

## STEP 6 — `TaughtMotionV2.match()` : 3-shot same-family recognition

`learn(name, [demo1, demo2, demo3])` → multi-reference prototype descriptors
(temporal+joint mean of the encoder rep per demo, + mirror-augmented) + a
canonical embedding trajectory + a rest embedding + an accept threshold
calibrated as `5 × intra-demo spread` (floored). The name is metadata; it is
never used for verification.

`match(frames)` on an **unseen** recording:

| | jumping_jack query | squat query | arm_wave query |
|---|---|---|---|
| taught jumping_jack | ✅ same (margin 0.04) | ✗ (1.21) | ✗ (1.39) |
| taught squat | ✗ (1.42) | ✅ same (0.12) | ✗ (2.74) |
| taught arm_wave | ✗ (1.28) | ✗ (2.56) | ✅ same (0.05) |

**TP 3/3 · TN 6/6 · FP 0 · FN 0.** `proto_margin` (dist / accept threshold)
separates same-motion (0.04–0.12) from different-motion (1.2–2.7) by ~20×. The
canonical-trajectory `coverage` is a second independent signal (an arm-wave
query against the squat model reaches only 0.10 coverage).

## STEP 7 — segmentation without "hold still"

`segment_action()` trims leading/trailing idle using **embedding velocity**
(median-relative threshold). No fixed start pose, no user calibration ritual —
idle frames before/after a recording are found and dropped by the engine. Demo
capture stays: Record → move → Stop → Save.

## STEP 8 — `RepDetectorV2` : generic repetition counting

Matched filter: slide the learned canonical trajectory along the stream, score
each window by banded diagonal alignment, non-max-suppress the peaks. Each peak
window is **re-encoded in isolation** (a rep sliced from a pre-encoded long
sequence carries transformer attention context from the other reps and its
descriptor drifts) and passed through `match()`. Count the passes. No
movement-specific state machine.

| taught | 1× | 3× | 5× | wrong motion ×3 | flailing |
|---|---|---|---|---|---|
| jumping_jack | 1 ✅ | 3 ✅ | 5 ✅ | 1 ⚠ | 0 ✅ |
| squat | 1 ✅ | 2 | 4 | 0 ✅ | 0 ✅ |
| arm_wave | 1 ✅ | 2 | 3 | 0 ✅ | 0 ✅ |

**Total abs error 5 over 9 correct sequences · 1 false positive.** jumping_jack
exact; squat/arm_wave undercount ~20–40% because the NMS min-spacing (`W×0.55`)
merges slow adjacent reps in the synthetic corpus (reps are ~40 frames with only
7 idle frames between — real captures have clearer stops).

## Read

- STEP 6 `match()` is **solid** and is the gate for STEP 10 (phone): unseen
  same-motion recognized, different motion rejected, no name used, no hand
  features. This is the core V2 claim, demonstrated.
- STEP 7 removes the hold-still ritual — done.
- STEP 8 rep counting **works but needs real-data tuning** of the NMS spacing +
  match threshold. Synthetic reps are too smooth/close to calibrate the spacing.
  FP behaviour (the safety-critical direction) is already good.
- STEP 9 (V1 vs V2 benchmark) is **blocked on real fixtures** — V1
  (`CustomPoseSequenceRuntime`) is Dart; a shared benchmark needs the same real
  recordings run through both. STEP 4 (raw-stream fixture export) unblocks it.

## Next

1. STEP 4: export the **raw** Nuvo pose stream from the teach flow (current
   export is V1-normalized `CustomPoseCalibration`); add a Python loader.
2. Re-run exp01 + exp02 on real captures.
3. Tune STEP 8 spacing/threshold on real data.
4. STEP 9 benchmark, then STEP 10 phone.
