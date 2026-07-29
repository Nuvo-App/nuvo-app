# Nuvo Live Proof Engine Implementation Plan

This document starts the implementation process for turning the current AI
Motion Proof flow into a reusable live proof engine. It is the Phase 0 baseline:
no runtime behavior changes are implied by this file.

## Product Target

Nuvo should support races where progress is verified live through the camera:

```text
Create race -> choose Nuvo AI proof -> open camera -> track progress live
-> submit verified proof -> move the leaderboard
```

The target is not one-off support for a single activity. The target is:

```text
One live camera engine.
Many activity validators.
Generic proof result.
No video storage required.
```

## Current Baseline

The existing AI Motion Proof path already proves the main loop:

```text
Race Detail / Submit Proof
-> /race/:id/proof/ai-motion
-> AiMotionProofScreen
-> CameraController image stream
-> PoseDetectorService
-> NuvoVerifyEngine
-> MotionValidator
-> AiMotionResult
-> RaceController.submitAiMotionProof
-> RaceApi.submitAiMotionProof
-> POST /races/:id/proof
-> leaderboard update
```

Current stable activities are pose-based:

- pushups
- squats
- jumping jacks
- lunges
- plank hold

Current proof submissions send structured analysis only. The app does not need
to store proof video for the existing AI Motion Proof flow.

## Existing Building Blocks

### `AiMotionProofScreen`

File: `lib/features/races/presentation/ai_motion_proof_screen_io.dart`

Current responsibilities:

- load race detail
- resolve camera eligibility
- choose movement and target
- own camera lifecycle
- start and stop image stream
- send frames to pose detection
- update the verifier
- render live count, confidence, and status
- submit verified proof

This screen currently owns both UI and engine orchestration. The long-term goal
is to keep it as the UI shell and move engine orchestration into reusable live
proof classes.

### `PoseDetectorService`

File: `lib/features/races/ai/pose_detector_service.dart`

Current responsibility:

- convert camera frames into `NuvoPoseFrame`
- provide normalized body landmark positions and likelihoods

This remains the first signal detector in the live proof engine.

### `NuvoVerifyEngine`

File: `lib/features/races/ai/motion_validators.dart`

Current responsibilities:

- hold the selected movement
- create the activity-specific `MotionValidator`
- forward each `NuvoPoseFrame` into the validator
- expose live count, confidence, feedback, and completion state
- produce the final `AiMotionResult`

This is the closest current equivalent to the future `NuvoLiveProofEngine`, but
it is still named and shaped around motion-only proof.

### `MotionValidator`

File: `lib/features/races/ai/motion_validators.dart`

Current contract:

```text
start()
update(NuvoPoseFrame)
finish() -> AiMotionResult
```

Current validators already behave like plugins. The next step is to formalize
that contract so validators can consume multiple signal types later, not only
pose frames.

### `AiMotionResult`

File: `lib/features/races/data/ai_motion_models.dart`

Current proof result fields include:

- activity
- target value
- detected value
- confidence
- verification status
- verification summary
- frames analyzed
- valid pose frames
- duration
- validator version

This shape is close to the final generic proof result. It should eventually be
renamed or wrapped so non-motion validators can use the same submission path.

### Activity Catalog

File: `lib/features/races/domain/motion_activity_catalog.dart`

Current responsibilities:

- define supported activities
- define units, default targets, camera instructions, and formats
- parse race ideas
- mark which activities are camera-verifiable

This should become the registry-backed source of truth for Nuvo AI activities.

## Target Architecture

```text
Race activityId
-> LiveProofActivityRegistry
-> LiveProofActivityDefinition
-> NuvoLiveProofEngine
-> LiveProofSignal detectors
-> LiveProofValidator
-> LiveProofUpdate
-> LiveProofResult
-> existing proof submission endpoint
```

## Target Core Types

### `LiveProofActivityDefinition`

Defines what an AI-verifiable activity needs:

```text
activityId
title
unit
metric
supported formats
required signals
validator factory
camera instructions
default target
confidence threshold
```

### `LiveProofEngine`

Owns reusable proof orchestration:

```text
start()
stop()
update from camera frame
track duration
run detectors
feed validator
emit LiveProofUpdate
finish() -> LiveProofResult
```

### `LiveProofSignal`

Reusable detector output. Initial signal:

```text
PoseSignal from NuvoPoseFrame
```

Future signals:

```text
ObjectSignal
SceneSignal
AudioSignal
CloudflareVisionSignal
```

### `LiveProofValidator`

Generic validator plugin contract:

```text
start()
update(LiveProofSignals) -> LiveProofUpdate
finish() -> LiveProofResult
```

Existing `MotionValidator` implementations should be adapted into this
contract without changing their verification math.

## Implementation Sequence

### Phase 1: Add Generic Interfaces

Add new live proof interfaces alongside existing code:

- `LiveProofEngine`
- `LiveProofValidator`
- `LiveProofSignal`
- `LiveProofUpdate`
- `LiveProofResult`
- `LiveProofActivityDefinition`

No existing behavior should change in this phase.

### Phase 2: Wrap Existing Motion Validators

Adapt the current `MotionValidator` contract into the generic validator
contract. Existing pushups, squats, jumping jacks, lunges, and plank hold must
produce the same live count, confidence, status, and final proof values.

### Phase 3: Move Orchestration Out Of The Screen

Move non-UI orchestration out of `AiMotionProofScreen`:

- frame processing
- engine start/finish
- validator updates
- frame count and duration aggregation

The screen should remain responsible for:

- route/race loading
- rendering live state
- camera controls
- submit action
- navigation

### Phase 4: Registry-Backed Activity Selection

Make race `activityId` / `aiActivityType` choose the validator through a single
registry. Reduce duplicate title inference over time.

### Phase 5: Registry-Backed Race Creation

Make AI race creation write consistent activity metadata:

```text
activityId
aiActivityType
metric
targetUnit
proofRequirement: ai_check
proofMode: ai_check
format
targetValue
```

### Phase 6: Add New Activities As Plugins

New AI-verifiable race types should require:

- registry entry
- validator implementation
- camera instructions
- confidence threshold
- manual device test

They should not require a new proof screen.

### Phase 7: Add More Signal Providers

After the pose-only plugin system is stable, add optional signals:

- local object detection
- local scene/framing checks
- Cloudflare Workers AI sampled-frame checks

These signals should support validators. They should not replace the live
on-device loop for activities that need instant feedback.

## Guardrails

- Do not fake AI verification.
- Do not bypass `motion_validators.dart` verification outputs for existing
  activities.
- Keep camera lifecycle changes small and isolated.
- Do not change backend JSON contracts until a scoped backend task is declared.
- Do not add dependencies without explicit scoped approval.
- After Flutter changes, run:

```bash
flutter analyze --no-fatal-infos
```

The known baseline has 4 existing info findings in
`lib/features/auth/presentation/auth_controller.dart`.

## First Code Task

The first code task should be:

```text
Add generic live proof interfaces and a compatibility wrapper for the current
MotionValidator system, without changing AI Motion Proof behavior.
```

That task should avoid changing camera lifecycle code until the interfaces are
in place.
