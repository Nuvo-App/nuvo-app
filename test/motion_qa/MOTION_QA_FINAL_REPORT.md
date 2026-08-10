# Motion QA System — Final Report

## Overview

Built a lightweight internal motion QA/replay system for Nuvo's AI Motion Proof
verifier, focused on jump squats and lunge jumps. The system reproduces
real-world phone failure modes via synthetic noisy fixtures, measures validator
tolerance, and ships evidence-based tolerance improvements — all without
redesigning core architecture or adding new movements.

---

## What Was Built

### Infrastructure (Stages 2–6)

| Component | File | Purpose |
|---|---|---|
| Replay fixture format | `test/motion_qa/replay_fixture.dart` | JSON-compatible pose sequence with normalized landmarks, likelihoods, frame ordering, metadata |
| Replay runner | `test/motion_qa/replay_runner.dart` | Feeds fixtures through the production `MultiPhaseSequenceValidator` — same runtime path as the live camera |
| Diagnostic collector | `test/motion_qa/motion_diagnostics.dart` | Sidecar trackers mirroring validator internals for per-frame state inspection |
| Synthetic fixture factory | `test/motion_qa/synthetic_fixture_factory.dart` | Generates clean, noisy, and confuser pose sequences simulating real-world ML Kit conditions |
| Fixture augmenter | `test/motion_qa/fixture_augmenter.dart` | Produces robustness variants: jitter, dropout, time stretch/compress, duplicate, mirror, scale, translation |
| QA report generator | `test/motion_qa/qa_report.dart` | Produces JSON + Markdown confusion reports with accept rates, false accepts, failure reasons, robustness metrics |

### QA Fixture Bank (Stage 11)

- **110 fixtures** serialized to `test/motion_qa/fixtures/` (JSON)
- Manifest at `test/motion_qa/fixtures/manifest.json` with expected outcomes
- Report at `test/motion_qa/fixtures/qa_report.md`
- Generator: `flutter test test/motion_qa_generate_test.dart`
- Regression test: `flutter test test/motion_qa_regression_test.dart`

---

## Tolerance Improvements (Stage 9)

All changes are evidence-based, derived from replay failure analysis.

### 1. Relaxed landmark requirements

**File:** `lib/features/races/ai/preset_motion/multi_phase_definitions.dart`

- Removed ankles from `requiredLandmarks` for jump squat and lunge jump
- Rationale: ankles are frequently lost during airborne phases; the
  `AirborneStateTracker` handles missing ankles internally
- Phase conditions (`hipToKneeRatio`, `kneeAngle`) only need shoulders, hips, knees

### 2. Override `update` in `MultiPhaseSequenceValidator`

**File:** `lib/features/races/ai/motion_validators.dart`

- Always updates `AirborneStateTracker` (handles missing ankles safely)
- Uses relaxed `_coreLandmarks` check (shoulders, hips, knees — no ankles)
- Prevents frames with missing ankles from being discarded as `missing_landmarks`

### 3. Noise grace frames

**File:** `lib/features/races/ai/multi_phase_sequence_tracker.dart`

- Added `noiseGraceFrames` parameter to `MultiPhaseSequenceDefinition`
- Tracker tolerates N non-matching frames before resetting candidate progress
- Backward phase matches (e.g., STANDING while in AIRBORNE) consume grace
  instead of immediate reset — handles ankle dropout during airborne

### 4. Reduced airborne `stableFrames`

**File:** `lib/features/races/ai/preset_motion/multi_phase_definitions.dart`

- Jump squat airborne: 2 → 1 stable frames
- Lunge jump airborne: 2 → 1 stable frames (both left-start and right-start)
- Rationale: real-world airborne phases are brief (1–3 frames at 30fps)

### 5. Airborne tracker tolerance

**File:** `lib/features/races/ai/airborne_state_tracker.dart`

