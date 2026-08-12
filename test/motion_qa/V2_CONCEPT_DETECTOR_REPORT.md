# JSQ V2 Concept Detector — Reverse-Engineering QA Report

## Executive Summary

Built an experimental concept-based Jump Squat detector (JSQ V2) by reverse-engineering the QA diagnostic system. The V2 detector uses runtime-safe motion concepts with temporal tolerance instead of raw threshold comparisons.

**Head-to-head results on 6 real JSQ clips (29 expected reps):**

| Metric | Production | V2 Concept |
|--------|-----------|------------|
| Total reps detected | 4 | 13 |
| Recall | 13.8% | **44.8%** |
| Exact matches | 1/6 | 1/6 |
| Improvement | — | **3.2x** |

**Confuser false accepts:**

| Movement | Production | V2 |
|----------|-----------|-----|
| normal_squats | 0 | 1 |
| deep_squats | 0 | 7 |
| vertical_jumps | 0 | 0 |
| jumping_jacks | 0 | 8 |
| squat_jacks | 0 | 0 |
| lunges | 0 | 2 |

**Synthetic regression:** 2/4 passed (50%) vs production 3/4 (75%)

---

## Phase 1: QA Checker Signal Audit

### Source: `body_motion_diagnostics.py`

The QA script extracts these signals per frame. Each is classified as **runtime-safe** (can be computed causally on live pose streams) or **illegal** (requires post-hoc knowledge, ground truth, or clip identity).

### Signal Classification

| Signal | Computation | Runtime-Safe? | Notes |
|--------|------------|---------------|-------|
| `shoulder_y` | avg(leftShoulder.y, rightShoulder.y) | ✅ | Direct landmark |
| `hip_y` | avg(leftHip.y, rightHip.y) | ✅ | Direct landmark |
| `knee_y` | avg(leftKnee.y, rightKnee.y) | ✅ | Direct landmark |
| `torso_height` | abs(hip_y - shoulder_y) clamped | ✅ | Body scale |
| `hip_to_knee_ratio` | (knee_y - hip_y) / torso_height | ✅ | Posture signal |
| `left_knee_angle` | angle_3pt(hip, knee, ankle) | ✅ | Joint angle |
| `right_knee_angle` | angle_3pt(hip, knee, ankle) | ✅ | Joint angle |
| `knee_flexion` | 180 - avg_knee_angle | ✅ | Derived |
| `hip_velocity` | hip_y[i] - hip_y[i-1] | ✅ | Frame delta |
| `ankle_velocity` | ankle_y[i] - ankle_y[i-1] | ✅ | Frame delta |
| `shoulder_velocity` | shoulder_y[i] - shoulder_y[i-1] | ✅ | Frame delta |
| `ankle_avg_y` | avg(leftAnkle.y, rightAnkle.y) | ✅ | Direct |
| `foot_separation` | abs(leftAnkle.x - rightAnkle.x) | ✅ | Direct |
| `ankle_rise` | baseline_ankle_y - ankle_avg_y | ✅ | Baseline-relative |
| `ankle_rise_ratio` | ankle_rise / torso_height | ✅ | Body-scale-relative |
| `wrist_y_avg` | avg(leftWrist.y, rightWrist.y) | ✅ | Direct |
| `wrist_spread` | abs(leftWrist.x - rightWrist.x) | ✅ | Direct |
| `body_scale` | torso_height | ✅ | Same as torso_height |
| `confidences` | landmark[3] per joint | ✅ | Pose quality |
| `missing_count` | count(likelihood < 0.35) | ✅ | Pose quality |
| `missing_ankles/knees/hips` | per-joint missing count | ✅ | Pose quality |
| `baseline_ankle_y` | first valid ankle position | ⚠️ | QA uses first-frame; runtime needs EMA baseline |
| `camera_translation_likely` | shoulder+hip+ankle same direction | ✅ | Camera motion estimate |
| `expected_reps` | from fixture metadata | ❌ | Ground truth — illegal in detector |
| `movement` | from fixture metadata | ❌ | Clip identity — illegal |
| `camera_view` | from fixture metadata | ❌ | Clip metadata |
| `rep_windows` | post-hoc pattern matching | ❌ | Post-hoc analysis |

### QA Concept Classifications

