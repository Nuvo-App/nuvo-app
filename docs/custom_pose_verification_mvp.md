# Custom Pose Verification MVP

## MVP Product Goal

Let a race creator define a custom camera-verified pose sequence later, while
preserving the current AI Motion Proof flow for preset races.

Stage 0 does not implement custom movement verification. It locks the current
source of truth before refactoring.

## Current Implementation Map

### Race creation and preset selection

- `lib/features/races/presentation/race_composer_screen.dart`
  - Builds the current race creation flow.
  - Uses `RaceDraft` payloads when starting a preset race.
- `lib/features/races/domain/race_draft.dart`
  - `RaceDraft`
  - `draftFromIdea`
  - `draftForActivity`
  - `generatedTitle`
  - `RaceDraft.toCreatePayload`
- `lib/features/races/domain/motion_activity.dart`
  - `MotionActivityType`
  - `RaceMetric`
  - `RaceFormat`
  - `RaceRecurrence`
  - `MotionActivityDefinition`
- `lib/features/races/domain/motion_activity_catalog.dart`
  - `motionActivityDefinitions`
  - `supportedMotionActivityTypes`
  - `motionActivityForType`
  - `motionActivityForBackendValue`
  - `resolveRaceMotionActivity`
  - `parseRaceIdea`

### Pose detection and preset validation

- `lib/features/races/presentation/ai_motion_proof_screen.dart`
  - Conditional export for mobile/web AI Motion Proof screen.
- `lib/features/races/presentation/ai_motion_proof_screen_io.dart`
  - Loads race detail.
  - Calls `resolveCameraVerification`.
  - Maps the resolved movement to `NuvoVerifyEngine`.
  - Streams camera frames through pose detection.
  - Submits verified AI Motion Proof.
- `lib/features/races/presentation/ai_motion_proof_screen_web.dart`
  - Web placeholder for the native-only camera flow.
- `lib/features/races/ai/pose_detector_service.dart`
  - ML Kit pose detector bridge.
- `lib/features/races/ai/camera_image_converter.dart`
  - Camera image to ML Kit input conversion.
- `lib/features/races/ai/motion_validators.dart`
  - `MovementDefinition`
  - `supportedMovementDefinitions`
  - `movementDefinitionForActivity`
  - `NuvoVerifyEngine`
  - `MotionValidator`
  - `createMotionValidator`
  - `PushupsValidator`
  - `JumpingJacksValidator`
  - `SquatsValidator`
  - `LungesValidator`
  - `PlankHoldValidator`
- `lib/features/races/data/ai_motion_models.dart`
  - `AiMotionActivity`
  - `AiMotionResult`
  - `NuvoPoseFrame`
  - `NuvoPosePoint`

### Camera proof and proof submission

- `lib/features/races/domain/camera_verification_resolver.dart`
  - `resolveCameraVerification`
  - `CameraVerificationEligibility`
  - `CameraVerificationSource`
  - `PreferredCameraView`
  - `debugLogCameraVerificationDecision`
- `lib/features/races/presentation/submit_proof_screen.dart`
  - Loads race detail.
  - Calls `resolveCameraVerification`.
  - Routes camera-verifiable races to `/race/:id/proof/ai-motion`.
  - Shows unsupported copy for unsupported camera movements.
- `lib/features/races/presentation/race_controller.dart`
  - Calls repository methods for race detail and proof submission.
- `lib/features/races/data/race_repository.dart`
  - `createRace`
  - `submitProof`
  - `submitAiMotionProof`
- `lib/features/races/data/race_api.dart`
  - `createRace`
  - `submitProof`
  - `submitAiMotionProof`
- `lib/features/races/data/race_models.dart`
  - `Race`
  - `RaceParticipant`
  - `RaceProof`
  - `RaceSubmissionResult`

### Backend race creation, proof acceptance, and leaderboard progress

- `server/worker/src/routes/races.ts`
  - `POST /races`
  - `GET /races/:id`
  - `POST /races/:id/proof`
  - `GET /races/:id/proofs`
  - `PATCH /races/:id/proofs/:proofId`
