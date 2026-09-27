# Nuvo Motion Control Plane PRD

Status: implementation contract  
Owner: Nuvo  
Scope: Flutter client, Cloudflare Worker, D1, R2, motion evaluation tooling  
Primary outcome: improve, add, release, and roll back motion verifiers without requiring an app release for every movement change

## 0. Directive To The Implementing Agent

This document is the source of truth for the work. It is not an architecture suggestion.

Implement the stages in order. Do not stop after an audit, a schema draft, a catalog endpoint, or a set of passing unit tests. Continue through migration, client integration, release pinning, replay evaluation, rollback, and end-to-end verification unless an external credential, deployment approval, or destructive production action is required.

Before each stage:

1. Read the affected production code and existing tests.
2. State the exact files and contracts that stage will change.
3. Preserve unrelated working behavior and user changes.

After each stage:

1. Run its required deterministic tests.
2. Record the migration and compatibility result.
3. Commit the stage independently with a descriptive commit message.
4. Continue to the next stage automatically when the gate passes.

The following are not acceptable completion claims:

- "The infrastructure exists" when the Flutter app still uses the static catalog.
- "The API works" when races do not pin an immutable verifier release.
- "Tests pass" when no representative verifier has completed the remote round trip.
- "Backward compatible" without testing an old race payload and an old app capability set.
- "The failure is pre-existing" without reproducing it against the baseline commit or a clean comparison worktree.
- Updating golden files or expectations simply to make a changed result pass.
- Adding another hardcoded catalog that must be manually synchronized.
- Shipping a debug fixture, fake learned state, or forced success path as proof of integration.

## 1. Executive Summary

Nuvo currently ships movement identities, UI metadata, camera guidance, validator selection, and much of the verifier behavior inside the Flutter binary. The Worker contains a second movement catalog. This makes verifier improvements slow and risky: changing one action or adding a preset can require an app build, beta redistribution, and repeated user testing.

Nuvo will introduce a Motion Control Plane with two separated responsibilities:

- The phone is the motion data plane. It captures pose landmarks and runs a deterministic, low-latency verifier locally.
- The Worker is the control plane. It owns the activity catalog, immutable verifier releases, compatibility, rollout, rollback, race assignment, and telemetry indexing.

One foundational app release will install generic verifier runtimes and the remote registry client. After that release, Nuvo may remotely:

- Change instructions and camera framing policy.
- Tune thresholds, timing, required landmarks, hysteresis, and feedback.
- Publish compatible fixes for one movement without changing unrelated movements.
- Add activities expressible by an installed generic runtime.
- Roll back a bad verifier release immediately.

New executable Dart logic, new sensors, new pose models, or new runtime operators still require an app release. The Worker must never send executable code.

## 2. Problem Statement

### 2.1 User problem

Motion verification is too sensitive to camera distance, body framing, movement speed, and action-specific assumptions. A user can perform a valid movement while Nuvo remains stuck in readiness guidance, misses the action, counts late, or requires irrelevant body parts.

When this happens, Nuvo cannot currently improve the affected verifier quickly enough. Testers may need another app build even when the desired fix is only a threshold, visibility requirement, timing rule, or movement definition.

### 2.2 Product problem

Nuvo needs to support a growing activity catalog without turning each movement into a new app feature. Product operators need to see which verifier version ran, inspect failures, test a candidate improvement, release it to a subset of users, and roll it back without changing every race or every activity.

### 2.3 Engineering problem

The current sources of truth are duplicated and compiled:

- `lib/features/races/domain/motion_activity.dart`
- `lib/features/races/domain/motion_activity_catalog.dart`
- `lib/features/races/ai/motion_validators.dart`
- `lib/features/races/ai/preset_motion/preset_movement_work_orders.dart`
- `lib/features/races/ai/verifier_runtime.dart`
- `server/worker/src/domain/raceActivities.ts`

The current race model can store a custom pose sequence specification, but preset races resolve to local hardcoded definitions. A Worker catalog endpoint exists, but the Flutter composer and runtime do not consume it as their source of truth.

## 3. Goals

1. Publish a compatible verifier improvement without publishing the app.
2. Add a compatible activity without publishing the app.
3. Change only the selected activity and release, not the whole catalog.
4. Freeze the verifier used by an active verification session.
5. Keep every race internally consistent across participants.
6. Support controlled compatible updates for active races between sessions.
7. Preserve offline verification when the required release is already cached.
8. Prevent old apps from seeing verifiers they cannot execute.
9. Collect enough versioned evidence to reproduce missed and false counts.
10. Roll back a bad release without mutating historical releases.
11. Keep live motion decisions local, deterministic, and responsive.
12. Preserve custom taught movements while the preset system migrates.

## 4. Non-Goals

1. Running an LLM in the live camera loop.
2. Downloading or executing arbitrary code from the Worker.
3. Replacing the on-device pose detector in this project.
4. Automatically publishing an AI-generated verifier.
5. Uploading raw video by default.
6. Rewriting Teach Nuvo as part of the first control-plane migration.
7. Moving every existing specialized validator to the generic runtime before launch.
8. Making all historical races silently follow every future verifier change.
9. Treating successful compilation as proof of recognition quality.

## 5. Product Principles

### 5.1 One activity identity, many immutable releases

`push_ups` is a stable activity identity. `pushups-2026.09.3` is an immutable verifier release. A release is never edited after publication.

### 5.2 Pin sessions, govern races

A verification session always freezes its release ID, checksum, and specification at session creation. A race has an explicit update policy that determines whether it may move to a compatible release between sessions.

### 5.3 Local recognition, remote control

The app must not depend on a network round trip for each frame, state transition, or rep. The Worker distributes releases and records outcomes. The phone executes them.

### 5.4 Compatibility is negotiated, never assumed

The app advertises runtime capabilities and build information. The Worker returns only releases the client can execute.

### 5.5 Data improves the verifier only through evaluation

Telemetry and user labels may produce a candidate release. Deterministic replay, regression comparison, and human approval are required before publication.

## 6. User Stories

### 6.1 Person verifying a race