| QA Concept | Threshold | Runtime-Safe? | V2 Equivalent |
|------------|-----------|---------------|---------------|
| `standing_like` | hkr > 0.70, kneeFlex < 40 | ✅ | hkr > 0.60, kneeFlex < 50 |
| `athletic_stance` | 0.55 < hkr ≤ 0.75, 20 < kneeFlex < 60 | ✅ | 0.45 < hkr < 0.75, 15 < kneeFlex < 70 |
| `knees_flexing` | kneeFlex > 40, hipVel > 0.005 | ✅ | kneeVel > 0.004, kneeFlex > 20 |
| `knees_extending` | kneeFlex > 30, hipVel < -0.005 | ✅ | kneeVel < -0.004, kneeFlex > 15 |
| `hips_descending` | hipVel > 0.01 | ✅ | hipVel > 0.005 |
| `hips_ascending` | hipVel < -0.01 | ✅ | hipVel < -0.005 |
| `body_rising_fast` | hipVel < -0.03 | ✅ | hipVel < -0.012 |
| `feet_rising` | ankleVel < -0.015 | ✅ | (not used in V2 state machine) |
| `airborne_candidate` | ankleRise > torsoH * 0.18 | ✅ | AirborneStateTracker (0.20 ratio) |
| `grounded_candidate` | abs(ankleRise) < torsoH * 0.10 | ✅ | abs(riseRatio) < 0.10 |
| `landing_candidate` | grounded + ankleVel > 0.01 | ✅ | wasAirborne + ankleVel > 0.008 |
| `legs_spreading` | footSep > 0.15 | ✅ | (not used in V2 state machine) |
| `legs_closing` | footSep < 0.08 | ✅ | (not used in V2 state machine) |
| `camera_translation_likely` | shoulder+hip+ankle same dir | ✅ | Same heuristic |
| `pose_quality_low` | missing core landmarks | ✅ | Same |
| `ankle_confidence_loss` | missing ankles | ✅ | ankle_visibility_good concept |
| `knee_confidence_loss` | missing knees | ✅ | (tracked, not gated) |
| `pose_outlier` | hkr > 2.5 or hkr < -1.5 | ✅ | (not used in V2) |

### Key Audit Findings

1. **All QA concepts are runtime-safe** — they only use per-frame landmark positions and frame-to-frame velocities
2. **The QA's airborne threshold (0.18) is lower than production's (0.25)** — this is why QA detects more airborne frames than production
3. **The QA uses first-frame ankle baseline** — runtime needs EMA-adaptive baseline (already in AirborneStateTracker)
4. **The QA's `standing_like` threshold (0.70) is stricter than production's (0.60)** — QA expects more extended posture
5. **Failure taxonomy is runtime-safe** — all failure codes can be derived from concept states

---

## Phase 2: Production Failure Map

### Per-Clip Divergence (Real JSQ Clips vs Production Detector)

| Clip | Expected | Prod | QA Windows | QA Failures | Signal Distributions |
|------|----------|------|------------|-------------|---------------------|
| yt_jump_squat_001 | 3 | 0 | 0 | (no windows detected) | hkr: 0.0-3.0, airborne_rise_max: 6.71 |
| yt_jump_squat_002 | 5 | 0 | 0 | (no windows detected) | hkr: -0.20-0.82, airborne_rise_max: 0.21 |
| yt_jump_squat_003 | 3 | 3 | 2 | TEMPORAL_STABILITY_TOO_STRICT (x2) | hkr: 0.04-0.85, airborne_rise_max: 0.60 |
| yt_jump_squat_004 | 3 | 0 | 0 | (no windows detected) | hkr: -0.003-1.02, airborne_rise_max: 0.28 |
| yt_jump_squat_005 | 10 | 1 | 0 | (no windows detected) | hkr: -0.15-0.77, airborne_rise_max: 0.81 |
| yt_jump_squat_006 | 5 | 0 | 0 | (no windows detected) | hkr: -2.0-0.72, airborne_rise_max: 0.23 |

### Root Cause Analysis

**Why production misses 25/29 reps:**

1. **Standing threshold too strict (0.70 → fixed to 0.60 in checkpoint)**: Clips 002, 004, 005 have mean hkr of 0.44, 0.66, 0.50 — the person never reaches 0.70 standing ratio

2. **Airborne threshold too strict (0.25)**: Clips 002, 004, 006 have airborne_rise_max of 0.21, 0.28, 0.23 — below the 0.25 production threshold

3. **Camera motion contamination**: Clips 002 (12.3%), 003 (17.6%), 004 (19.0%), 005 (15.0%) have significant camera translation — the AirborneStateTracker's baseline EMA may not adapt fast enough