- `server/worker/src/domain/raceActivities.ts`
  - Activity and metric normalization.
- `server/worker/src/domain/raceValidation.ts`
  - Race config parsing and AI Motion Proof compatibility checks.
- `server/worker/src/domain/raceScoring.ts`
  - Verified submission scoring.
- `server/worker/src/domain/raceRanking.ts`
  - Leaderboard rank computation.
- `server/worker/src/domain/raceLifecycle.ts`
  - Race status/lifecycle helpers.
- `lib/features/races/domain/race_display.dart`
  - Client-side race progress, labels, status, and rank display helpers.

## Five Active Preset Activities

The active camera-verified preset activities are:

- `push_ups`
- `jumping_jacks`
- `squats`
- `lunges`
- `plank_hold`

`high_knees` and `arm_raises` still exist in older AI motion enums/validators,
but they are not in `motionActivityDefinitions` or
`supportedMotionActivityTypes`.

## Existing Reusable Components

- `NuvoPoseFrame` and `NuvoPosePoint` can be reused as the raw pose input.
- `PoseDetectorService` can provide frames for both presets and future custom
  verification.
- `MotionValidator` and `NuvoVerifyEngine` are the current preset runtime
  boundary.
- `CameraVerificationEligibility` is the current camera proof routing decision.
- `AiMotionResult.toProofPayload` is the current AI Motion Proof submission
  payload builder.
- Backend `raceValidation` and `raceScoring` already validate activity/metric
  compatibility and apply verified progress.

## Exact MVP User Flow

1. Creator starts a preset race from the race composer.
2. Composer writes a race payload with `activityId`, `metric`, `format`,
   `proofRequirement: ai_check`, `proofMode: ai_check`, and `aiActivityType`.
3. Backend `POST /races` stores the race activity, metric, format, target, and
   camera verification method.
4. Participant opens Race Detail and taps submit proof.
5. Submit Proof loads race detail and calls `resolveCameraVerification`.
6. Supported preset races route to AI Motion Proof.
7. AI Motion Proof loads race detail, calls `resolveCameraVerification`, chooses
   the matching preset `MovementDefinition`, and runs `NuvoVerifyEngine`.
8. Camera frames flow through `PoseDetectorService` into the active
   `MotionValidator`.
9. A verified `AiMotionResult` is submitted to `POST /races/:id/proof`.
10. Backend accepts compatible AI Motion Proof, writes a move log, updates
    progress, recomputes ranks, and returns updated leaderboard data.

Future custom flow should enter the same proof route, but with a distinct
verifier spec and runtime.

## Proposed Stage Sequence

1. Stage 0: Baseline and source-of-truth contract
2. Stage 1: Generic verifier runtime and preset adapters
3. Stage 2: Pose normalization and similarity primitives
4. Stage 3: Creator calibration recorder
5. Stage 4: Custom pose sequence builder
6. Stage 5: Custom runtime and creator test
7. Stage 6: Backend persistence and custom race creation
8. Stage 7: Participant custom proof flow
9. Stage 8: End-to-end stabilization

## Initial Verifier Types

- `preset_pose`: existing camera-verified preset movements.
- `custom_pose_sequence`: future creator-defined pose sequence.

Only `preset_pose` should execute until the custom verifier stages are
implemented.

## Stage 4 `CustomPoseVerifierSpec`

