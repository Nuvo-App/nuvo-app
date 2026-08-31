# Motion V2 — STEP 6+8: 3-shot learner + generic rep detection (synthetic)

Generated 2026-08-31 12:16 · MotionBERT-Lite · 3 demos/movement.

## match() — same-family recognition

| taught | query | is_same_family | score | proto_dist | traj_sim | coverage |
|---|---|---|---|---|---|---|
| jumping_jack | jumping_jack | False | 0.89 | 0.002 | 0.995 | 1.00  ❌ |
| jumping_jack | squat | False | 0.50 | 0.072 | 0.998 | 1.00 |
| jumping_jack | arm_wave | False | 0.50 | 0.083 | 0.996 | 1.00 |
| squat | jumping_jack | False | 0.50 | 0.085 | 0.995 | 1.00 |
| squat | squat | False | 0.56 | 0.007 | 1.000 | 1.00  ❌ |
| squat | arm_wave | False | 0.50 | 0.164 | 0.994 | 1.00 |
| arm_wave | jumping_jack | False | 0.50 | 0.077 | 0.994 | 1.00 |
| arm_wave | squat | False | 0.50 | 0.153 | 0.994 | 1.00 |
| arm_wave | arm_wave | True | 0.94 | 0.003 | 0.998 | 1.00 |

match: TP=1 TN=6 FP=0 FN=2

## count_reps() — generic repetition detection

| taught | sequence | expected | detected |
|---|---|---|---|
| jumping_jack | 1× jumping_jack | 1 | 1 |
| jumping_jack | 3× jumping_jack | 3 | 3 |
| jumping_jack | 5× jumping_jack | 5 | 5 |
| jumping_jack | 3× squat (wrong) | 0 | 0 |
| jumping_jack | random flailing | 0 | 3  ❌ |
| squat | 1× squat | 1 | 1 |
| squat | 3× squat | 3 | 0  ⚠ |
| squat | 5× squat | 5 | 0  ⚠ |
| squat | 3× jumping_jack (wrong) | 0 | 3  ❌ |
| squat | random flailing | 0 | 0 |
| arm_wave | 1× arm_wave | 1 | 1 |
| arm_wave | 3× arm_wave | 3 | 0  ⚠ |
| arm_wave | 5× arm_wave | 5 | 0  ⚠ |
| arm_wave | 3× jumping_jack (wrong) | 0 | 15  ❌ |
| arm_wave | random flailing | 0 | 7  ❌ |

rep counting: total abs error over 9 correct sequences = 16; false positives on wrong-motion + flailing = 28

_(runtime 5.3s)_

## Read — v1 of the matcher/detector: partial

**Works:** `match()` never confuses different motions (FP=0, TN=6/6); `proto_dist`
separates same-motion (0.002–0.007) from cross-motion (0.07–0.16) by 10–20×.
1-rep counting correct. jumping_jack multi-rep correct.

**Broken:**
1. `match()` FN=2 — `accept_proto_dist` threshold (mean+2.5·std of 3 demos'
   pairwise distances, with mirror-aug shrinking std) is absurdly tight (~0.002).
   The *signal* is fine; the threshold derivation is wrong. Fix: relative margin
   with a sane floor, not std-scaled off 3 samples.
2. `RepDetectorV2` — trajectory similarity saturates ~0.99 for everything (the
   per-frame joint-mean embedding is too smooth), so the progress state machine
   fires on anything: squat/arm_wave multi-rep → 0 (index stalls), cross-motion
   and flailing → 3–15 false reps.

**Next architecture (not V1 tuning):** replace the streaming progress state
machine with **burst segmentation + per-burst `match()`**: split the stream at
embedding-velocity valleys into motion bursts, run `match()` on each, count the
bursts that pass. Generic, reuses the strong `proto_dist` signal, no bespoke
state. Also try the full (T,17,512) rep (keeps which joint moved) instead of the
joint-mean (T,512).