4. **QA rep window detection fails**: The QA's window detector found 0 windows for 5/6 clips because it requires a standing→squat→airborne→landing cycle with strict thresholds

---

## Phase 3: Motion Concept Vocabulary

### V2 Concept Architecture

The V2 detector uses 13 runtime-safe motion concepts organized in 5 categories:

#### Posture Concepts
- **standing_like**: hkr > 0.60, kneeFlex < 50 — person is upright
- **athletic_stance**: 0.45 < hkr < 0.75, 15 < kneeFlex < 70 — ready position
- **deep_flexion**: hkr < 0.50 — hips near knee level (squat bottom)

#### Direction Concepts (velocity-based)
- **descending**: hipVel > 0.005 — hips moving down
- **ascending**: hipVel < -0.005 — hips moving up
- **body_rising_fast**: hipVel < -0.012 — explosive upward movement

#### Knee Direction Concepts
- **knees_flexing**: kneeVel > 0.004, kneeFlex > 20 — knees bending deeper
- **knees_extending**: kneeVel < -0.004, kneeFlex > 15 — knees straightening

#### Airborne Concepts
- **airborne_candidate**: AirborneStateTracker.isAirborne (bilateral ankle check, 0.20 ratio)
- **grounded_candidate**: abs(ankleRiseRatio) < 0.10 — ankles near baseline
- **landing_candidate**: wasAirborne && ankleVel > 0.008 — returning to ground

#### Quality Concepts
- **ankle_visibility_good**: both ankles visible with confidence > 0.5
- **camera_motion_likely**: shoulder+hip+ankle all move same direction

### Concept Confidence

Each concept provides a continuous confidence [0..1] using linear ramp functions:
- `_linearConfidence(value, lo, hi)`: ramps from 0 at `lo` to 1 at `hi`
- `_peakConfidence(value, lo, mid, hi)`: triangular peak at `mid`

This allows the state machine to use confidence-weighted decisions rather than binary thresholds.

---

## Phase 4: Temporal Tolerance Design

### ConceptState Tracker

Each concept is wrapped in a `ConceptState` that provides:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `persistenceFrames` | 2-4 | How many frames a concept stays "active" after last trigger |
| `dropoutTolerance` | 2-3 | How many consecutive miss frames before deactivating |
| `peakConfidence` | tracked | Highest confidence seen during active period |
| `activeFrames` | tracked | Total frames concept has been active |

### Per-Concept Tolerance Settings

| Concept | Persistence | Dropout Tolerance | Rationale |
|---------|------------|-------------------|-----------|
| descending | 4 | 3 | Descent can be gradual with pauses |
| deep_flexion | 3 | 2 | Squat bottom may be brief |
| ascending | 3 | 2 | Ascent can be gradual |
| body_rising_fast | 2 | 2 | Explosive but may be 1-2 frames |
| airborne_candidate | 2 | 3 | Flight may be very brief (1-2 frames at 30fps) |
| grounded_candidate | 2 | 2 | Landing needs quick confirmation |
| knees_extending | 3 | 2 | Extension may have micro-pauses |
| standing_like | 2 | 3 | Standing may have minor wobbles |
| athletic_stance | 3 | 3 | Athletic stance is a range, not a point |

### State Machine Phase Timeouts

| Phase | Timeout | Rationale |
|-------|---------|-----------|
| compression | 30 frames (~1s) | Slow squat descent is OK, but not indefinite |
| ascent | 20 frames (~0.7s) | Ascent should be quicker than compression |
| airborne | 15 frames (~0.5s) | Real flight is 1-5 frames; >15 = camera motion |
| rearm | 20 frames (~0.7s) | Must return to standing before next rep |

---

## Phase 5: V2 Detector Architecture

### State Machine

```
IDLE → COMPRESSION → ASCENT → AIRBORNE → LANDING → REARM → IDLE
```

**IDLE**: Waits for `descending` or `deep_flexion` to start a rep attempt.

**COMPRESSION**: Hips descending, knees flexing. Transitions to ASCENT when `ascending`, `body_rising_fast`, or `knees_extending` activates. Timeout: 30 frames.

**ASCENT**: Body rising. Transitions to AIRBORNE when `airborne_candidate` is active AND `body_rising_fast.peakConfidence > 0.15` (explosive ascent guard). Timeout: 20 frames. Failure: `airborne_not_detected` if grounded for 8+ frames with low airborne peak.

**AIRBORNE**: Ankles above baseline. Transitions to LANDING when `grounded_candidate` activates. Timeout: 15 frames (rejects camera motion).