- `jitterTolerance`: 0.015 → 0.030 (real-world ML Kit noise exceeds 0.015)
- `baselineFrames`: 5 → 4 (faster baseline establishment with noisy data)

### 6. Safe `kneeAngle` with missing ankles

**File:** `lib/features/races/ai/motion_validators.dart`

- `PoseFeatureExtractor.kneeAngle` returns 180° (straight leg) when ankle is missing
- Prevents null check crash and ensures lunge conditions don't falsely match

---

## Results

### Before Tolerance Improvements (Baseline)

| Metric | Jump Squat | Lunge Jump |
|---|---|---|
| Accept rate | 43.2% | 45.5% |
| False accepts | 0 | 0 |
| Noisy 3-rep detection | 1/3 | — |
| Robustness (avg) | ~65% | ~50% |

### After Tolerance Improvements

| Metric | Jump Squat | Lunge Jump |
|---|---|---|
| Accept rate | 61.4% | 45.5% |
| False accepts | 0 | 0 |
| Noisy 3-rep detection | 3/3 ✓ | 1/2 |
| Robustness (avg) | ~80% | ~50% |

### Confuser Rejection (Preserved)

All confusers remain correctly rejected at 0 false accepts:
- normal_squat, plain_jump, jumping_jack, partial_squat

### Test Suite

- **734 tests pass** (full suite)
- **1 pre-existing failure** (`arena_screen_golden_test.dart` — missing font file, unrelated)
- **0 new warnings/errors** from `flutter analyze --no-fatal-infos`

---

## Files Changed (Production)

| File | Change |
|---|---|
| `lib/features/races/ai/airborne_state_tracker.dart` | `jitterTolerance` 0.015→0.030, `baselineFrames` 5→4 |
| `lib/features/races/ai/motion_validators.dart` | Override `update` with relaxed landmarks, safe `kneeAngle` |
| `lib/features/races/ai/multi_phase_sequence_tracker.dart` | `noiseGraceFrames` + backward-phase grace logic |
| `lib/features/races/ai/preset_motion/multi_phase_definitions.dart` | Remove ankles from `requiredLandmarks`, `noiseGraceFrames: 1`, airborne `stableFrames: 1` |

## Files Changed (Test-only)

| File | Change |
|---|---|
| `test/batch_b_identity_test.dart` | Updated incomplete-sequence test for new `stableFrames: 1` |
| `test/motion_qa/synthetic_fixture_factory.dart` | Recalibrated poses, realistic airborne tuck, per-ankle dropout |
| `test/motion_qa/motion_diagnostics.dart` | Fixed double-update of sidecar airborne tracker |

## Files Created (Test-only)

| File | Purpose |
|---|---|
| `test/motion_qa/replay_fixture.dart` | Fixture format + loader |
| `test/motion_qa/replay_runner.dart` | Replay through production validator |
| `test/motion_qa/motion_diagnostics.dart` | Diagnostic collector |
| `test/motion_qa/synthetic_fixture_factory.dart` | Synthetic pose generator |
| `test/motion_qa/fixture_augmenter.dart` | Augmentation variants |
| `test/motion_qa/qa_report.dart` | QA report generator |
| `test/motion_qa/generate_fixture_bank.dart` | Fixture bank generator (script) |
| `test/motion_qa_generate_test.dart` | Fixture bank generator (test runner) |
| `test/motion_qa_baseline_test.dart` | Baseline QA test with assertions |
| `test/motion_qa_regression_test.dart` | Permanent regression test (strict + measurement tiers) |
| `test/motion_qa/fixtures/` | 110 JSON fixture files + manifest + report |

---

## Remaining Work

- **Stage 12** (medium priority): Add motion concept metadata to 13 movements
- **Lunge Jump noisy detection**: Still 1/2 on noisy fixtures — needs further
  investigation of lunge phase conditions under noise
- **Time compress robustness**: 50% for both movements — time compression
  reduces below `stableFrames` thresholds