- I can begin quickly without waiting for cloud inference.
- Nuvo asks only for the body regions required by this activity.
- Nuvo handles near, normal, and farther camera distances within the verifier's supported range.
- The verifier does not change while I am performing an attempt.
- Friendly guidance explains what must change without exposing internal rule names.
- If I am offline and the release is cached, verification still works.
- I can report `Missed my movement` or `Counted incorrectly` after an attempt.

### 6.2 Nuvo operator

- I can create or edit a draft release for one activity.
- I can replay it against labeled recordings and compare it with stable.
- I can publish it to internal, beta, canary, or stable channels.
- I can see adoption, errors, missed-count reports, and false-count reports by release.
- I can roll back the channel pointer without deleting history.
- I cannot accidentally publish a release incompatible with the target app population.

### 6.3 Race participant

- Every participant in my race uses the same race-assigned release at a given time.
- A compatible update never changes an attempt already in progress.
- A breaking update does not silently alter my active race.

## 7. System Architecture

```text
                        NUVO MOTION CONTROL PLANE

 Internal editor / tooling
          |
          v
 Draft release -> schema validation -> replay evaluation -> approval
          |                                               |
          +---------------- publish / rollback ------------+
                                                          v
                           Cloudflare Worker
                 +-------------+-------------+
                 |                           |
                 v                           v
           D1 registry                 R2 artifacts
     activities, releases,          reference sequences,
     channels, assignments,         session landmark data,
     sessions, evaluation runs      evaluation reports
                 |
                 v
       catalog and release APIs
                 |
                 v
       Flutter release repository
       cache by release ID/checksum
                 |
                 v
 camera -> pose detector -> normalizer -> local runtime -> guidance/count
                                                        |
                                                        v
                                         versioned result + telemetry
```

Cloudflare Queues may process telemetry and evaluation jobs asynchronously. They are not required in the live verification path.

## 8. Domain Model

### 8.1 Motion activity

A stable product identity and display record. It does not contain mutable verifier behavior.

Required fields:

- `id`: stable snake-case identifier.
- `display_name`.
- `category`.
- `proof_label`.
- `measurement_type`: `repetitions`, `duration`, or `distance`.
- `metric`.
- `suggested_targets_json`.
- `supported_formats_json`.
- `icon_key`: value from a client-supported icon allowlist.
- `sort_priority`.
- `featured`.
- `availability`: `draft`, `internal`, `beta`, `stable`, `hidden`, `retired`.
- `created_at`, `updated_at`.

Activity IDs are strings at network and persistence boundaries. Flutter enums may remain only as legacy adapters during migration.

### 8.2 Verifier release

An immutable executable specification.

Required fields:

- `id`: globally unique release ID.
- `activity_id`.
- `semver`.
- `change_class`: `patch`, `minor`, or `major`.
- `engine_type`.
- `spec_schema_version`.
- `spec_json` or `spec_object_key`.
- `checksum_sha256`.
- `required_capabilities_json`.
- `minimum_app_build`.
- `compatibility_group`.
- `status`: `draft`, `validated`, `internal`, `beta`, `stable`, `retired`, `disabled`.
- `release_notes`.
- `created_by`, `created_at`, `published_at`.
- `parent_release_id`.

Published release rows and their specifications are immutable. Changing any executable field creates a new release.

### 8.3 Activity channel release

Maps an activity and channel to one release.

- `activity_id`.
- `channel`: `internal`, `beta`, `stable`.
- `release_id`.
- `rollout_percent`.
- `updated_at`, `updated_by`.

Changing this pointer is the release and rollback operation.

### 8.4 Race verifier assignment

- `race_id`.
- `activity_id`.
- `release_id`.
- `update_policy`: `pinned` or `follow_compatible_patch`.
- `compatibility_group`.
- `assigned_at`, `updated_at`.
- `assignment_reason`: `race_created`, `compatible_patch`, `manual_migration`, `emergency_rollback`.

Default policy for newly created preset races: `follow_compatible_patch`.

The Worker may update a race assignment only when:

1. No verification session for that race is currently open.
2. The target release is stable for the race's channel.
3. The target release is a `patch` in the same compatibility group.
4. The target release is executable by the participating client's declared capabilities, or the older release remains available as a fallback.

Minor and major releases require a new race or explicit migration.

### 8.5 Verification session

- `id`.
- `race_id`, `user_id`, `activity_id`.
- `release_id`, `release_checksum`.
- `spec_schema_version`, `engine_type`.
- `app_version`, `app_build`, `runtime_capabilities_json`.
- `status`: `created`, `running`, `completed`, `failed`, `abandoned`.
- `result_value`, `confidence`, `failure_reason`.
- `started_at`, `completed_at`.
- `motion_session_id` linking the existing R2 telemetry artifact.

The release fields on this record never change after creation.

## 9. D1 Migration Requirements

Create additive migrations for:

1. `motion_activities`.
2. `verifier_releases`.
3. `activity_channel_releases`.
4. `race_verifier_assignments`.
5. `verification_sessions`.
6. `verifier_evaluation_runs`.
7. New release-identification columns on `motion_sessions`.

Add nullable `verifier_release_id` to `races` for efficient response shaping, while `race_verifier_assignments` remains the auditable assignment record.

Migration rules:

- Never delete or rename the existing race verifier columns during the initial migration.
- Backfill every supported preset activity with a release representing its current production behavior.
- Backfill active preset races to the matching release.
- Preserve `custom_pose_sequence` races unchanged.
- Preserve manual races unchanged.
- Support dual-read during migration: release assignment first, legacy fields second.
- Support dual-write for one app release cycle.
- Do not remove legacy reads until production telemetry shows no unsupported old clients for the agreed compatibility window.

Every migration must have:

- A local D1 migration test.
- A populated-database migration test.
- An idempotency or already-applied check where applicable.
- A rollback note, even when rollback means forward-fixing rather than dropping columns.

## 10. Verifier Specification Contract

The Worker sends declarative data only.

Example shape:

```json
{
  "specSchemaVersion": 1,
  "releaseId": "arm-raises-2026.09.1",
  "activityId": "arm_raises",
  "engineType": "state_machine_v1",
  "measurementType": "repetitions",
  "requiredCapabilities": [
    "pose_landmarks_v1",
    "derived_features_v1",
    "state_machine_v1"
  ],
  "cameraPolicy": {
    "preferredView": "front",
    "requiredRegions": ["torso", "left_arm", "right_arm"],
    "optionalRegions": ["hips"],
    "minimumVisibility": 0.55,
    "minimumPersonScale": 0.18,
    "maximumPersonScale": 0.92,
    "mirrorInvariant": true
  },
  "normalization": {
    "anchor": "shoulder_midpoint",
    "scale": "shoulder_width",
    "translationInvariant": true
  },
  "features": [
    {"id": "left_wrist_above_shoulder", "operator": "relative_y", "a": "leftWrist", "b": "leftShoulder"},
    {"id": "right_wrist_above_shoulder", "operator": "relative_y", "a": "rightWrist", "b": "rightShoulder"}
  ],
  "states": [],
  "transitions": [],
  "timing": {
    "minimumStateMs": 100,
    "cooldownMs": 220,
    "maximumRepMs": 5000
  },
  "feedback": {
    "missing_required_region": "Keep your arms and shoulders in view.",
    "waiting_for_start": "Move to the starting position.",
    "partial_motion": "Finish the movement."
  }
}
```

The production schema must be strictly validated on both Worker and client.

Reject a specification containing:

- Unknown engines, features, landmarks, operators, or feedback keys.
- Non-finite numbers.
- Thresholds outside safe ranges.
- Duplicate feature or state IDs.
- Unreachable states or invalid transitions.
- Excessive payload size.
- A mismatched activity or release ID.
- A checksum mismatch.
- Capabilities not advertised by the app.

## 11. Runtime Families

### 11.1 `state_machine_v1`

For repetitions expressible as a bounded set of pose states and transitions.

Required capabilities:

- Relative landmark positions.
- Joint angles.
- Normalized distances.
- Visibility checks.
- Velocity and direction.
- `all`, `any`, and bounded threshold predicates.
- Hysteresis.
- Stable-duration checks in milliseconds.
- Rearming and cooldown.
- Symmetry and side selection.

### 11.2 `alternating_rep_v1`

For left/right alternating movements. It must prevent one side from repeatedly incrementing without the required opposite-side or neutral transition.

### 11.3 `hold_v1`

For duration goals. It must distinguish readiness, valid hold time, temporary grace, invalid posture, and reset.

### 11.4 `sequence_match_v1`

For a movement represented by curated landmark-sequence references. It may reuse the serializable ideas in Motion V2, but inference must run locally in production. The specification contains references and thresholds, not executable model code.

### 11.5 `native_v1`

Compatibility wrapper for specialized validators not yet representable by generic runtimes. A native release references an allowlisted built-in validator key. New native keys require an app release.

## 12. Camera And Pose Policy

Camera readiness is part of the release, not a global full-body rule.

Requirements:

1. Validate only the regions required by the selected activity.
2. Treat optional regions as quality improvements, not hard blockers.
3. Normalize movement using relevant anatomical anchors.
4. Use person scale ranges rather than one assumed camera distance.
5. Use time durations instead of frame counts for debounce and stability where possible.
6. Make mirror handling explicit and parity-tested.
7. Separate pose-readiness failures from movement-recognition failures.
8. Keep the last good pose briefly through isolated detector misses, without using stale poses for rep decisions.
9. Provide user language, never raw rule IDs.

Close-camera acceptance requirement:

- An upper-body activity must remain usable when legs are outside the frame if all required upper-body regions are visible and person scale remains within the release's supported range.
- A lower-body activity may require lower-body regions and must explain that requirement clearly.

## 13. Worker APIs

### 13.1 Public/client APIs

#### `GET /motion/catalog`

Request information:

- `channel`.
- `appBuild`.
- Runtime capabilities, preferably in a compact request header or query parameter.
- Existing catalog ETag through `If-None-Match`.

Response:

- `catalogVersion`.
- Compatible activities only.
- Stable display metadata.
- Current compatible release ID and checksum.
- Minimum build and required capabilities.
- Cache headers and ETag.

#### `GET /motion/releases/:releaseId`

Returns an immutable, compatible specification. Support ETag and checksum validation. Return a structured unsupported-client response when capabilities do not match.

#### `POST /races`

For a preset race, the client submits `activityId`, not an arbitrary preset verifier specification. The Worker resolves and stores the race assignment transactionally with race creation.

#### `POST /races/:raceId/verification-sessions`

The Worker:

1. Validates race membership and active status.
2. Applies an allowed compatible patch between sessions when policy permits.
3. Freezes the assigned release into a new session.
4. Returns session ID, release metadata, and the specification when the client does not already have the checksum.

#### `POST /verification-sessions/:sessionId/complete`

The request must include release ID, checksum, result, measurement, confidence, and motion-session artifact ID. Reject mismatches with the frozen session.

The existing proof submission remains the authoritative race-progress write. Session completion and proof submission must be idempotently linked to avoid double progress.

### 13.2 Internal APIs

Protected internal endpoints must support:

- Create activity draft.
- Create release draft.
- Validate release.
- Start evaluation run.
- Read evaluation report.
- Promote to internal, beta, or stable.
- Change rollout percentage.
- Roll back channel pointer.
- Disable a release.
- Inspect adoption and failure metrics.

No internal write endpoint may be publicly accessible or protected only by obscurity.

## 14. Flutter Client Architecture

Add these boundaries rather than wiring HTTP calls into screens:

- `MotionCatalogRepository`.
- `VerifierReleaseRepository`.
- `VerifierSpecCache`.
- `RuntimeCapabilityProvider`.
- `RemoteMotionActivityDefinition`.
- `RemoteVerifierSpec` sealed by engine type.
- `VerifierRuntimeFactory`.
- `VerificationSessionController`.

### 14.1 Catalog behavior

- Fetch on authenticated launch and foreground revalidation.
- Use ETag/304 behavior.
- Persist the last known good catalog atomically.
- Fall back to the bundled compatibility catalog when no remote catalog has ever been saved.
- Do not clear a valid catalog because one refresh fails.
- Do not fetch the catalog on every screen build.

### 14.2 Release cache behavior

- Cache by immutable release ID and checksum.
- Validate before committing to disk.
- Write to a temporary file and atomically rename.
- Keep releases referenced by active races.
- Never replace one release ID with different bytes.
- Do not fetch during the live frame loop.
- Permit offline verification only when the exact race-assigned release is valid in cache.