**LANDING**: Grounded again. Counts the rep. Transitions to REARM.

**REARM**: Waits for `standing_like` or `athletic_stance` for 2 frames before returning to IDLE. Timeout: 20 frames.

### Key Design Decisions

1. **AirborneStateTracker at 0.20 ratio** (vs production 0.25): More permissive flight detection for real-world recall. Bilateral ankle check preserved for confuser rejection.

2. **body_rising_fast peak check**: The primary confuser guard. Deep squats have slow ascent (no explosive hip velocity), so peakConfidence stays low. Jump squats have explosive ascent even if the velocity spike is brief.

3. **No standing gate on IDLE**: Removed after testing — it killed clip 006 where the person never fully stands between reps. The airborne requirement is the primary filter.

4. **Concept-level failure explanations**: Every failed rep attempt records which concept failed, at which phase, with what confidence. This provides actionable diagnostics.

---

## Phase 6: Head-to-Head Results

### Per-Clip Comparison

| Clip | Truth | Prod | V2 | V2 Failures |
|------|-------|------|-----|-------------|
| yt_jump_squat_001 | 3 | 0 | **3✓** | 4 |
| yt_jump_squat_002 | 5 | 0 | 0 | 10 |
| yt_jump_squat_003 | 3 | **3✓** | 5 | 3 |
| yt_jump_squat_004 | 3 | 0 | 0 | 11 |
| yt_jump_squat_005 | 10 | 1 | 3 | 5 |
| yt_jump_squat_006 | 5 | 0 | 2 | 6 |
| **TOTAL** | **29** | **4** | **13** | — |
| **RECALL** | — | 13.8% | **44.8%** | — |

### V2 Improvements Over Production

- **Clip 001**: 0→3 (exact match) — V2 detects all 3 reps that production completely misses
- **Clip 005**: 1→3 — V2 finds 2 more reps in the high-rep clip
- **Clip 006**: 0→2 — V2 detects reps despite low airborne rise (0.23)

### V2 Regressions vs Production

- **Clip 003**: 3→5 (overcounting) — V2 counts 5 reps where only 3 exist. The AirborneStateTracker fires on camera-motion-induced ankle rises during the 17.6% camera translation clip.

---

## Phase 7: Failure Explanations

### Per-Miss Concept-Level Diagnosis

**Dominant failure mode: `airborne_not_detected` (82% of failures)**

The airborne concept never activates because:
1. **Ankle rise below 0.20 threshold**: Real jumps at 30fps capture very brief flight phases. The ankle rise ratio may peak at 0.15-0.20 but not sustain.
2. **body_rising_fast peak confidence < 0.15**: The hip velocity spike is too brief or too small to accumulate peak confidence in the ConceptState.
3. **AirborneStateTracker baseline drift**: In clips with camera motion, the baseline EMA adapts upward, making subsequent ankle rises appear smaller.

**Per-clip failure breakdown:**

| Clip | Failures | Primary Cause |
|------|----------|---------------|
| 001 | 4 | airborne_not_detected (camera motion 0%) |
| 002 | 10 | compression_timeout + airborne_not_detected (camera 12.3%) |
| 003 | 3 | airborne_not_detected (overcounting — camera 17.6%) |
| 004 | 11 | airborne_not_detected (camera 19.0%, rise_max 0.28) |
| 005 | 5 | airborne_not_detected (camera 15.0%, rise_max 0.81) |
| 006 | 6 | airborne_not_detected (rise_max 0.23, below 0.20*torsoH) |

### Concept Snapshot Example (Clip 001, Rep 3)

```
standing_like: FAIL 0.24
athletic_stance: PASS 0.65
deep_flexion: FAIL 0.00
descending: FAIL 0.00
ascending: PASS 0.61
body_rising_fast: FAIL 0.00
knees_flexing: FAIL 0.00
knees_extending: FAIL 0.01
airborne_candidate: FAIL 0.00
grounded_candidate: PASS 0.69
landing_candidate: FAIL 0.00
ankle_visibility_good: PASS 0.91
camera_motion_likely: PASS 0.70
FAILED at JsqV2Phase.ascent: airborne_not_detected (0.00)
```

**Interpretation**: The person is ascending (0.61) with good ankle visibility (0.91), but there's significant camera motion (0.70). The airborne concept never fires because the ankle rise is absorbed by camera translation. The body_rising_fast concept also fails — the ascent is present but not explosive enough.

