# Nuvo motion control plane — Stage 0 baseline

Date: 2026-09-17
Contract: `docs/NUVO_MOTION_CONTROL_PLANE_PRD.md`
Status: Stage 0 inventory and contract lock

## Scope and authority

This is a snapshot of the pre-control-plane implementation. It is an input to
the staged migration, not a second activity catalog. The PRD remains the
authority for the target architecture.

The current implementation has four relevant surfaces:

| Surface | Current location | Current role | Stage 0 finding |
| --- | --- | --- | --- |
| Flutter activity identity and display metadata | `lib/features/races/domain/motion_activity.dart`, `motion_activity_catalog.dart` | Composer, race display, legacy resolution | 23 stable IDs; compile-time source |
| Flutter live validator dispatch | `lib/features/races/ai/motion_validators.dart` | On-device pose-frame decisions | 23 local dispatch entries; hardcoded behavior |
| Flutter manufacturing/work-order metadata | `lib/features/races/ai/preset_motion/preset_movement_work_orders.dart` | Behavior documentation and tests | 13 entries; 10 legacy/native validators have no work order |
| Worker race activity allowlist | `server/worker/src/domain/raceActivities.ts` and `GET /races/activities` | Race creation validation and legacy catalog response | 23 IDs; separate static TypeScript authority |

The existing `/motion/models/current` endpoint and `motion_model_releases`
table describe server-side post-hoc analysis artifacts. They do not deliver a
declarative release to the Flutter live verifier and must not be treated as the
control plane implementation.

## Activity inventory

The following is the complete current preset set. The `current local family`
column describes the installed behavior; `target remote mode` describes the
PRD migration destination, not a claim that remote execution exists yet.

| Stable activity ID | Current local family | Target remote mode | Current status |
| --- | --- | --- | --- |
| `push_ups` | `PushupsValidator` | `state_machine_v1` | native compatibility |
| `jumping_jacks` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `squats` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `lunges` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `plank_hold` | `PlankHoldValidator` | `hold_v1` | native compatibility |
| `high_knees` | `HighKneesValidator` | `alternating_rep_v1` | native compatibility |
| `arm_raises` | `ArmRaisesValidator` | `state_machine_v1` | native compatibility |
| `sumo_squats` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `side_lunges` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `deep_squats` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `squat_jacks` | `ConfigurableRepValidator` | `state_machine_v1` | generic candidate |
| `jump_squats` | `MultiPhaseSequenceValidator` | `sequence_match_v1` | native compatibility |
| `lunge_jumps` | `MultiPhaseSequenceValidator` | `sequence_match_v1` | native compatibility |
| `running_in_place` | `CadenceMotionValidator` | `alternating_rep_v1` | native compatibility |
| `treadmill_running` | `CadenceMotionValidator` | `alternating_rep_v1` | native compatibility |
| `walking_in_place` | `CadenceMotionValidator` | `alternating_rep_v1` | native compatibility |
| `marching_in_place` | `CadenceMotionValidator` | `alternating_rep_v1` | native compatibility |
| `butt_kicks` | `CadenceMotionValidator` | `alternating_rep_v1` | native compatibility |
| `mountain_climbers` | `MountainClimbersValidator` | `alternating_rep_v1` | native compatibility |
| `burpees` | `MultiPhaseSequenceValidator` | `sequence_match_v1` | native compatibility |
| `step_ups` | `CadenceMotionValidator` | `alternating_rep_v1` | native compatibility |
| `calf_raises` | `CalfRaisesValidator` | `state_machine_v1` | native compatibility |
| `lateral_steps` | `LateralStepsValidator` | `alternating_rep_v1` | native compatibility |

The Flutter enum/catalog IDs and Worker catalog IDs are an exact set match:
23 IDs on each side. That result is covered by the existing
`test/preset_activity_round_trip_test.dart` contract test and by Worker catalog
tests. The parity is useful, but it does not make either static list the future
production authority.

## Current version and evidence baseline

The current Worker motion-analysis versions are:

- analysis schema: `1`
- server model: `nuvo-motion-baseline-v1`
- server validator: `nuvo-motion-server-rules-v1`
- Flutter motion-session model label: `mlkit-pose-base`

These identifiers describe different paths and are not interchangeable release
IDs. Stage 1 must introduce immutable verifier release IDs and checksums before
any of them are used for race assignment or session pinning.

Baseline evidence captured before Stage 0 artifacts:

| Check | Result |
| --- | --- |
| Flutter activity/validator round-trip suite (5 targeted files) | 102 tests passed |
| Worker `npm run typecheck` | passed with zero output |
| Worker `npm test` | 88 tests passed, 0 failed |
| Simulator/device launch | not performed |

The Flutter baseline includes existing local replay and identity coverage. It is
not the PRD release-gate dataset: it does not yet provide held-out per-person,
distance, speed, framing, dropout, and confusion strata for every stable
activity.

## Contract and naming lock

The following names are frozen for later stages:

- Stable activity identity: `activityId` (snake case, e.g. `push_ups`).
- Immutable verifier release: `releaseId` plus `checksum`.
- Runtime family: `engineType` with only the PRD families
  `state_machine_v1`, `alternating_rep_v1`, `hold_v1`, `sequence_match_v1`,
  and `native_v1`.
- Capability names: `pose_landmarks_v1`, `derived_features_v1`,
  `state_machine_v1`, `alternating_rep_v1`, `hold_v1`, `sequence_match_v1`,
  plus explicit allowlisted native validator keys.
- Race assignment policy: `pinned` or `follow_compatible_patch`.
- Session release fields: `releaseId`, `releaseChecksum`, `engineType`, and
  `specSchemaVersion`; these are immutable after session creation.
- The phone executes validated declarative specifications locally. It never
  downloads Dart, JavaScript, native libraries, or arbitrary expressions.

The shared fixture file
`docs/motion_control_plane_contract_fixtures.json` contains the initial
capability registry, response-shape examples, and rejection cases for the
Stage 1 Worker and Stage 3 Flutter contract tests.

## Mismatch and risk register

1. **Duplicate catalog authority — high.** Flutter and Worker currently repeat
   the activity set. Stage 1 must make D1 authoritative while preserving the
   old response shape during migration.
2. **No immutable race release assignment — high.** Existing preset races carry
   activity/verifier legacy fields; a future session must not infer behavior
   from a title or resolve a moving channel pointer.
3. **No live remote spec consumer — high.** Existing model APIs and telemetry do
   not change the on-device validator. Stage 3/4 must add the repository/cache
   and runtime factory before enabling remote execution.
4. **Work-order coverage is incomplete — medium.** 13 activities have
   `MovementWorkOrder` records; 10 rely on legacy/native validator definitions.
   This is migration backlog, not a reason to invent remote specs without
   replay evidence.
5. **Server and Flutter display metadata differ — medium.** Category, proof
   label, display unit, camera policy detail, featured ordering, and measurement
   presentation are primarily Flutter-owned today. The registry contract must
   carry stable metadata without making display text a verifier selector.
6. **Existing motion telemetry lacks release identity — high.** Stage 2 must
   add release/checksum and runtime evidence while preserving current artifact
   uploads and privacy boundaries.
7. **Custom and manual races — high compatibility.** They must continue through
   their existing paths and must not be coerced into preset release assignment.

## Stage 0 gate

Stage 0 passes for this repository when the inventory and fixture are reviewed
against the current sources, the two catalog ID sets remain exactly equal, and
the baseline checks above are repeatable. No production behavior is enabled by
this artifact-only stage.