### 14.3 Compatibility behavior

The app advertises strings such as:

- `pose_landmarks_v1`.
- `derived_features_v1`.
- `state_machine_v1`.
- `alternating_rep_v1`.
- `hold_v1`.
- `sequence_match_v1`.
- Built-in native validator keys.

Unknown activity IDs must not default to pushups. Unknown engines or incompatible releases produce a safe unsupported state and telemetry.

### 14.4 UI behavior

The composer consumes the remote catalog after repository resolution. It must not know whether an activity is bundled or remote.

The verification screen receives a resolved session and runtime. It must not look up a movement by title or infer a verifier from display copy.

## 15. Versioning And Update Policy

### 15.1 Patch

Compatible tuning inside the same runtime capability and behavior contract. Examples: visibility threshold, hysteresis, camera scale range, feedback copy, timing tolerance.

May update `follow_compatible_patch` races between sessions.

### 15.2 Minor

Meaningful recognition behavior change that remains within the installed engine but could affect competition outcomes. Applies to new races by default. Existing races require explicit migration.

### 15.3 Major

New engine semantics, measurement behavior, or incompatible specification. Requires a new compatibility group and may require an app update.

### 15.4 Emergency disable

A release may be disabled immediately. New sessions must resolve to the configured fallback release. An already-running session may finish only if the release is not marked security-critical. The action must be hidden if no compatible fallback exists.

## 16. Telemetry And Privacy

Extend the existing motion-session artifact and index with:

- `releaseId` and checksum.
- Engine type and specification schema version.
- Race assignment update policy.
- Required-region coverage.
- Person scale distribution.
- Readiness time.
- Frames received, processed, and dropped.
- Rep candidates, accepted reps, and rejection reasons.
- User feedback label.

Default upload should remain normalized pose landmarks and decision traces, not raw video.

Requirements:

- Document retention periods.
- Delete artifacts when their index record is deleted or retention expires.
- Do not log authentication tokens, raw authorization headers, or private account data inside motion artifacts.
- Gate production uploads according to the product's consent and privacy policy.
- Bound local retry storage and server object size.

## 17. AI-Assisted Improvement Loop

The LLM is an analyst and draft author, not a live verifier or publisher.

Pipeline:

```text
acquire sessions
  -> validate and normalize artifacts
  -> group by activity/release/failure
  -> create a structured analysis packet
  -> LLM proposes causes and a draft change
  -> deterministic schema validation
  -> replay candidate and baseline
  -> human review
  -> controlled publish
```

Required structured LLM output:

- Evidence summary.
- Named failure clusters.
- Proposed change with exact affected fields.
- Expected improvement.
- Regression risks.
- Tests to add.
- Confidence and unsupported assumptions.

The LLM may not:

- Change production state.
- Publish or promote a release.
- Delete sessions.
- Invent landmarks or runtime operators outside the schema.
- Override failed deterministic gates.

## 18. Evaluation Framework

### 18.1 Dataset structure

Each activity evaluation set must contain:

- Valid repetitions from multiple people.
- Near, normal, and far supported camera distances.
- Fast, normal, and slow valid movement speeds.
- Mirrored front-camera input.
- Partial framing allowed by the activity policy.
- Invalid partial movements.
- Similar movements that must not count.
- Repeated start-pose motion that must not double count.
- Detector dropouts and variable frame rate.
- At least one supported-device recording where the current verifier failed.

Keep training/tuning examples separate from held-out release-gate examples.

### 18.2 Deterministic release gates

A candidate cannot advance when any of these fail:

- Schema validity: 100%.
- Release checksum reproducibility: 100%.
- Positive held-out rep recall: at least 92%.
- Negative/confusion false-positive rate: at most 2%.
- Double-count rate: at most 1%.
- No regression greater than 2 percentage points against stable in any required distance or speed stratum.
- Readiness succeeds in at least 95% of clips where required regions are visibly present.
- Runtime p95 processing remains inside the existing real-time frame budget on supported devices.
- No crash, non-finite value, unbounded buffer, or specification mutation.

Early internal releases may use a smaller dataset, but stable promotion requires at least:

- 10 distinct people.
- 100 labeled valid repetitions or equivalent hold/sequence samples.
- 100 negative or confusion samples.
- Coverage across all required camera-distance and speed strata.

Report every dimension separately. Do not hide a failed subgroup inside an aggregate score.

### 18.3 Integration gates

- New compatible activity appears in the composer without a new app binary.
- Race creation stores an immutable release assignment.
- Two participants resolve the same race release.
- A session remains on its release after the stable pointer changes.
- The next eligible session adopts an allowed patch.
- A pinned race does not adopt it.
- Offline cached release works.
- Offline uncached release fails cleanly without falling back to the wrong movement.
- Old capability sets do not receive unsupported activities.
- Rollback changes new eligible sessions without deleting historical data.
- Duplicate completion/proof requests do not double progress.

### 18.4 Production gates

Canary promotion must monitor:

- Session-start failure rate.
- Readiness failure rate.
- Verification completion rate.
- User-reported missed count rate.
- User-reported false count rate.
- Crash and unsupported-spec rate.
- Runtime latency.
- Difference from stable by device, app build, and camera-distance stratum.

Automatic rollback may be added only after the metrics are reliable. Initial rollback remains a human-approved channel change.

## 19. Security And Trust Boundaries

1. The Worker is authoritative for catalog publication, race assignment, and accepted release IDs.
2. The client is not allowed to submit an arbitrary preset specification during race creation.
3. The client validates schema and checksum before execution.
4. The Worker validates session release and checksum on completion.
5. Internal publishing endpoints require explicit authorization and audit records.
6. Specification values use allowlists and bounded numeric ranges.
7. No dynamic Dart, JavaScript, native library, or arbitrary expression evaluation is permitted.
8. Client-side verification is not perfect anti-cheat. Preserve telemetry and an upgrade path for server replay or attestation without blocking this architecture.

## 20. Failure Behavior