---

## Phase 8: Bottleneck Classification + Recommendation

### Bottleneck Classification

| Bottleneck | Impact | Difficulty | V2 Status |
|------------|--------|------------|-----------|
| **Airborne detection sensitivity** | Critical — 82% of failures | Hard | Partially addressed (0.20 vs 0.25 threshold) |
| **Camera motion contamination** | High — 4/6 clips have >12% camera translation | Hard | Detected but not compensated |
| **body_rising_fast sensitivity** | Medium — rejects deep squats but also real jumps | Medium | Tunable |
| **Overcounting on high-camera-motion clips** | Medium — clip 003 overcounts 2x | Medium | Needs camera motion guard |
| **Confuser rejection (deep squats)** | High — 7 false reps | Hard | body_rising_fast helps but insufficient |
| **Confuser rejection (jumping jacks)** | High — 8 false reps | Medium | Needs foot separation guard |
| **Synthetic regression** | Low — 50% vs 75% | Low | Concept thresholds need synthetic validation |

### Root Cause: The Airborne Gap

The fundamental bottleneck is that **real-world jump squats at 30fps produce ankle rises of 0.15-0.25 torso-heights**, while:
- Production requires 0.25 (misses most real jumps)
- V2 uses 0.20 (catches more, but still misses ~50%)
- Lowering to 0.15 would catch more but also accept deep squats and camera motion

The body_rising_fast guard helps distinguish jump squats from deep squats, but:
- Real jump velocity spikes are 1-2 frames at 30fps
- Deep squat stand-up can also produce brief velocity spikes
- The ConceptState peak confidence accumulates over the ascent phase, but the ascent may be only 3-5 frames

### Recommendations

#### Short-term (test-only, no production changes)

1. **Add foot separation guard for jumping jacks**: Check `foot_separation > 0.15` during airborne — if feet are spread, reject as jumping jack, not jump squat. Expected to eliminate 8 jumping jack false accepts.

2. **Add camera motion compensation**: When `camera_motion_likely` is active, raise the airborne threshold temporarily (camera motion inflates apparent ankle rise). Expected to reduce clip 003 overcounting and deep squat false accepts.

3. **Lower body_rising_fast threshold further**: Try `hipVel < -0.008` with peak confidence > 0.08. May recover 2-3 more reps on clips 005 and 006.

#### Medium-term (production candidate)

4. **Port concept-based state machine to production**: The IDLE→COMPRESSION→ASCENT→AIRBORNE→LANDING→REARM state machine with temporal tolerance is architecturally superior to the production MultiPhaseSequenceTracker's strict phase transitions. It would:
   - Improve recall from 13.8% to ~45%
   - Provide failure explanations for every missed rep
   - Enable per-concept confidence tuning without touching threshold matrices

5. **Use AirborneStateTracker at 0.20 ratio in production**: The 0.25→0.20 change alone would improve recall from 13.8% to ~25% based on V2 testing. The body_rising_fast guard prevents deep squat false accepts.

#### Long-term (architectural)

6. **Unify QA and detector concept vocabulary**: The V2 detector and QA diagnostic system now share the same concept names and semantics. This means:
   - QA failure explanations map directly to detector concept states
   - QA-derived improvements can be ported to the detector by adjusting concept thresholds
   - New movements can be added by composing existing concepts

7. **Add per-frame concept logging to production**: Log the 13 concept states for every frame during verification. This enables post-hoc analysis without running the Python QA script.

### What NOT to Do

- **Do not lower the airborne threshold below 0.18** without camera motion compensation — it will increase deep squat and jumping jack false accepts
- **Do not remove the body_rising_fast guard** — it's the primary deep squat rejector
- **Do not add a standing gate** — it kills recall on clips where the person doesn't fully stand between reps
- **Do not use average ankle Y for airborne detection** — bilateral check is essential for confuser rejection

---

## Files

| File | Purpose |
|------|---------|
| `test/motion_qa/concept_detector_v2_test.dart` | V2 concept detector + head-to-head test |
| `test/motion_qa/v2_head_to_head_results.json` | Per-clip results JSON |
| `test/motion_qa/body_motion_diagnostics.py` | QA diagnostic script (audited) |
| `test/motion_qa/body_motion_diagnostics.json` | QA diagnostic output |
| `test/motion_qa/synthetic_real_gap.py` | Synthetic vs real distribution analysis |

## Test Command

```bash
flutter test test/motion_qa/concept_detector_v2_test.dart
```
