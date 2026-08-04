# Post-Learning Flow Audit — Teach Nuvo

This audit covers what happens after `SingleSessionTeachingCapture` reaches `learned`. It maps the handoff from `TeachMovementScreen` to test, save/use, and race creation. The explicit recording-based teaching flow (record/stop, 2+ examples, manual builder trigger) is preserved and not reverted.

---

## 1. Post-Learning Flow Map

### What happens after `Movement learned`

`TeachMovementScreen._summaryStep()` renders when `TeachMovementStage.learned` is reached (or a debug fixture is active). It shows:

- Movement name.
- `Movement learned` status.
- **Test movement** primary button.
- If the live test passes: a race creation form with title + target + **Create race with this movement**.
- **Retry teaching** and **Change name** secondary buttons.

### Where the verifier spec lives

- `SingleSessionTeachingCapture._verifierSpec` holds the built `CustomPoseVerifierSpec`.
- It is exposed through `verifierSpec` getter.
- `TeachMovementScreen` reads `_flow.verifierSpec`.
- **No application-level/provider storage exists.** If the user navigates away from `TeachMovementScreen` the spec is lost.
- **No local persistence** (SharedPreferences, file, etc.) is implemented for learned custom movements.

### What `Test movement` does

`TeachMovementScreen._startVerifierTest()`:

1. Takes `_flow.verifierSpec`.
2. Creates `CustomPoseSequenceRuntime(spec: spec, target: 5)..start()`.
3. Reuses the same `CameraController` / image stream already active for teaching.
4. `_handleFrame()` calls `_customRuntime?.update(frame)` on every camera frame and stores `_customUpdate = update?.customPoseUpdate`.
5. `_completeVerifierTest()` is called when `update?.count == 5`.
6. `CustomPoseRuntimeResult` is produced and a `CustomPoseVerifierReadiness` object is set if `result.isVerified` and the valid-frame ratio is >= 55%.

### What `Create race with this movement` does

`TeachMovementScreen._createRaceWithMovement()`:

1. Requires `_readiness?.readyForStage6Persistence == true`.
2. Validates title and target.
3. Calls `RaceController.createCustomRace(title, targetValue, customActivityName, verifierSpec: spec)`.
4. On success, `context.go('/race/${race.id}')`.

### Current path into the rest of race creation

- The user does **not** leave `TeachMovementScreen` to create the race.
- `CreateRaceScreen` (`/races/new`) has no way to receive a `CustomPoseVerifierSpec` or a custom activity name.
- The only way to use a learned movement is the in-screen `_createRaceWithMovement` flow.

---

## 2. Broken or Missing Connections

| # | Missing/broken handoff | Files involved | Impact |
|---|---|---|---|
| A | Learned spec is screen-local, not reusable. | `teach_movement_screen.dart`, `pose_calibration_flow.dart` | The user cannot save the movement for later, cannot navigate away and come back, and cannot reuse it for another race. |
| B | `CreateRaceScreen` cannot receive a custom movement. | `create_race_screen.dart`, `router.dart` | The rest of the race creation flow is bypassed. The user cannot set crew, visibility, rules, etc. for a custom movement race. |
| C | No route or provider carries the spec forward. | `router.dart`, `race_controller.dart` | `TeachMovementScreen` must hold all state or call the backend directly, which couples teaching and race creation. |
| D | `CustomPoseVerifierSpec` is not preserved in `RaceDraft`. | `race_draft.dart` (assumed) | A draft-based race creation cannot be pre-filled with the custom verifier. |
| E | `AiMotionProofScreen` can run the custom runtime, but there is no way to test from `TeachMovementScreen` with a smaller target/honest feedback. | `ai_motion_proof_screen_io.dart`, `teach_movement_screen.dart` | The test surface in `TeachMovementScreen` is the only custom test entry point and is hard-wired to 5 reps. |

---

## 3. Test Movement Audit

### Is it using `CustomPoseSequenceRuntime`?

Yes. `TeachMovementScreen._startVerifierTest()` creates a `CustomPoseSequenceRuntime` from `_flow.verifierSpec`.

### Is it using live pose frames?

Yes. The same `_handleFrame()` stream that feeds the teaching flow also feeds `_customRuntime.update(frame)` while `_testingVerifier == true`.

### Is it using the skeleton overlay?

Yes and no.

- `_cameraStep()` always renders `_cameraPreviewCard()` which shows `CameraPreview` + `_PoseSkeletonPainter` over `_latestFrame`.
- In `_summaryStep()`, the camera is not shown. When the user taps **Test movement**, `_startVerifierTest()` reuses or restarts the camera and the user is returned to `_cameraStep()` because the only switch is `stage == learned ? _summaryStep() : _cameraStep()` — but `learned` is still `learned`, so `_summaryStep()` stays. The camera preview is **not visible during the test** because `_summaryStep()` does not include it.