| Failure | Required behavior |
|---|---|
| Catalog refresh fails | Use last known good catalog; do not erase it |
| Release download fails | Use exact cached release if valid; otherwise explain retry |
| Checksum mismatch | Reject release, retain prior valid cache, report telemetry |
| Unknown engine | Do not infer or default; mark unsupported |
| Activity disabled | Hide from new races; use fallback policy for existing races |
| Worker channel rollback | New eligible sessions use fallback; running session remains frozen |
| App offline | Cached race release may run locally |
| Proof completion retried | Idempotent result, never duplicate progress |
| Telemetry upload fails | Queue locally within existing age/attempt/storage bounds |
| LLM analysis fails | No production effect; retain deterministic pipeline state |

## 21. Migration And Delivery Plan

### Stage 0: Baseline and contract lock

Deliverables:

- Inventory every current activity, runtime family, validator key, and backend alias.
- Record current verifier versions and current test outcomes.
- Export the Worker and Flutter catalog into one comparison report.
- Create initial replay fixtures from existing tests and motion-session artifacts.
- Freeze JSON contracts and naming used by later stages.

Gate:

- Every supported current activity is accounted for exactly once.
- No unknown mismatch between Flutter and Worker catalogs remains undocumented.

### Stage 1: Registry and immutable releases

Deliverables:

- D1 migrations and domain repository.
- Backfilled activity and release rows.
- Channel pointers.
- Internal read APIs.
- Existing `/races/activities` response backed by the registry while preserving its old fields.

Gate:

- Existing clients receive equivalent catalog data.
- Existing race creation tests remain valid.
- Published rows cannot be mutated through repository methods.

### Stage 2: Race assignment and session pinning

Deliverables:

- Transactional race assignment during preset race creation.
- Verification-session create and complete APIs.
- Release identity in race responses and motion telemetry.
- Idempotent link between session completion and proof submission.

Gate:

- Race, session, proof, and telemetry all identify the same release.
- Pointer changes do not change an open session.

### Stage 3: Flutter remote catalog and cache

Deliverables:

- Capability provider.
- Remote catalog repository with ETag and last-known-good storage.
- Release cache with schema/checksum validation.
- Dynamic activity IDs and legacy adapters.
- Composer reading the repository instead of the compile-time list.
- Bundled fallback catalog for first launch/offline compatibility.

Gate:

- A server-added compatible activity appears without modifying the app source.
- An incompatible activity remains hidden.
- Catalog failure leaves the last known good experience intact.

### Stage 4: Runtime factory and first remote engines

Deliverables:

- Strict verifier specification parser.
- `state_machine_v1`, `alternating_rep_v1`, and `hold_v1` factories.
- Runtime diagnostics mapped to friendly UI guidance.
- Arm raises, squats, and jumping jacks migrated as the representative set.
- Existing native releases retained as rollback fallback.

Gate:

- Remote and baseline replay comparison passes.
- All three activities complete a real app round trip from catalog to proof.

### Stage 5: Evaluation and release workflow

Deliverables:

- Versioned evaluation datasets and runner.
- Baseline-versus-candidate report.
- Internal draft, validate, promote, disable, and rollback APIs.
- Audit records.
- User feedback labels connected to session artifacts.

Gate:

- A deliberately bad candidate is blocked.
- A good candidate canary can be promoted and rolled back without an app release.

### Stage 6: Scale the catalog

Deliverables:

- Migrate remaining suitable activities.
- Keep only justified specialized validators under `native_v1`.
- Add the planned remote activities through specifications and evidence, not one-off client code.
- Document which future movement classes require a new engine capability.

Gate:

- Each stable activity independently passes the release evaluation gates.
- No catalog synchronization list is maintained manually in multiple languages.

### Stage 7: Production rollout

Deployment order:

1. Deploy backward-compatible Worker registry support.
2. Verify migration and old-client responses in the target environment.
3. Release the foundational Flutter build with remote support disabled by default.
4. Enable remote catalog shadow mode and compare decisions.
5. Enable internal accounts.
6. Enable beta cohort.
7. Promote representative activities to stable.
8. Expand activity by activity.

Do not expose a remote activity to stable users before its compatible runtime exists in the minimum supported app build.

## 22. Required Test Matrix

### Worker

- D1 migration from populated current schema.
- Activity/release CRUD restrictions.
- Published-release immutability.
- Capability-filtered catalog.
- Race assignment transaction.
- Patch adoption and pinned-race behavior.
- Session freeze and mismatch rejection.
- Idempotent completion and proof submission.
- Disable and rollback behavior.
- Old request/response compatibility.

### Flutter

- Catalog parsing and unknown-field tolerance.
- Last-known-good catalog behavior.
- Atomic release-cache behavior.
- Checksum rejection.
- Capability negotiation.
- Dynamic activity display and race payload.
- Legacy race resolution.
- Runtime factory for every supported engine.
- Offline cached and uncached behavior.
- Friendly unsupported state.
- No title-based verifier inference for assigned races.

### End to end

- Worker-published activity -> app composer -> race -> session -> local verification -> proof -> race progress.
- Publish compatible patch -> old session unchanged -> next eligible session updated.
- Rollback -> new session returns to previous release.
- Old app capability set -> compatible fallback or hidden activity.
- Custom taught race remains functional.
- Manual race remains functional.

## 23. Performance Requirements

- No network call in the per-frame processing path.
- Catalog and release fetches are deduplicated.
- A release is parsed and validated once per downloaded checksum, not once per frame.
- Runtime buffers are bounded.
- Telemetry upload never blocks camera feedback or proof completion UI.
- Large reference artifacts use R2 rather than inflating every race response.
- Catalog responses contain metadata and release references, not every large specification.

## 24. Observability

Every relevant log or metric must include:

- Activity ID.
- Release ID.
- Engine type.
- App build.
- Session ID when available.
- Outcome or structured failure reason.

Dashboards/reports must answer:

1. Which release is stable for each activity?
2. Which releases are active in races?
3. Which app builds cannot execute the current stable release?
4. Which failure reasons increased after a rollout?
5. Can a failed user attempt be replayed against both old and candidate releases?
6. Was a rollback effective?

## 25. Definition Of Done

The project is complete only when all of the following are true:

1. D1 contains immutable releases and auditable channel pointers.
2. Existing preset races are backfilled without breaking custom or manual races.
3. New preset races store a release assignment.
4. Every verification attempt freezes a release and checksum.
5. Flutter consumes the remote catalog and release cache in production code.
6. The composer can show a newly published compatible activity without source changes.
7. At least three representative activities execute remote specifications locally.
8. Compatible patch adoption works between sessions and never during a session.
9. Pinned-race behavior works.
10. Offline exact-release verification works.
11. Incompatible releases are filtered or safely rejected.
12. Telemetry and user feedback identify the release used.
13. Candidate-versus-baseline replay gates run automatically.
14. Publishing and rollback are auditable and tested.
15. A real device completes the full remote activity and proof flow.
16. Analyze, Worker typecheck, unit, integration, migration, and selected real-session replay tests pass.
17. No duplicate hardcoded cross-language catalog remains authoritative.

## 26. Required Final Handoff

The implementing agent must report:

1. Commits by stage.
2. D1 migrations added and their production application status.
3. API contracts implemented.
4. Flutter runtime capabilities implemented.
5. Activities migrated and those still native.
6. Evaluation dataset composition and per-dimension results.
7. End-to-end flow evidence.
8. Rollback evidence.
9. Old-client and old-race compatibility evidence.
10. Physical-device checks completed and any remaining checks.
11. Exact unresolved risks, without presenting deferred required work as complete.

## 27. Verifier Design Modes

The system must expose a small number of explicit design modes. These are product and engineering contracts, not visual themes. Every activity declares exactly one mode in its current release, and the operator interface changes its fields and validation around that mode.

### 27.1 Mode A: State-based repetition

Use for a repetition described as a start state, one or more movement states, and a completed return or finish state. Examples include pushups, squats, jumping jacks, and arm raises.

The editor must support required body regions, readiness predicates, ordered transition predicates, state durations, a rearm state, hysteresis, cooldown, partial-motion guidance, and confusion movements that must not count. A rep cannot count from one noisy threshold crossing.

### 27.2 Mode B: Alternating repetition

Use when left and right phases must alternate or one complete unit contains two sides. Examples include mountain climbers, alternating lunges, and high knees.

The editor additionally supports which side may begin, whether one side or a pair increments progress, neutral transition requirements, maximum side imbalance, and side-specific visibility fallback.

### 27.3 Mode C: Timed hold

Use for a posture maintained over time, such as a plank, wall sit, or balance hold.

The editor supports entry and valid-hold predicates, grace periods for detector misses and small posture violations, pause-versus-reset conditions, maximum stale-pose duration, and live correction priority. Time accrues only while a fresh pose satisfies the valid-hold contract.

### 27.4 Mode D: Reference sequence

Use when movement shape is better represented by a normalized trajectory than a small hand-authored state machine, including a wave, multi-step gesture, or custom taught movement.

The editor supports curated references, active and required feature sets, temporal resampling, mirror policy, minimum amplitude, completion thresholds, allowed speed variation, start/rearm strategy, and similar negative sequences. References are immutable release artifacts in R2 or inline when safely small. A different reference set creates a different release and checksum.

### 27.5 Mode E: Native compatibility

Use only while a production validator cannot be represented by Modes A-D. The editor exposes an allowlisted built-in validator key and only the remote fields that validator explicitly supports. It never exposes arbitrary expressions.

Native compatibility is a migration tool, not the desired endpoint. Each native activity needs a documented reason, owner, and conversion target.

### 27.6 Mode selection rules

- Choose the simplest mode that captures the movement without false counts.
- Do not choose sequence mode solely to avoid defining clear states.
- Do not force a complex trajectory into a brittle state machine solely to avoid reference data.
- A mode change is at least a minor release and creates a new compatibility group when counting semantics change.
- The stable release names its mode in telemetry and evaluation reports.

## 28. Operator Product And Release Workflow

The first implementation may be a protected internal web surface or authenticated command-line workflow, but it must implement this state model and validation. Direct production database editing is not an acceptable operating workflow.

### 28.1 Activity workspace

For each activity, the operator can see:

- Stable identity and customer-facing metadata.
- Stable, beta, and internal release pointers.
- Current rollout percentage.
- Supported app builds and runtime capabilities.
- Races and sessions assigned to each release.
- Evaluation results by person, distance, speed, framing, device, and confusion class.
- Recent structured failure reasons.
- Release history and audit log.

### 28.2 Draft release creation

An operator starts from an immutable parent release, a mode-specific blank template, or a machine-generated draft from offline analysis. The operator explicitly records the change reason, expected user improvement, change class, compatibility decision, evaluation dataset, and known risks.

Saving a draft runs schema validation but does not expose it to clients.

### 28.3 Preview mode

Preview runs a draft against selected stored sessions and displays baseline versus candidate timelines, every accepted and rejected rep candidate, readiness changes, the first divergence, responsible rules/features, per-stratum metric deltas, and performance impact.

Preview never changes a race, channel pointer, or production session.

### 28.4 Internal mode

Internal releases are available only to authenticated staff/test accounts that advertise the required capability. Internal sessions remain separately identifiable in telemetry.

### 28.5 Beta mode

Beta assignment is deterministic by user or installation hash so an eligible tester does not oscillate between releases. Beta preserves a stable control cohort.

### 28.6 Stable canary mode

A stable candidate begins at a controlled rollout percentage. The operator sees candidate-versus-previous-stable health before increasing rollout. Rollout changes update only channel allocation and never mutate a release.

### 28.7 Full stable mode

Full stable promotion requires deterministic, integration, privacy, and physical-device gates. Promotion records the evaluator version, dataset snapshot ID, metrics, approver, and time.

### 28.8 Rollback mode

Rollback moves a channel pointer to a previous compatible immutable release. The workflow previews affected activities, races, and future sessions before confirmation. Historical sessions retain their release.

### 28.9 Emergency disable mode

Disable prevents new sessions from receiving a release. The system resolves a configured compatible fallback or returns an unavailable state. It never silently substitutes a different activity.

## 29. Runtime And Session State Machines

### 29.1 Verification session lifecycle

Allowed transitions:

```text
created -> running -> completed
created -> abandoned
running -> failed
running -> abandoned
```

Terminal states never transition. Retrying creates a new session while preserving a link to the previous attempt.

### 29.2 Client verification lifecycle