```dart
class CustomPoseVerifierSpec {
  const CustomPoseVerifierSpec({
    required this.schemaVersion,
    required this.verifierType,
    required this.movementName,
    required this.measurementType,
    required this.startPose,
    required this.completionPose,
    required this.completionStrategy,
    required this.canonicalSequence,
    required this.requiredFeatureIds,
    required this.activeFeatureIds,
    required this.sequenceSimilarityThreshold,
    required this.completionSimilarityThreshold,
    required this.resetSimilarityThreshold,
    required this.minimumValidFeatureRatio,
    required this.minimumVisibility,
    required this.cooldownMs,
    required this.expectedSequenceFrameCount,
    required this.calibrationSummary,
  });

  final int schemaVersion;
  final String verifierType;
  final String movementName;
  final String measurementType;
  final NormalizedPose startPose;
  final NormalizedPose completionPose;
  final CustomPoseCompletionStrategy completionStrategy;
  final List<PoseTemplateFrame> canonicalSequence;
  final List<String> requiredFeatureIds;
  final List<String> activeFeatureIds;
  final double sequenceSimilarityThreshold;
  final double completionSimilarityThreshold;
  final double resetSimilarityThreshold;
  final double minimumValidFeatureRatio;
  final double minimumVisibility;
  final int cooldownMs;
  final int expectedSequenceFrameCount;
  final CustomPoseCalibrationSummary calibrationSummary;
}
```

The stable identifiers are `schemaVersion = 1`,
`verifierType = custom_pose_sequence`, and `measurementType = count`. The
movement name remains data and is not promoted into a Dart activity enum. The
JSON form contains normalized pose features and template statistics only, not
raw ML Kit objects, camera frames, images, or videos.

## Stage 2 Pose Math Architecture

Normalization uses `NuvoPoseFrame` as input and emits serializable values only.
The primary origin is the hip midpoint. If hips are unavailable, the shoulder
midpoint is used. Scale uses shoulder width first, then torso length, then hip
width. If no finite positive scale can be found, normalization returns an
invalid pose with a clear reason instead of producing zero, NaN, or infinity.

Feature categories are bounded and general-purpose: body-relative landmark
coordinates, selected joint angles, and selected relative distances. Left and
right landmarks remain distinct; no automatic mirroring is applied. Current
front-camera mirroring is handled before `NuvoPoseFrame` reaches these
primitives, so these values preserve the landmark IDs they receive.

Landmarks below the confidence threshold are excluded from normalized landmarks
and features. Missing or low-confidence landmarks reduce valid-feature coverage
instead of becoming valid zero values.

Similarity compares shared valid features and returns a 0.0-1.0 similarity,
valid-feature ratio, compared-feature count, missing-feature count, and optional
per-feature diagnostics. If too few features are comparable, the result is
invalid and the public similarity is 0.

Serialization uses schema version `1` for normalized poses, feature vectors,
and sequence frames. Decoding rejects unknown versions, missing fields, unknown
landmark IDs, non-numeric values, non-finite values, and malformed feature
objects.

Known limitations: Stage 2 does not implement sequence resampling,
demonstration averaging, Dynamic Time Warping, active-feature selection,
custom verifier runtime, backend persistence, or backend pose replay.

## Stage 3 Creator Calibration Recorder

Stage 3 adds an internal `/internal/teach-movement` route for device testing.
It is not linked from public race creation and does not create a race. The flow
collects a movement name, one averaged start pose, and three manual
demonstration recordings in memory.

Calibration reuses the same camera convention as AI Motion Proof: portrait
orientation is locked, the back camera is preferred, iOS uses sensor rotation,
and Android uses the existing front/back rotation compensation in
`camera_image_converter.dart`. Front-camera mirror invariance is not added.
Pose frames preserve the ML Kit landmark left/right names received by
`PoseDetectorService`.

Stable start-pose capture uses Stage 2 normalization. It requires consecutive
valid normalized poses, compares adjacent poses for stability, resets the
window when movement or coverage drops, and averages only accepted stable
frames. The MVP local thresholds are intentionally scoped to calibration
capture and are not final verifier thresholds.

Demonstrations are manually started and stopped. Each accepted demonstration
stores only bounded `PoseSequenceFrame` values with relative elapsed time and
normalized sequence position. Raw camera frames, images, videos, ML Kit objects,
race IDs, backend IDs, and final verifier thresholds are not stored.

Capture quality checks include valid start pose, start-pose stability,
demonstration count, processed-frame count, valid-frame count, valid-frame
ratio, average normalized-pose coverage, and interruption status. A calibration
is ready for Stage 4 only when the start pose is valid, exactly three
demonstrations are accepted, and no camera interruption remains unresolved.