This is the first concrete UX bug: the test flow tries to run the runtime on the same stream but the UI is on the summary, not the camera step.

### Is feedback honest?

Partially.

- `_testSummary()` shows `count / 5`, sequence progress percentage, `guidance`, and `verificationStatus`.
- `_completeVerifierTest()` declares success only after `count == 5` and `result.isVerified == true` and the valid-frame ratio >= 55%.
- The target of 5 reps is hard-coded. There is no way to “test once and stop” or to pass with fewer reps.
- `verificationStatus` is rendered raw, e.g. `custom_verified` or `custom_failed`. This is Nuvo language only in `customResult.verificationStatus`, but `_testSummary()` displays it directly.
- Debug detail is not gated by `kDebugMode` in `_testSummary()`. It is hidden in `_debugPanel()` only.

### Target/honest issues

- `target: 5` is arbitrary. For testing, the user should be able to do a single good rep and see it recognized.
- `_completeVerifierTest()` completes after `count == 5` in `_handleFrame()` (setState storms aside). This makes testing slow.
- `_testSummary()` does not show states like `Ready`, `Watching`, `Keep going`, `Matched`, `Try again` in a clean way; it shows the runtime's `guidance` string plus a progress percent.

---

## 4. Race Creation Audit

### Can custom verifier specs be carried into race creation?

No, not through the main `CreateRaceScreen`.

- `RaceController.createCustomRace()` exists and works, but it is only called from `TeachMovementScreen._createRaceWithMovement()`.
- `CreateRaceScreen` only supports `createRace()` with a preset `RaceDraft` derived from the text idea / quick start.
- There is no `RaceCreatePrefill` or extra argument that can carry a `CustomPoseVerifierSpec`.
- `go_router` extras are not used for this.

### Can they be used by proof verification?

Yes. The verification side is already wired:

- `Race` model has `customVerifierSpec` and `customActivityName`.
- `CameraVerificationResolver` returns `CameraVerificationSource.customVerifier` when `race.isCustomVerifierRace` is true and the spec is valid.
- `VerifierRuntimeResolver` creates a `CustomPoseSequenceRuntime` from `eligibility.customVerifierSpec` when `verifierType == custom_pose_sequence`.
- `AiMotionProofScreen` loads the race, resolves the verifier, and runs the runtime.

So the **proof verification end of the pipeline is already real**. The break is between teaching and race creation.

### What is real, partial, or missing?

| Area | Status |
|---|---|
| Build a real `CustomPoseVerifierSpec` from recorded examples | Real. |
| Test the spec with live camera + runtime | Partial; the test is not visible because `_summaryStep()` has no camera preview, and the target is hard-coded to 5. |
| Submit proof for a custom race | Real. `RaceController.submitCustomPoseProof()` exists and `AiMotionProofScreen` supports it. |
| Create race with custom movement from teaching | Partial. `TeachMovementScreen` can call `createCustomRace`, but only with title + target. No full race creation form. |
| Save the learned movement for later / reuse | Missing. No local state or persistence. |
| Pass the learned movement into `CreateRaceScreen` | Missing. No route/provider model. |

---

## 5. Minimal Fix Plan

### Priority 1 — Test movement is visible and honest

Risk: low. Touch: `teach_movement_screen.dart` only.

1. Add a `testing` stage or mode to `TeachMovementScreen` that renders the camera preview + skeleton overlay while `_testingVerifier` is true.
2. Lower the test target from 5 to 1 or 3, or let the user stop and finish the test at any time.
3. Replace raw `verificationStatus` in `_testSummary()` with friendly status copy (e.g. `Matched`, `Try again`) derived from `_customUpdate.guidance` and `result.isVerified`.
4. Move debug details into the existing `_debugPanel()` which is only shown in `kDebugMode`.
5. Show the runtime state clearly: `Ready` / `Move into the starting position` / `Begin the movement` / `Keep going` / `Matched`.

### Priority 2 — Learned movement can be reused / not lost on navigation

Risk: medium. Touch: `teach_movement_screen.dart`, `pose_calibration_flow.dart`, plus a small provider or route argument.

Option A (provider):
- Add a small Riverpod provider (`customMovementProvider`) that holds `({String name, CustomPoseVerifierSpec spec, DateTime? savedAt})`.
- `SingleSessionTeachingCapture` / `TeachMovementScreen` writes to it on success.
- `CreateRaceScreen` can watch it.

Option B (go_router extra):
- Pass the `CustomPoseVerifierSpec` and movement name as `state.extra` when navigating from a new `Use this movement` button to `/races/new`.
- Simpler, but the spec is lost if the user navigates back.

Recommended: **Option A provider** because it is the smallest local state mechanism and survives within the session.