```text
resolve race assignment
  -> negotiate capabilities
  -> load exact release from validated cache or network
  -> create frozen verification session
  -> initialize pose detector and runtime
  -> readiness
  -> active verification
  -> local result
  -> complete session idempotently
  -> submit/link proof idempotently
  -> show race progress
```

The camera cannot enter active verification before the session and release are frozen. Network loss after freezing cannot swap the release. Network loss after local completion preserves one retryable result instead of rerunning and risking duplicate progress.

### 29.3 Per-frame runtime contract

Each runtime consumes a normalized frame and emits a typed result:

- `notReady(reason)`.
- `ready`.
- `tracking(guidance, progress)`.
- `repCandidate(candidateId, evidence)`.
- `repAccepted(candidateId, total)`.
- `repRejected(candidateId, reason)`.
- `holdProgress(validMs, guidance)`.
- `completed(value)`.
- `runtimeError(code)`.

The same candidate ID cannot be accepted twice. Runtime timing uses monotonic elapsed time, not wall-clock time or assumed frame rate.

### 29.4 Pose freshness contract

- The UI may visually hold the last skeleton for a short release-defined period.
- Runtime predicates consume only frames inside maximum decision freshness.
- Missing frames do not manufacture transitions.
- Resuming after a long gap requires readiness/rearm before counting.

## 30. Configuration Safety Model

The declarative format is a closed language.

Required controls:

1. Every operator, landmark, feature, state field, and feedback key is allowlisted.
2. Numeric fields have explicit bounds.
3. State and feature counts have hard limits.
4. Specifications have a hard serialized-size limit.
5. Predicate nesting depth is bounded.
6. References form no cycles unless the engine explicitly supports a bounded state loop.
7. The Worker validates before storage and promotion.
8. Flutter independently validates before caching and execution.
9. A canonical JSON serializer produces the checksum.
10. Published specifications are content-addressable and immutable.

No specification may contain source code, arbitrary mathematical strings, logic-bearing regular expressions, URLs to executable content, or dynamically loaded libraries.

## 31. Environments, Deployment, And Feature Flags

Maintain separate development, staging, and production resources. Never share production D1 or R2 bindings with local or staging environments.

### Development

- Local Worker and local D1 migrations.
- Seed catalog and replay fixtures.
- Unsigned drafts allowed only locally.
- No production user artifacts.

### Staging

- Production-equivalent schemas and authentication.
- Synthetic and approved tester artifacts.
- Full promotion and rollback rehearsal.
- Mobile builds point to staging through explicit build configuration.

### Production

- Migrations use the reviewed deployment path.
- Publishing authorization and audit logging are enabled.
- Release channel changes are separate from Worker code deployment.
- Secrets remain in Cloudflare bindings/secrets, never source control.

Feature flags:

- `remote_motion_catalog_enabled`.
- `remote_verifier_sessions_enabled`.
- `remote_runtime_<engine>_enabled` as temporary migration controls.
- `motion_telemetry_upload_enabled` subject to consent policy.

Flags are kill switches and rollout controls, not permanent alternate architectures. Their owners and removal criteria must be documented. A verifier rollback must not require a Worker redeployment.

## 32. Concrete Implementation Ownership

The implementing agent must confirm exact current paths before editing. The current ownership map is:

### Existing Flutter code to adapt

- `lib/features/races/domain/motion_activity.dart`: replace authoritative enum assumptions with stable network IDs and a legacy adapter.
- `lib/features/races/domain/motion_activity_catalog.dart`: become bundled fallback/legacy data, not the production source of truth.
- `lib/features/races/ai/motion_validators.dart`: expose native validators through allowlisted runtime keys during migration.
- `lib/features/races/ai/preset_motion/preset_movement_work_orders.dart`: migrate representable behavior into release seeds and generic specs.
- `lib/features/races/ai/verifier_runtime.dart`: delegate remote preset verification through `VerifierRuntimeFactory`; preserve manual/custom paths.
- Race API, model, controller, and composer files: retain stable activity and release assignment fields without title inference.
- Existing motion-session artifact pipeline: add release and runtime evidence without putting upload work in the frame loop.

### New Flutter boundaries

- Domain models for catalog entries, release metadata, session assignment, and capability sets.
- Network DTOs separated from validated domain models.
- Catalog repository with bundled fallback and atomic persistence.
- Release repository/cache with checksum verification.
- Generic feature evaluator and runtime implementations.
- Verification session controller owning freeze, local execution, completion, and proof linking.
- Diagnostic exporter describing the exact release and rule path without exposing private tokens.

### Existing Worker code to adapt

- `server/worker/src/domain/raceActivities.ts`: retain only seed or migration compatibility behavior after D1 becomes authoritative.
- Existing race routes and validation: resolve release assignments transactionally.
- Existing motion-session upload/indexing: store release identity and evaluation fields.
- Existing authentication and membership checks: apply to session creation/completion.

### New Worker boundaries

- Catalog/release repository.
- Capability filtering service.
- Race assignment service.
- Verification session service.
- Release validation and canonical-checksum service.
- Protected publishing/evaluation routes.
- Optional Queue consumer for telemetry indexing and replay jobs.

Do not create screen-specific network calls or duplicate business rules between routes.

## 33. Detailed Delivery Artifacts By Stage

Each stage must produce more than code.

### Stage 0 artifacts

- Current behavior inventory by activity.
- Current production baseline replay report.
- API and JSON schema fixtures.
- Capability naming registry.
- Migration risk register.

### Stage 1 artifacts

- D1 migrations and seed data.
- Canonical serializer/checksum vectors shared across Dart and TypeScript tests.
- Release validation report.
- Internal publish/rollback runbook.

### Stage 2 artifacts

- Backfill report with counts by race type and activity.
- Race/session assignment audit queries.
- Idempotency test evidence.
- Old race payload compatibility fixtures.

### Stage 3 artifacts

- Flutter cache corruption/recovery tests.
- Offline behavior evidence.
- Catalog visual regression evidence for long names, hidden activities, and incompatible items.
- Request-count evidence proving no per-frame or per-build fetch loop.

### Stage 4 artifacts

- Three remote specifications covering representative state, alternating/hold, and sequence behavior where applicable.
- Candidate-versus-baseline replay report.
- Real-device frame-time report.
- Mirror and close-camera parity report.

### Stage 5 artifacts