`CustomPoseCalibration` uses schema version `1` and round-trips through JSON for
tests and debugging. It reuses Stage 2 normalized-pose and sequence-frame
serializers. No D1 persistence or backend fields are introduced.

Known limitations: Stage 3 does not build a final verifier spec, align
demonstrations, resample sequences, choose active features, run custom
participant proof, create a race, persist calibration, or replay evidence on
the backend.

## Stage 4 Custom Pose Sequence Builder

Stage 4 converts one ready `CustomPoseCalibration` into one deterministic
`CustomPoseVerifierSpec`. It does not run live camera verification, count reps,
create a race, persist anything, or submit proof.

The implemented builder pipeline is:

```text
validate calibration
→ trim static capture padding
→ determine shared required features
→ select active movement features
→ resample each demonstration to 24 frames
→ compare demonstration consistency
→ build the canonical template
→ infer completion strategy
→ derive MVP thresholds
→ centrally validate the spec
→ self-validate source demonstrations against the template
→ serialize through stable JSON
```

Calibration validation rejects not-ready calibrations, invalid start poses,
wrong demonstration counts, empty recordings, too few valid frames, malformed
nested pose data, invalid movement names, non-finite values, and metadata that
contradicts stored sequence contents.

Trimming removes leading frames that remain strongly similar to the captured
start pose while preserving one start-state context frame. Trailing reset
padding is reduced to a single return frame when the creator held the start
pose after returning. Entirely static recordings are rejected. The captured
`startPose` remains the reset pose in the final spec.

Completion is represented with
`CustomPoseCompletionStrategy.completionAtTerminalPose` when all demonstrations
end away from the reset pose, and
`CustomPoseCompletionStrategy.completionAfterSequenceReturn` when all
demonstrations return to the reset pose after the ordered sequence. Mixed or
ambiguous demonstrations are rejected instead of silently choosing one mode.

Resampling uses fixed normalized sequence position, not wall-clock duration,
and produces 24 `PoseTemplateFrame` values. Each scalar feature is interpolated
only between compatible valid values. Missing or invalid values are omitted
rather than filled with zero. Alignment for the MVP is fixed-position alignment
after trimming and resampling, bounded by exactly three demonstrations and a
24-frame template.

Feature selection starts from features present in the start pose and reliably
covered across all three cleaned demonstrations. A feature is selected for the
template only when it has enough coverage, enough movement amplitude, and
consistent amplitude across demonstrations. Mostly static features and
inconsistently available features are excluded. Diagnostics are returned for
development but are not shown in normal creator-facing UI.

Consistency validation calculates deterministic pairwise sequence similarity
across selected active features. The builder rejects demonstrations with too
few active features, low lowest-pair similarity, or low overall consistency.

Threshold generation is conservative and local to the MVP. Sequence,
completion, reset, valid-feature-ratio, visibility, and cooldown thresholds are
derived from calibration consistency, start-pose stability, active-feature
count, and calibration coverage, then clamped to documented safe ranges. After
building the spec, the builder compares all three source demonstrations back
against the canonical sequence and rejects the spec if the creator's own
recordings do not meet the generated sequence threshold.

`validateCustomPoseVerifierSpec` centrally rejects unsupported schema versions,
wrong verifier or measurement types, empty movement names, invalid poses, empty
or non-monotonic templates, duplicate or unknown feature IDs, inactive required
features, invalid thresholds, invalid cooldowns, inconsistent frame counts,
malformed calibration summaries, and non-finite values. JSON decoding rejects
unknown versions, missing fields, malformed template frames, unknown feature
IDs, and unsupported completion strategies.

The internal `/internal/teach-movement` summary screen now exposes a
development-only `Build movement template` action after a ready calibration.
The action runs the builder in memory, displays either a clear rejection reason
or a concise verifier summary, and does not expose publish, race creation,
participant proof, or live verification.

