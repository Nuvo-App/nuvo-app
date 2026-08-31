# Nuvo Motion System Architecture

## End-to-End Pipeline

```
CAMERA
  → CameraImage (YUV/RGB planes)
  → CameraImageConverter (rotation, format, InputImage)
  → Google ML Kit PoseDetector (stream mode)
  → NuvoPoseFrame {points: Map<String, NuvoPosePoint>, imageWidth, imageHeight, createdAt}
  → PoseFeatureExtractor (per-frame derived signals)
  → AirborneStateTracker (temporal: baseline-relative flight detection)
  → MultiPhaseSequenceTracker (temporal: N-phase state machine)
  → MultiPhaseSequenceValidator (production: owns trackers, counts reps)
  → MotionValidationUpdate (snapshot: currentValue, status, coaching)
  → UI: AI Motion Proof Screen
```

## File Inventory

### Production Runtime (lib/features/races/ai/)

| File | Responsibility | Key Classes |
|------|---------------|-------------|
| `pose_detector_service.dart` | ML Kit pose detection, frame throttling | `PoseDetectorService` |
| `camera_image_converter.dart` | CameraImage → InputImage rotation/format | `inputImageFromCameraImage()` |
| `airborne_state_tracker.dart` | Baseline-relative bilateral ankle flight detection | `AirborneStateTracker`, `AirbornePhase` |
| `motion_validators.dart` | Per-frame feature extraction, pose conditions, production validator | `PoseFeatureExtractor`, `PoseSignal`, `BooleanPoseSignal`, `PoseCondition` hierarchy, `MultiPhaseSequenceValidator` |
| `multi_phase_sequence_tracker.dart` | N-phase ordered state machine with stability + noise grace | `MultiPhaseSequenceTracker`, `MultiPhaseSequenceDefinition`, `SequencePhaseDefinition`, `AirborneCondition`, `GroundedCondition` |
| `preset_motion/multi_phase_definitions.dart` | Jump Squat + Lunge Jump definitions | `buildJumpSquatDefinition()`, `buildLungeJumpDefinitions()` |
| `preset_motion/movement_work_order.dart` | Movement metadata, factory family routing | `MovementWorkOrder`, `MultiPhaseSequenceBehavior` |

### Data Models (lib/features/races/data/)

| File | Responsibility | Key Classes |
|------|---------------|-------------|
| `ai_motion_models.dart` | Pose frame + point data structures | `NuvoPoseFrame`, `NuvoPosePoint` |

### R&D / QA Tooling (test/motion_qa/)

| File | Responsibility |
|------|---------------|
| `body_motion_diagnostics.py` | Python QA: per-frame signal extraction, concept classification, failure taxonomy |
| `body_motion_diagnostics.json` | QA diagnostic output for all real clips |
| `synthetic_real_gap.py` | Compares synthetic vs real signal distributions |
| `synthetic_real_gap.json` | Gap analysis output |
| `motion_qa_import.py` | Real-video → pose fixture importer (YouTube → MediaPipe → JSON) |
| `real_video_sources.json` | Source URLs, metadata for real clips |
| `replay_fixture.dart` | Dart replay fixture loader (`ReplayFixture`, `RecordedFrame`, `RecordedLandmark`) |
| `replay_runner.dart` | Runs production validators on replay fixtures |
| `synthetic_fixture_factory.dart` | Generates synthetic pose sequences for JSQ, lunge jump, confusers |
| `generate_fixture_bank.dart` | Batch fixture generation + augmentation |
| `fixture_augmenter.dart` | Augmentation: jitter, dropout, translation, scale, mirror, time warp |
| `motion_diagnostics.dart` | Dart-side motion diagnostics |
| `qa_report.dart` | QA report generator |
| `tolerance_experiment_harness.dart` | Parameter sweep experiments on production detector |
| `concept_detector_v2_test.dart` | V2 concept detector + head-to-head test harness |
| `V2_CONCEPT_DETECTOR_REPORT.md` | V2 detector 8-phase report |
| `TOLERANCE_EXPERIMENT_REPORT.md` | Tolerance experiment results |
| `MOTION_QA_FINAL_REPORT.md` | Initial QA report |
| `REAL_VIDEO_QA_REPORT.md` | Real-video QA findings |
| `REAL_VIDEO_PRIMITIVE_ANALYSIS.md` | Real-video primitive analysis |

### Fixture Bank (test/motion_qa/fixtures/)

