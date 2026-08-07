# Teach Nuvo MVP Plan

This plan is for making Teach Nuvo reliable enough to demo and iterate without
pretending it is a general custom-movement trainer.

## Product Decision

Teach Nuvo MVP should be:

> Record what you do three times. Nuvo learns the shared pose pattern for a
> short, supported movement family.

Teach Nuvo MVP should not be:

> Train a universal movement model from three examples.

The current codebase is already closest to a template-matching MVP:

- `SingleSessionTeachingCapture` records examples and builds a calibration.
- `CustomPoseSequenceBuilder` selects active pose features and builds a
  canonical sequence.
- `CustomPoseSequenceRuntime` verifies a live movement against that sequence.
- `RaceComposerScreen` can route custom drafts through `createCustomRace`.

That architecture is the right MVP direction. Do not replace it with video
upload, LLM calls, or on-device custom model training for the first version.

## External Research Notes

ML Kit Pose Detection is appropriate as the MVP primitive because it is
on-device, cross-platform, and designed for real-time body pose tracking. It
returns 33 body landmarks plus per-landmark `InFrameLikelihood` confidence.

Important constraints from the platform docs:

- Pose Detection is beta, so Nuvo should isolate pose contracts behind local
  adapters and tests.
- The base SDK is intended for real-time performance; accurate mode trades speed
  for precision.
- ML Kit works best with the full body visible, but it can detect partial body
  poses. Missing landmarks should not automatically fail a recording.
- It detects one prominent person. Teach Nuvo should guide users toward one
  person in frame, not support group movement.
- Real-time use should throttle detector calls and rendering updates.
- MediaPipe Pose uses a detector-tracker pipeline where tracking reuses prior
  landmarks between frames. Nuvo should preserve stream lifecycle and avoid
  restarting detection unnecessarily.

References:

- ML Kit Pose Detection overview:
  https://developers.google.com/ml-kit/vision/pose-detection
- ML Kit Android pose detection performance and stream mode:
  https://developers.google.com/ml-kit/vision/pose-detection/android
- MediaPipe Pose Landmarker:
  https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
- MediaPipe Pose pipeline overview:
  https://github.com/google-ai-edge/mediapipe/blob/master/docs/solutions/pose.md

## MVP Scope

Ship support for short, repeatable, single-person movements that are visible in
camera and have clear landmark motion.

Supported in MVP:

- Upper-body gestures: wave, arm raise, overhead reach, punch-like motions.
- Lower-body patterns when visible: squat-like and lunge-like movements.
- One to three second clips.
- Three saved examples.
- Live test using the real `CustomPoseSequenceRuntime`.
- Race creation using the real `CustomPoseVerifierSpec`.

Not supported in MVP:

- Arbitrary dance routines.
- Fast tiny finger gestures.
- Multi-person movements.
- Movements where the body part is usually outside frame.
- Learning from uploaded video.
- LLM movement interpretation.
- Training a new ML model on-device from three examples.
- Server-side custom verifier creation.

## Reliability Strategy

### 1. Make Capture Boring

Capture should be tolerant before recording and strict after recording.

Rules:

- Do not block recording because hips, knees, or ankles are missing.
- Do not require full body for all movements.
- Do not show "Step into frame" as a hard pre-record blocker.
- Record first, analyze after.
- Reject after recording only when:
  - no usable pose frames exist,
  - too few pose frames were processed,
  - the clip is static,
  - examples are inconsistent.

Implementation requirements:

- Keep one pose-processing job in flight.
- Drop frames while pose detection is busy.
- Keep the last good skeleton visible for about 400ms.
- Clear stale skeletons after the hold window.
- Throttle UI updates to about 100-150ms.
- Start recording only when the camera stream exists, not when the whole body is
  visible.
- Stop recording only after target duration and minimum processed frames, with a
  max cap.

### 2. Make the Builder Conservative

The builder should learn only features that move consistently across examples.

Rules:

- Active features should come from repeated motion, not from all visible body
  parts.