- Evaluation dataset manifest.
- Machine-readable gate report.
- Protected promotion and rollback evidence.
- Audit-log evidence.

### Stage 6 artifacts

- Activity migration matrix: remote, native compatibility, custom, or manual.
- At least one newly added activity proven without Flutter source changes.
- Native-mode conversion backlog.

### Stage 7 artifacts

- Staging rehearsal report.
- Production migration result.
- Canary comparison report.
- Rollback drill.
- Final physical-device acceptance recording or timestamped test log.

## 34. Expanded Test Design

### 34.1 Contract tests

- TypeScript and Dart accept the same valid canonical fixture.
- Both reject every invalid fixture with a stable error code.
- Canonical serialization produces the same SHA-256 on both platforms.
- Unknown optional response fields are tolerated; unknown executable operators are rejected.
- Payload size, numeric bounds, duplicate IDs, bad transitions, and capability mismatch are covered.

### 34.2 Property and fuzz tests

- Runtime never emits decreasing totals.
- One candidate cannot count twice.
- Non-finite pose values never reach comparison logic.
- Random missing frames cannot create a rep.
- Shuffled timestamps are normalized or rejected before runtime use.
- Invalid state graphs cannot hang or allocate without bound.
- Spec decoding has bounded runtime and memory at maximum allowed payload size.

### 34.3 Motion replay tests

For each stable activity, include valid slow/normal/fast attempts; close/expected/far supported framing; allowed partial-body framing; camera mirroring; start-only, half-rep, bounce, and repeated-end-state negatives; confusable actions; detector dropout; and variable frame cadence.

Assertions include count, readiness result, time to first guidance, accepted candidate timestamps, and rejection-reason distribution.

### 34.4 Migration tests

- Empty database migration.
- Production-shaped populated database migration.
- Backfill counts and foreign-key integrity.
- Custom and manual race preservation.
- Recovery after a partial migration failure.
- Old Worker against pre-migration data where deployment ordering requires it.
- New Worker during mixed old/new client traffic.

### 34.5 Failure-injection tests

- Catalog 500, timeout, and invalid JSON.
- Release checksum mismatch.
- Cache write interrupted before atomic rename.
- Network loss immediately before and after session freeze.
- Duplicate completion and proof requests.
- Stable pointer changes during a running session.
- Release disabled during a running session.
- Queue delay/outage.
- R2 artifact unavailable during offline analysis.

### 34.6 UI and usability tests

- The user sees activity-specific framing instead of generic full-body blocking.
- Guidance changes only when the priority reason changes and does not flicker frame by frame.
- Unsupported/offline states explain the next action without technical codes.
- Verification shows the correct movement identity from the assignment.
- A remote activity works in composer, race details, verification, proof result, and history.
- Long localized names and accessibility text scaling do not clip.
- Screen-reader labels identify controls and current verification state.

### 34.7 Physical-device matrix

At minimum test one older supported iPhone, one current iPhone, one lower-tier supported Android device, and one current Android device. Cover front camera portrait use, background/foreground transitions, temporary connectivity loss, and reduced-performance conditions.

Simulator-only evidence cannot close the physical motion acceptance gate.

## 35. Release Metrics And Decision Rules

Every report contains baseline and candidate values, sample sizes, and confidence intervals where meaningful.

Primary metrics:

- Valid-rep recall.
- False-positive and double-count rates.
- Readiness success rate.
- Median and p95 time to readiness.
- Completion rate.
- Median and p95 frame-processing latency.

Guardrail metrics:

- Crash-free session rate.
- Unsupported-spec rate.
- Cache/checksum failure rate.
- Session completion/proof mismatch rate.
- Abandonment after repeated guidance.
- User-reported missed and false counts.

Promotion rules:

- A failed hard gate cannot be overridden because aggregate metrics improved.
- Insufficient sample size is inconclusive, not passing.
- A new serious failure cluster blocks stable promotion.
- Beta rollout pauses when documented guardrails are exceeded.
- Rollback decisions and reasons are written to the audit log.

## 36. Explicit Anti-Loophole Acceptance Rules

The work is not complete while any of the following is true:

1. A remote activity appears in an API response but not the actual Flutter composer.
2. A race stores only an activity name and resolves behavior later without an auditable assignment.
3. The app fetches remote metadata but still chooses recognition through a hardcoded activity switch.
4. A generic runtime exists but no production race uses it end to end.
5. Tests prove schema decoding but never replay motion traces.
6. A patch changes an already-running session.
7. An uncached offline release silently falls back to a different verifier.
8. An old client sees an activity it cannot execute.
9. Publishing mutates a release instead of creating a new immutable release.
10. Rollback requires a mobile build or Worker redeployment.
11. Telemetry omits the release/checksum needed to reproduce behavior.
12. Evaluation reuses tuning clips as held-out proof.
13. An LLM can publish, bypass gates, or participate in the live camera loop.
14. Debug fixtures, forced success, relaxed expectations, or regenerated goldens substitute for behavior evidence.
15. The implementer defers a required stage while claiming the project is complete.

## 37. Final Product Acceptance Scenario

The final demonstration uses a compatible activity absent from the tested Flutter binary's hardcoded production catalog.

1. Create the activity and draft release in the control plane.
2. Validate it against the schema and replay dataset.
3. Promote it through internal and beta to a stable canary.
4. Open the unchanged installed app and refresh the catalog.
5. Confirm the activity appears with correct metadata.
6. Create a race and confirm its immutable release assignment.
7. Open verification on two compatible devices.
8. Confirm both sessions freeze the same race-compatible release.
9. Perform the action close to the camera within its declared framing policy.
10. Confirm local guidance, counting, completion, proof submission, and race progress.
11. Publish a compatible patch while one session remains open.
12. Confirm the open session stays unchanged and the next eligible session receives the patch.
13. Roll back the channel.
14. Confirm the following eligible session receives the prior release.
15. Disconnect the network and verify an already-cached assigned release.
16. Attempt an uncached release offline and confirm a clear non-destructive failure.
17. Show audit, telemetry, replay, and assignment records tying every decision to exact releases and checksums.

Passing this scenario, together with all automated and migration gates, proves that Nuvo can improve and expand motion verification without repeatedly redistributing the app.