| Category | Count | Description |
|----------|-------|-------------|
| Synthetic base | 10 | JSQ clean/noisy/very_noisy/minimal + 6 confusers |
| Synthetic augmented | 100 | 10 base × 10 augmentations each |
| Real jump squat | 6 | yt_jump_squat_001-006 (29 total reps) |
| Real normal squat | 5 | yt_squat_001-005 (confuser) |
| Real deep squat | 3 | yt_deep_squat_001,003 + 1 failed import (confuser) |
| Real vertical jump | 4 | yt_vertical_jump_001-004 (confuser) |
| Real jumping jack | 2 | yt_jumping_jack_003,004 + 2 failed imports (confuser) |
| Real squat jack | 2 | yt_squat_jack_001,002 (confuser) |
| Real lunge | 3 | yt_lunge_001-003 (confuser) |
| Real lunge jump | 3 | yt_lunge_jump_001-003 (confuser) |

## Signal Extraction Layer

### PoseFeatureExtractor (per-frame, stateless)

| Signal | Computation | Used By |
|--------|------------|---------|
| `shoulderY` | avg(leftShoulder.y, rightShoulder.y) | AirborneStateTracker, conditions |
| `hipY` | avg(leftHip.y, rightHip.y) | AirborneStateTracker, conditions |
| `kneeY` | avg(leftKnee.y, rightKnee.y) | AirborneStateTracker |
| `ankleY` | avg(leftAnkle.y, rightAnkle.y) | AirborneStateTracker |
| `torsoHeight` | abs(hipY - shoulderY) clamped [0.12, 0.6] | AirborneStateTracker, ratios |
| `bodyWidth` | max(shoulderWidth, hipWidth) clamped [0.08, 0.6] | Normalization |
| `hipToKneeRatio` | (kneeY - hipY) / torsoHeight clamped [-2, 3] | STANDING/SQUAT conditions |
| `kneeAngle(left/right)` | angle(hip, knee, ankle) | Lunge conditions |
| `ankleWidth` | abs(leftAnkle.x - rightAnkle.x) | Unused in JSQ |
| `wristsAboveShoulders` | both wrists above shoulder line | Unused in JSQ |
| `wristsNearBody` | both wrists in torso range | Unused in JSQ |

### PoseSignal enum (numeric, for conditions)

| Signal | Extractor | Used In |
|--------|----------|---------|
| `hipToKneeRatio` | f.hipToKneeRatio() | STANDING (>0.60), SQUAT (<0.58) |
| `ankleWidthToBodyWidth` | f.ankleWidth / f.bodyWidth | Unused in JSQ |
| `kneeSeparationToHipWidth` | abs(lKnee.x - rKnee.x) / f.hipWidth | Unused in JSQ |
| `leftKneeAngle` | f.kneeAngle(left: true) | Lunge jump |
| `rightKneeAngle` | f.kneeAngle(left: false) | Lunge jump |

### AirborneStateTracker (temporal, stateful)

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `baselineFrames` | 4 | Stable frames to establish ankle baseline |
| `flightThresholdRatio` | 0.25 | Torso-relative flight threshold |
| `groundedToleranceRatio` | 0.10 | Torso-relative grounded tolerance |
| `minFlightThreshold` | 0.025 | Absolute floor |
| `minGroundedTolerance` | 0.015 | Absolute floor |
| `jitterTolerance` | 0.030 | Max ankle Y variation for baseline stability |
| `minLikelihood` | 0.35 | Minimum landmark confidence |
| `baselineEmaAlpha` | 0.20 | EMA weight for baseline update |

**State machine:** `awaitingBaseline → grounded ↔ airborne`

**Key property:** Both ankles must independently rise above threshold (bilateral check). Rejects one-foot lifts, squats, jumping jacks.

## Production Jump Squat Definition

```
Phases: STANDING → SQUAT → AIRBORNE → LANDING
Reset: standing AND grounded

STANDING: hipToKneeRatio > 0.60, grounded, 2 stable frames
SQUAT:    hipToKneeRatio < 0.58, 1 stable frame
AIRBORNE: AirborneStateTracker.isAirborne, 1 stable frame
LANDING:  hipToKneeRatio > 0.60, grounded, 2 stable frames

Cooldown: 3 frames
NoiseGrace: 1 frame
RequiredLandmarks: shoulders, hips, knees (NOT ankles)
```

## Known Performance

| Metric | Production | Concept V2 |
|--------|-----------|------------|
| JSQ recall (real) | 13.8% (4/29) | 44.8% (13/29) |
| Exact matches | 1/6 clips | 1/6 clips |
| Confuser false accepts | 0 | deep_squat=7, jumping_jack=8 |
| Synthetic pass rate | 75% (3/4) | 50% (2/4) |

## Bottleneck Summary

1. **AirborneStateTracker sensitivity**: 0.25 threshold too strict for real jumps (ankle rise 0.15-0.25)
2. **Camera motion contamination**: 4/6 JSQ clips have 12-19% camera translation
3. **Standing threshold**: 0.60 still misses athletic-stance start positions
4. **Temporal instability**: Real jumps have 1-2 frame flight phases at 30fps
5. **Confuser overlap**: Deep squats and jump squats share descent+ascent pattern