- Required features should be the selected active features, not the full body.
- A wave should use wrists, elbows, shoulders, and relevant distances or angles.
- A squat should naturally select hips, knees, and ankles if visible.
- Return-to-start should only be required when all examples actually return.
- Static clips must reject.
- Random inconsistent motion must reject.

### 3. Make Runtime Forgiving Enough To Count Real Movement

The runtime should not demand frame-perfect replay.

Rules:

- Use sequence progress with forward lookahead.
- Allow small timing differences between examples and test movement.
- Allow brief missing-feature gaps.
- Require enough active-feature coverage, not full-body coverage.
- Count only after reaching terminal pose or return-to-start according to the
  learned strategy.
- Surface simple user guidance in product language.

## What To Build Next

### Phase A: MVP Hardening

Goal: a creator can teach and test a wave or reach reliably on a real phone.

Tasks:

1. Instrument capture quality in debug builds:
   - processed frames per clip,
   - valid pose frames,
   - selected active features,
   - rejection reason,
   - build failure reason,
   - runtime completion path.

2. Add a device QA script:
   - name movement,
   - record three wave examples,
   - learn movement,
   - test movement,
   - create custom race,
   - submit custom proof.

3. Add golden path fixtures:
   - upper-body wave with no hips or legs,
   - squat with legs visible,
   - static clip,
   - inconsistent random motion,
   - missing frames during runtime.

4. Add an internal support matrix:
   - "Works well": wave, reach, arm raise.
   - "Works if full body is visible": squat, lunge.
   - "Not supported yet": tiny finger gestures, dance routines.

### Phase B: Product Cut

Goal: prevent users from thinking this is universal.

Tasks:

1. Keep the copy broad but not magical:
   - "Record the same short movement three times."
   - "Nuvo learns the shared motion."

2. Avoid training or debug language:
   - No raw feature names.
   - No "model", "spec", "runtime", "landmarks", or "calibration" in user copy.

3. Add a friendly failure path:
   - "Nuvo couldn't read that one. Record it again."
   - "That one did not move enough. Record it again."
   - "Those did not match. Record the same movement each time."

### Phase C: Runtime Upgrade

Goal: reduce false negatives without increasing false positives.

Tasks:

1. Consider bounded dynamic-time-warping style matching for active feature
   sequences if windowed frame matching still fails quick movements.

2. Add per-feature weights:
   - higher weight for consistently moving features,
   - lower weight for noisy or barely moving features,
   - zero weight for missing/unreliable features.

3. Add warmup and reset logic:
   - ignore first few unstable frames,
   - avoid counting repeated terminal holds as new reps,
   - allow new rep only after reset or clear departure.

## Metrics For "Works"

Do not call the MVP done based on unit tests alone.

Minimum real-device acceptance:

- Wave/reach can be taught and learned in under 60 seconds.
- Three examples save without full-body gates.
- Static clips reject every time.
- No-pose clips reject every time.
- Matching live movement verifies at least 8 out of 10 attempts for the creator.
- Mismatched movement fails at least 8 out of 10 attempts.
- Race creation never shows "Choose a supported activity" for valid custom
  movement drafts.
- Custom race proof submits through `custom_pose_sequence`.

## What Not To Do Yet

- Do not add backend schema changes until the client flow works locally.
- Do not add MediaPipe Gesture Recognizer for body movements; it is hand-gesture
  focused and would be a separate feature.
- Do not add custom ML model training. Three examples are not enough training
  data for a robust model.
- Do not add LLM calls. This is a real-time deterministic verification problem.
- Do not broaden to all movement types before wave/reach and squat/lunge work on
  device.

## Recommended MVP Architecture

Keep the current pipeline:

```text
camera stream
  -> pose detector
  -> normalized pose frames
  -> three demonstration captures
  -> active feature selection
  -> canonical pose sequence spec
  -> live runtime verifier
  -> custom race creation
  -> custom proof submission
```

The important architectural rule is separation:

- Capture decides whether examples are usable.
- Builder decides what movement was learned.
- Runtime decides whether live proof matches.
- Race composer only persists a learned verifier into a race.

Do not let UI screens own builder or verifier logic beyond orchestration.