Known limitations: Stage 4 uses fixed-position alignment rather than Dynamic
Time Warping, stores only compact template statistics, and infers completion
strategy from consistent terminal reset behavior. It does not implement a
runtime state machine, repetition counting, persistence, backend evidence
replay, creator five-repetition testing, or participant custom proof.

## Stage 5 Live Custom Pose Runtime and Creator Test

Stage 5 adds the first executable runtime for `custom_pose_sequence`. The
runtime is driven entirely by `CustomPoseVerifierSpec` data: start pose,
canonical sequence, active and required feature IDs, completion strategy,
thresholds, feature coverage, visibility, and cooldown. It does not add a
movement enum, movement-specific validator, backend persistence, race creation,
proof submission, or leaderboard integration.

The live runtime states are:

- `waitingForSetup`: runtime has started and is waiting for a usable normalized
  pose.
- `waitingForStart`: setup is valid, but the participant has not held the
  stored start pose long enough.
- `armed`: the start pose has been held for 3 consecutive qualifying frames.
- `matchingSequence`: the participant has departed from start and ordered
  template progress is being matched.
- `completionCandidate`: terminal-pose completion is stable but not counted
  until the required completion-frame count is met.
- `waitingForReset`: a terminal-pose repetition counted and the runtime is
  waiting for a stable return to the start pose.
- `cooldown`: a return-to-start repetition counted and duplicate counts are
  blocked until cooldown and departure conditions are satisfied.
- `invalid`: the supplied spec is unsupported or malformed.

Sequence matching is monotonic and bounded. For each valid pose, the runtime
compares only a small canonical window around current progress: one earlier
frame for noise tolerance, the current frame, and up to four forward template
frames. It prefers valid forward progress over staying on the same index, never
searches the whole 24-frame template as an independent best match, and never
uses unbounded Dynamic Time Warping. Completion requires at least 82% ordered
sequence coverage. Return-to-start specs may treat a stable reset as the final
return region only after at least 70% of the action has already been observed.

Speed variation is supported by permitting repeated matches to the current
region, bounded forward progress, and intermediate holds. Reversed movement,
out-of-order stages, starting halfway through the sequence, and final-pose-only
shortcuts are rejected by the stable-start requirement and monotonic progress
window.

Completion supports both Stage 4 strategies:

- `completionAtTerminalPose`: counts after start was armed, ordered progress
  passed the minimum coverage, completion similarity passes the spec threshold,
  and completion is stable for 2 processed frames. Holding the terminal pose
  cannot count again; a stable reset is required.
- `completionAfterSequenceReturn`: counts after start was armed, ordered action
  progress was observed, and the participant returns to the stored start pose
  for 2 processed frames. Holding the start pose cannot count again; meaningful
  departure is required before another repetition.

Cooldown uses `cooldownMs` from the spec, converted to a bounded frame count for
the MVP live loop. It blocks duplicate completion events without erasing the
valid count. Abandoned attempts reset after 18 frames without meaningful
progress. Brief missing-feature loss is tolerated for 3 frames; during that
grace window progress does not advance and no count can occur. Extended missing
required features invalidate only the current attempt and preserve previous
valid repetitions.

`CustomPoseRuntimeUpdate` reports state, count, target, sequence progress,
current template index, current similarity, completion similarity, reset
similarity, valid-feature ratio, visibility, analyzed frames, valid frames,
missing-feature grace count, progress timeout state, guidance, failure reason,
and bounded diagnostic confidence.

`CustomPoseRuntimeResult` reports verifier type, runtime version, movement
name, measurement type, count, target, verification status, confidence, frames
analyzed, valid frames, duration, completion events, invalid-attempt count, and
final failure reason. It round-trips through JSON for tests. It is not a
backend proof payload and does not force the movement name into
`AiMotionActivity`.

The internal `/internal/teach-movement` flow now supports:

```text
calibration summary
→ build movement template
→ verifier summary
→ test learned movement
→ live camera test
→ in-memory readiness after five verified repetitions
```

