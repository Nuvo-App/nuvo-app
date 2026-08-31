# Race, proof, movement, and AI Motion Proof

## Race domain

Race identity and display logic live in `lib/features/races/domain/`; transport models and endpoint calls live in `data/`; screens and shared mutations live in `presentation/`.

Important concepts in the current model include finish-line format, scoring rule, target value/unit, proof requirement, proof review mode, visibility, recurrence, participants, recent proofs, final standings, and submission results. Preserve backend field names and defaults when adding fields.

## Proof types

Nuvo supports manual, photo, note, link, daily check-in, AI Motion Proof, and custom pose flows as represented by the current API/domain code. A UI label must match the actual server behavior. Never label a proof as verified before the backend/runtime says it is verified.

## AI Motion Proof pipeline

```text
camera
  → platform frame conversion
    → ML Kit pose detector
      → landmark smoothing / phase trackers
        → movement validator or custom-pose runtime
          → NuvoVerifyOutput
            → proof payload
              → Worker review/scoring
```

Key files:

- `pose_detector_service.dart`: ML Kit bridge.
- `camera_image_converter.dart`: platform pixel conversion.
- `pose_landmark_smoother.dart`: temporal smoothing.
- `motion_validators.dart`: verification thresholds/state/confidence.
- `verifier_runtime.dart`, `multi_phase_sequence_tracker.dart`, and `airborne_state_tracker.dart`: runtime coordination.
- `custom_pose/`: taught movement calibration/specification/runtime.
- `ai_motion_proof_screen.dart` plus platform variants: camera lifecycle and user-facing flow.
- `presentation/widgets/movement_demo.dart`: non-verification instructional animation.

## Non-negotiable safety rules

- Do not bypass pose detection, alter confidence, or turn a failed validation into success.
- Do not change thresholds casually; use motion QA fixtures and regression tests.
- Do not change camera disposal/order without testing on the affected platform.
- Treat false positives and false negatives as product correctness issues, not cosmetic issues.
- AI output is activity verification, not medical advice, diagnosis, or a guarantee of safe exercise.

## Required movement validation checks

Run the focused validator/runtime tests and motion QA regression suite when touching movement code. Include clean, noisy, missing-landmark, mirrored, dropped-frame, and hard-negative fixtures. A passing widget test alone is not evidence that camera verification is correct.