### Priority 3 — Continue into `CreateRaceScreen` with the learned movement

Risk: medium. Touch: `create_race_screen.dart`, `router.dart`, `race_controller.dart`, `teach_movement_screen.dart`, `race_draft.dart`.

1. Add a `RaceCreatePrefill` or `RaceDraft` source that carries `customActivityName` and `verifierSpec`.
2. Update `CreateRaceScreen` to detect the provider/extra and switch to `RaceController.createCustomRace()`.
3. Replace the in-screen race creation form with a **Use this movement** or **Create race with this movement** button that pushes to `/races/new` with the spec.
4. Disable or block the button when `verifierSpec == null`.

### Priority 4 — Reduce slowness / glitchiness

Risk: low to medium. Touch: `teach_movement_screen.dart`, `pose_calibration_flow.dart`.

1. Avoid `_initializeCamera()` on every summary/test toggle. Keep the stream and just swap the runtime/overlay.
2. Ensure `_stopImageStream()` / `_startImageStream()` are not called redundantly in `_ensureCameraStream()`.
3. Remove the 600ms artificial `buildDelay` in the teaching flow (or make it visual only, not a logic pause).
4. Debounce `setState()` in `_handleFrame()` or use a `ValueNotifier` for the camera/pose feed to avoid rebuild storms.
5. Do not recreate `CustomPoseSequenceRuntime` on `setState` / stage changes.

### Priority 5 — Tests

- `test/teach_movement_test.dart` (or extend `test/pose_calibration_test.dart`):
  - Learned movement exposes a non-null `verifierSpec`.
  - Test movement updates the runtime with matching frames and produces a verified `CustomPoseRuntimeResult`.
  - Test movement with mismatched frames does not verify.
  - Continue button is disabled when `verifierSpec` is null.
- `test/custom_pose_sequence_runtime_test.dart` already covers matching/mismatched, so no new tests required there unless the runtime is changed.

---

## 6. Files to edit

| Priority | Files |
|---|---|
| 1 | `lib/features/races/presentation/custom_pose/teach_movement_screen.dart` |
| 2 | `lib/features/races/presentation/custom_pose/teach_movement_screen.dart`, `lib/features/races/ai/custom_pose/pose_calibration_flow.dart` (to expose build result cleanly), new or existing provider |
| 3 | `lib/features/races/presentation/create_race_screen.dart`, `lib/app/router.dart`, `lib/features/races/presentation/race_controller.dart`, `lib/features/races/domain/race_draft.dart` (verify) |
| 4 | `lib/features/races/presentation/custom_pose/teach_movement_screen.dart` |
| 5 | `test/pose_calibration_test.dart` or new `test/teach_movement_test.dart` |

### What will NOT change

- `CustomPoseSequenceBuilder` (already supports 2 examples and manual trimming).
- `CustomPoseSequenceRuntime` (real verification is already wired).
- `CustomPoseVerifierSpec` / validation.
- `CameraVerificationResolver` / `AiMotionProofScreen` proof verification.
- `race_api.dart` / `race_repository.dart` backend contract.
- `motion_validators.dart`, `pose_detector_service.dart`, `camera_image_converter.dart`.
- `pubspec.yaml`, iOS native files, auth, backend.

---

## 7. Task declaration

```
Files to read:      lib/features/races/presentation/custom_pose/teach_movement_screen.dart,
                    lib/features/races/ai/custom_pose/pose_calibration_flow.dart,
                    lib/features/races/presentation/create_race_screen.dart,
                    lib/app/router.dart,
                    lib/features/races/presentation/race_controller.dart,
                    lib/features/races/domain/race_draft.dart,
                    lib/features/races/data/race_models.dart

Files to edit:      lib/features/races/presentation/custom_pose/teach_movement_screen.dart,
                    lib/features/races/ai/custom_pose/pose_calibration_flow.dart,
                    (new or existing provider for learned custom movement),
                    lib/features/races/presentation/create_race_screen.dart,
                    lib/app/router.dart,
                    lib/features/races/presentation/race_controller.dart,
                    lib/features/races/domain/race_draft.dart,
                    test/pose_calibration_test.dart

Behavior changes:   - Test movement shows the camera + skeleton overlay and gives honest 1/3-rep feedback.
                    - Learned movement is surfaced in a session provider so it survives navigation.
                    - A "Use this movement" button opens the real race creation flow with the spec pre-filled.
                    - Continue is disabled without a valid spec.

What will NOT change: - Recording-based teaching flow.
                    - Builder, runtime, verifier spec, or resolver logic.
                    - Backend contracts or verification math.
                    - Auth / iOS / camera bridge / pubspec.

Risk level:         high (crosses teaching, creation, and state; touches > 5 files)
```

Because this is high risk and touches more than 5 files, explicit approval is requested before editing.