The live test target is exactly 5 verified repetitions. The summary shows live
count, target, sequence progress, simple guidance, and final test status. A
successful test creates an in-memory `CustomPoseVerifierReadiness` equivalent
to `verifier built: yes`, `creator live test: passed`, and `ready for Stage 6
persistence: yes`. No publish, race creation, backend upload, or participant
proof action exists.

Known limitations: Stage 5 has not been physically validated in this coding
environment, uses a frame-count cooldown approximation rather than camera
timestamp deltas, keeps a compatibility shim for the existing preset-oriented
`VerifierRuntime` interface, and does not include threshold tuning UI,
persistence, backend replay, participant proof, race integration, anti-cheat,
or liveness checks.

## Stage 6 Persistence

Stage 6 persists a creator-tested `CustomPoseVerifierSpec` with a real race.
The backend stores nullable verifier fields on `races`: `verifier_type`,
`verifier_version`, `verifier_spec_json`, and `custom_activity_name`.

Custom races use the stable values `verifierType=custom_pose_sequence`,
`verifierVersion=1`, `metric=reps`, `unit=reps`,
`proofRequirement=ai_check`, `proofMode=ai_check`, and
`verificationMethod=ai`. The worker structurally validates the custom verifier
JSON and size-bounds it before insert, but does not replay pose math.

The internal teach screen now exposes `Create race with this movement` only
after the five-rep creator test passes. It collects only a race title and target
with defaults of movement name and `10` reps, creates a private race through
the real `/races` endpoint, and navigates to the race detail.

Race response decoding parses custom verifier specs once in `Race.fromJson`.
Custom races display the custom movement name and reps target, but proof
execution remains intentionally disabled until Stage 7. Submit Proof shows an
unsupported state and the backend rejects proof submissions for custom verifier
races.

## Baseline Test Inventory

### Flutter tests

- `test/race_draft_test.dart`
  - Race idea parsing, preset payloads, unsupported activity rejection, metric
    invariants, and catalog invariants.
- `test/race_composer_test.dart`
  - Generated race titles, draft editing behavior, create payload consistency,
    quick start behavior, and plank seconds handling.
- `test/race_display_test.dart`
  - Progress labels, rank labels, completion state, submission result parsing,
    and legacy race compatibility.
- `test/camera_verification_resolver_test.dart`
  - Stage 0 regression coverage for active preset eligibility, legacy
    `aiActivityType`, title inference, and unsupported movement routing.
- Other UI/component tests:
  - `test/animated_race_track_test.dart`
  - `test/nuvo_design_components_test.dart`
  - `test/nuvo_icons_test.dart`
  - `test/nuvo_preview_style_test.dart`
  - `test/race_ring_test.dart`
  - `test/reviewer_login_screen_test.dart`
  - `test/widget_test.dart`

### Backend tests

- `server/worker/test/race_domain.test.mjs`
  - Scoring for arbitrary targets, idempotent proof route behavior,
    non-participant proof rejection, final standings snapshot ordering,
    ranking, activity/metric normalization, race validation, and submission
    compatibility.

## Original Stage 0 Non-Goals

- No custom verifier runtime in Stage 0.
- No calibration screen.
- No GPT, object detection, or training pipeline.
- No backend schema migration in Stage 0.
- No proof payload semantic change.
- No restored universal implementation.
- No changes to preset validator thresholds or state machines.
- No new user-visible custom option.

## Known Current Trust Limitation

The backend currently trusts the AI verification status and result reported by
the Flutter client. It validates race membership, compatibility, and submission
structure, but it does not independently replay pose evidence.

Title and unit inference may remain only as a legacy preset fallback. Future
custom verification must use an explicit verifier type.

## Original Stage 0 Definition of Done

- Current preset races compile and continue to use the existing preset
  validators.
- Existing proof flow routes through Submit Proof into AI Motion Proof for
  supported presets.
- Unsupported camera movements do not silently fall back to a preset.
- Baseline tests for draft payloads, display helpers, backend scoring, and
  camera verification routing pass.
- No custom verifier code is implemented in Stage 0.
- No backend schema migration is introduced in Stage 0.
- No user-visible behavior changes.
