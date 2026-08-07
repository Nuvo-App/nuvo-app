# Teach Nuvo — Flow & Reliability Audit

This audit is the basis for the next coding pass. It does not propose redesigning the verifier architecture; it focuses on making the existing `SingleSessionTeachingCapture`, `CustomPoseSequenceBuilder`, and `CustomPoseSequenceRuntime` flow feel simple, retryable, and reliable.

## 1. Current Flow Map

### Flow states

| Stage | What the user sees | What the system is doing | Files |
|---|---|---|---|
| `TeachMovementStage.name` (`teach_movement_screen.dart:420-421`) | Name input + **Continue** | `_flow.setMovementName(...)` validates; `_initializeCamera()` starts | `teach_movement_screen.dart`, `pose_calibration_flow.dart:96-104` |
| `setup` | "Tap Start teaching when you\'re ready." + **Start teaching** | Camera is streaming; no capture yet | `pose_calibration_flow.dart:100-101` |
| `countdown` | 3 → 2 → 1 → Go | `tickCountdown()` waits, then `_startPoseCapture()` | `pose_calibration_flow.dart:106-127` |
| `startPose` | "Hold still in your starting position." | `StablePoseCapture` collects 8 consecutive frames with `stability >= 0.92` (`stable_pose_capture.dart:29-33`) | `pose_calibration_flow.dart:129-135`, `stable_pose_capture.dart` |
| `capturing` | "Do the movement a few times. Pause briefly at the start." + 3 dots | `SingleSessionTeachingCapture` watches for departure/return; `PoseDemonstrationCapture` records each rep; accepts 2–3, rejects bad ones, then builds | `pose_calibration_flow.dart:137-184`, `pose_demonstration_capture.dart` |
| `building` | "Learning your movement…" spinner | `CustomPoseSequenceBuilder.build(...)` runs after 600ms delay | `pose_calibration_flow.dart:224-253`, `custom_pose_sequence_builder.dart:19-129` |
| `learned` / `failed` | "Movement learned" + **Test movement** + **Teach again** OR an error + **Teach again** | If success, `verifierSpec` is set; if fail, `_lastBuildFailure` is set and both buttons call `_restart()` | `teach_movement_screen.dart:624-674` |

### Screen-level flow

- `_nameStep()` is shown only in `TeachMovementStage.name`.
- `_cameraStep()` is shown in `setup`, `countdown`, `startPose`, `capturing`, `building`.
- `_summaryStep()` is shown in `learned` or `failed`.
- `_restart()` in `TeachMovementScreen` calls `_flow.restart()`, then clears `_nameController` and stops the camera (`teach_movement_screen.dart:253-270`).

## 2. Failure Points

### F1. Any retry throws the user back to the movement-name step
- `SingleSessionTeachingCapture.restart()` resets `_stage = TeachMovementStage.name` and `_movementName = ''` (`pose_calibration_flow.dart:330-331`).
- `TeachMovementScreen._restart()` also clears `_nameController.text` (`teach_movement_screen.dart:255`).
- **Impact:** The "Start over" button, the "Teach again" button, and the implicit reset after every failure all force retyping the name. This is the single biggest source of "fragile and annoying."

### F2. No way to retry only the part that failed
- If `startPose` is not stable, the user is stuck in `startPose` until stable or presses **Start over**.
- If one rep is rejected, the user must keep capturing; there is no "Remove last bad rep" or "Try just that one again."
- If the builder fails with 2 accepted examples, the only offered action is capture one more. If the start pose itself was noisy, capturing more won\'t help.
- **Impact:** Users cannot surgically fix the problem. They are forced to repeat from the beginning.

### F3. No partial-progress visibility
- `_progressDots()` shows three dots, filling them as `_accepted.length` grows (`teach_movement_screen.dart:540-558`).
- There is no textual count ("1 of 3 examples"), no list of accepted/rejected examples, and no hint about how many attempts remain (max 5).
- **Impact:** Users do not know whether they are close or far from finishing.

### F4. Failure state is a dead end with one button
- In `failed`, `_summaryStep()` shows only `_flow.message` in danger color and a **Teach again** button that calls `_restart()` (`teach_movement_screen.dart:660-673`).
- There is no "Try again with the same name," no "Show debug details" (even behind `kDebugMode`), no way to go back one step.
- **Impact:** Failure feels terminal. The user has no mental model of what to change.

### F5. `markInterrupted()` does not transition state
- `SingleSessionTeachingCapture.markInterrupted()` only interrupts the current `PoseDemonstrationCapture` and sets a message (`pose_calibration_flow.dart:309-315`).
- The stage stays in `capturing`. There is no automatic pause/failed/reset.
- **Impact:** If the app becomes inactive during a rep, the capture is silently ruined and the user only sees "Try again from the start" without an actionable next step.

### F6. `StablePoseCapture` timeout is silent and unrecoverable
- `StablePoseCapture` gives up after 2500ms with `message: 'Hold still and try again.'` (`stable_pose_capture.dart:49-55`).
- The flow never transitions out of `startPose`; the user\'s only option is **Start over**, which loses the name.
- **Impact:** Users who cannot hold still fast enough are punished with a full reset.

### F7. The only retry action resets the camera
- `_restart()` calls `_stopCamera()`, so the user re-walks camera permission/startup.
- **Impact:** Heavy penalty for a failed or interrupted rep.

## 3. Training Reliability Issues

### T1. Similarity thresholds are too high for real camera noise
- `SingleSessionTeachingCapture._departureThreshold = 0.98` and `_returnThreshold = 0.98` (`pose_calibration_flow.dart:91-92`).
- `PoseSimilarity` already has a `minValidFeatureRatio` of 0.35 for `_startSimilarity`, so `similarity = 0` if too few features are valid.
- A score of 0.98 is near-perfect. Real camera frames with slight wobble, ML Kit jitter, or breathing will often sit around 0.97–0.99. Movements that should register may not depart for 3 consecutive frames, causing missed or short captures.
- **Risk:** Reps are not detected consistently; the `too_short` and `static_capture` errors appear unpredictably.

### T2. Start-pose capture is too strict
- `StablePoseCapture.requiredStableFrames = 8` with `stabilityThreshold = 0.92` (`stable_pose_capture.dart:28-32`).
- The timeout is 2500ms.
- Real users take more than 2.5s to settle. The 8-frame count and 0.92 threshold reject slight sway.
- **Risk:** Hard to reach `capturing`; users think the app is broken.

### T3. `return-to-start` is a hard gate for every movement
- `SingleSessionTeachingCapture` only finishes a rep after 3 consecutive frames at `_returnThreshold` (0.98) similarity to the start pose (`pose_calibration_flow.dart:173-178`).
- Small gestures like a wave do not have a long pause in the start position; the return is brief. The 3-frame rule at 0.98 may demand the user freeze too long.
- The same model is used for squats, jumps, and hand waves. A squat has a clear bottom and a clear return; a wave does not.
- **Risk:** Waving and small upper-body motions are accepted only if the user happens to pause exactly right.

### T4. Builder active-feature selection can reject small but meaningful movements
- `_selectActiveFeatures` (`custom_pose_sequence_builder.dart:268-340`) requires:
  - `minCoverage >= 0.82`
  - `averageAmplitude >= _movementThreshold` (`0.22` for coord, `0.10` for angle, `0.16` for distance)
  - `_amplitudeConsistency >= 0.45`
- A wave may not reach `0.22` on every active coord feature in all 3 demonstrations.
- `averageAmplitude` is computed across demos; if one demo is slightly smaller, the feature is rejected.
- **Risk:** `no_active_features` or `mostly_static` failures for legitimate small movements.

### T5. Builder consistency is too high for real humans
- `_measureConsistency` (`custom_pose_sequence_builder.dart:400-432`) fails if `lowest < 0.62` or `overall < 0.70`.
- Real people do not repeat a movement within 0.62–0.70 similarity across all active features on every rep.
- The wave fixture in `test/pose_calibration_test.dart` passes because it is identical each time. Real waves vary.
- **Risk:** `inconsistent_demonstrations` is the most common real-world failure.

### T6. `completionStrategy` is all-or-nothing
- `_completionStrategy` (`custom_pose_sequence_builder.dart:499-509`) requires either 0 or 100% of demos to return to start.
- If 2 of 3 demos return but 1 does not, it throws `ambiguous_completion_strategy`.
- **Risk:** Mixed timing across demonstrations kills the build even when the movement is clear.

### T7. Demonstration count is capped at 3
- `_validateCalibration` rejects `demonstrations.length` outside `[2, 3]` (`custom_pose_sequence_builder.dart:148-153`).
- `SingleSessionTeachingCapture._maxAttempts = 5` but the builder only accepts the first 2–3.
- If one accepted example is bad, the user cannot delete it and re-capture without restarting.
- **Risk:** A single bad accepted demo locks the user into a bad verifier or a failed build.

### T8. `minStartSimilarity` static guard is brittle
- After `_cleanDemonstration`, if `minStartSimilarity > 0.99`, it throws `no_clear_movement` (`custom_pose_sequence_builder.dart:230-233`).
- A slow or rounded movement may never drop below 0.99 on some frames.
- **Risk:** Legitimate movements are rejected as static.

## 4. Verification Reliability Issues

### V1. `requiredFeatureIds` and `activeFeatureIds` are the same set
- In `CustomPoseSequenceBuilder` the spec is built with `requiredFeatureIds: activeSelection.activeFeatureIds` and `activeFeatureIds: activeSelection.activeFeatureIds` (`custom_pose_sequence_builder.dart:83-85`).
- `CustomPoseSequenceRuntime._qualityFor` then uses `requiredFeatureIds` for `requiredCoverage` and `activeFeatureIds` for `activeCoverage` (`custom_pose_sequence_runtime.dart:465-490`).
- Because both are the same, the runtime has no concept of "must-see core body." It only checks the moving features.
- **Risk:** For a hand-only movement, the runtime may count a rep even when the rest of the body is missing or misaligned. For a full-body movement, it may reject a valid rep because one active feature is briefly occluded.

### V2. Reset/completion thresholds are derived from demonstration consistency
- `_deriveThresholds` (`custom_pose_sequence_builder.dart:563-591`) sets:
  - `sequenceSimilarity` = `(lowestPairScore - 0.08).clamp(0.62, 0.88)`
  - `completionSimilarity` = `(0.76 + startPoseStability * 0.08).clamp(0.74, 0.88)`
  - `resetSimilarity` = `(0.78 + startPoseStability * 0.10).clamp(0.78, 0.92)`
- `startPoseStability` is hardcoded to `1` in `_tryBuild` (`pose_calibration_flow.dart:264`). So `resetSimilarity` is always `0.88` and `completionSimilarity` is `0.84`.
- A 0.88 reset threshold is hard to hit in real camera noise. If the user\'s start pose is close but not 0.88, the runtime never arms or never counts a return.
- **Risk:** Trained movements often pass tests in fixtures but fail in the live verifier.

### V3. Arming requires 3 frames at reset similarity
- `_handleWaitingForStart` requires `_resetSimilarity >= resetSimilarityThreshold` for 3 consecutive frames (`custom_pose_sequence_runtime.dart:201-220`).
- Same as the teaching start-pose gate: real users wobble.
- **Risk:** The verifier is slow to arm; users repeat the movement before the runtime is ready.

### V4. `completionAfterSequenceReturn` needs 0.96 sequence progress
- `_handleReturnCompletion` requires `_sequenceProgress >= 0.96` before counting a rep (`custom_pose_sequence_runtime.dart:299-300`).
- `_sequenceProgress` is derived from the highest template index matched.
- If the movement is fast and the canonical sequence is long (24 frames), 0.96 means matching all but the last 1–2 frames. A rushed or slightly off rep can fail at the last frame.
- **Risk:** False negatives on fast or imperfect reps.

### V5. Progress timeout is short for slow movements
- `customPoseProgressTimeoutFrames = 18` (~2.1s at 120ms frame interval) (`custom_pose_sequence_runtime.dart:15`).
- Slow, controlled movements (squats, controlled waves) can exceed this.
- **Risk:** `progress_timeout` invalidates valid slow reps.

### V6. Cooldown + return logic assumes the same start for every movement
- `_handleCooldown` (`custom_pose_sequence_runtime.dart:335-352`) and `_handleWaitingForReset` (`custom_pose_sequence_runtime.dart:317-333`) are built around a single `resetSimilarityThreshold`.
- Movements that finish in a different but stable position (e.g., a lunge that ends low) have no concept of a "soft" or "terminal-only" reset.
- **Risk:** Movements that do not return to the exact start are impossible to verify, even if they are clear.

### V7. Confidence score is not a verification signal
- `_confidence()` blends count, progress, current similarity, valid ratio, and valid frames (`custom_pose_sequence_runtime.dart:532-543`).
- It is returned as a number but never translated into guidance for the user.
- **Impact:** Users have no idea whether they are "close" or "far" from a successful rep.

## 5. Proposed Fix Plan

Prioritized by user impact and implementation risk. Low-risk items are mostly UI/copy. Medium/high touch the capture/builder/runtime math.

### P1. Persist movement name and separate retry actions (high impact, medium risk)
- Make `SingleSessionTeachingCapture.restart()` keep the name and start from `setup` instead of `name`.
- Add a `resetToCapture()` method that keeps the name and start pose but clears accepted/rejected attempts.
- Add a `resetExamples()` method that keeps the name and start pose but clears accepted/rejected and re-enters `capturing`.
- Update `TeachMovementScreen` buttons:
  - **Teach again** / **Start over** should not clear `_nameController`.
  - Add **Retry capture** when in `failed` or after rejection.
- Files: `pose_calibration_flow.dart`, `teach_movement_screen.dart`, `test/pose_calibration_test.dart`.

### P2. Show example count and status clearly (high impact, low risk)
- Replace 3-dot-only progress with "`accepted` of `required` examples" and, when rejecting, "`attempts` attempts, try again."
- Add a stage-status pill: `Waiting for start pose`, `Watching`, `Example captured`, `Learning`, `Movement learned`, `Try again`.
- Files: `teach_movement_screen.dart`.

### P3. Add example-level controls (high impact, medium risk)
- Add `SingleSessionTeachingCapture.removeLastAccepted()` and `removeLastRejected()`.
- Add UI actions behind a small list/overflow: **Remove last example**, **Clear all examples**.
- Keep the start pose unless the user explicitly chooses **Reteach start pose**.
- Files: `pose_calibration_flow.dart`, `teach_movement_screen.dart`, `test/pose_calibration_test.dart`.

### P4. Re-capture start pose without full reset (high impact, medium risk)
- Add `SingleSessionTeachingCapture.resetStartPose()`.
- Add UI button **Hold still again** or **Reteach start pose** when in `capturing` or `failed`.
- Files: `pose_calibration_flow.dart`, `teach_movement_screen.dart`.

### P5. Loosen start-pose stability gate (medium impact, low risk)
- Reduce `StablePoseCapture.requiredStableFrames` from 8 to 5.
- Increase `timeout` from 2500ms to 5000ms or make it adaptive.
- Lower `stabilityThreshold` from 0.92 to 0.88.
- File: `stable_pose_capture.dart`, `test/pose_calibration_test.dart`.

### P6. Introduce a per-movement capture "mode" or auto-adaptive thresholds (high impact, high risk)
- Add a `TeachingMode` enum: `fullBody`, `upperBody`, `handsOnly`.
- Each mode drives `SingleSessionTeachingCapture` thresholds and `PoseDemonstrationCapture` min/max duration.
  - `fullBody`: 0.95 departure/return, 600ms min, 8s max.
  - `upperBody`: 0.92, 400ms, 5s.
  - `handsOnly`: 0.88, 200ms, 4s, smaller `consecutiveThreshold` for departures.
- This preserves the architecture but lets small waves train without breaking larger movements.
- Files: `pose_calibration_flow.dart`, `teach_movement_screen.dart`, `pose_demonstration_capture.dart`, `test/pose_calibration_test.dart`.

### P7. Relax builder consistency / active-feature thresholds (high impact, medium risk)
- Lower `_measureConsistency` `lowest` from 0.62 to 0.52 and `overall` from 0.70 to 0.60.
- Lower `_selectActiveFeatures` `_amplitudeConsistency` from 0.45 to 0.35.
- Lower `_movementThreshold` for `coord` from 0.22 to 0.16.
- Files: `custom_pose_sequence_builder.dart`, `test/custom_pose_sequence_builder_test.dart`.

### P8. Make return-to-start a soft cue instead of a hard gate (high impact, medium risk)
- Add `CustomPoseCompletionStrategy.completionAtTerminalPose` support for small movements that do not return cleanly.
- Allow the user to choose or auto-detect "one-way" vs "return" completion in the UI.
- Runtime already supports both; the teaching side forces return by trimming to start.
- Files: `pose_calibration_flow.dart`, `custom_pose_sequence_builder.dart`.

### P9. Derive more forgiving runtime thresholds (medium impact, medium risk)
- In `CustomPoseSequenceBuilder._deriveThresholds`, base `resetSimilarity` on actual start-pose stability, not hardcoded `1`.
- Cap `resetSimilarity` at 0.85 and `completionSimilarity` at 0.80.
- Consider adding a minimum `sequenceSimilarity` of 0.55 for all custom verifiers.
- Files: `custom_pose_sequence_builder.dart`, `pose_calibration_flow.dart` (pass real start stability), `test/custom_pose_sequence_builder_test.dart`, `test/custom_pose_sequence_runtime_test.dart`.

### P10. Add debug telemetry panel behind `kDebugMode` (low impact, low risk)
- Show in `_debugPanel()`:
  - Current `similarity`, `lastSimilarity`, `resetSimilarity`, `completionSimilarity`.
  - Accepted example indexes, rejected reasons, builder diagnostics.
  - `CustomPoseRuntimeUpdate` fields during testing.
- File: `teach_movement_screen.dart`.

## 6. Recommended First Implementation Pass

Keep this narrow. It should make the flow feel dramatically less fragile without replacing the architecture.

1. **Make the movement name survive retries**
   - Edit `SingleSessionTeachingCapture.restart()` to keep `_movementName` and start at `setup`.
   - Edit `TeachMovementScreen._restart()` to not clear `_nameController` and re-initialize camera.
   - Add a `SingleSessionTeachingCapture.resetToCapture()` for clearing attempts but keeping name/start pose.
   - Files: `pose_calibration_flow.dart`, `teach_movement_screen.dart`.

2. **Add a "Retry teaching" action that preserves name + start pose**
   - In `failed` and `learned` summary, rename **Teach again** to **Retry teaching** and call `resetToCapture()`.
   - Keep a separate **Change name** action to go back to `name` if wanted.
   - Files: `teach_movement_screen.dart`.

3. **Show example count and a status pill**
   - Replace dot-only progress with text: "`acceptedCount` of `_minAccepted` examples captured".
   - Add a small status pill above the camera card keyed to `_flow.stage`.
   - Files: `teach_movement_screen.dart`.

4. **Add "Remove last example" and "Clear examples" behind the camera UI**
   - Add `removeLastAccepted()` and `clearExamples()` to `SingleSessionTeachingCapture`.
   - Add small secondary buttons in `capturing` and `failed`: **Remove last**, **Clear examples**, **Reteach start pose**.
   - Files: `pose_calibration_flow.dart`, `teach_movement_screen.dart`, `test/pose_calibration_test.dart`.

5. **Loosen start-pose stability and timeout**
   - `requiredStableFrames: 6`, `stabilityThreshold: 0.88`, `timeout: 5000ms`.
   - Files: `stable_pose_capture.dart`, `test/pose_calibration_test.dart`.

### Tests to add/update
- `SingleSessionTeachingCapture name persists through restart and resetToCapture`
- `SingleSessionTeachingCapture can remove the last accepted example and continue`
- `SingleSessionTeachingCapture can clear examples and keep start pose`
- `StablePoseCapture captures with 6 stable frames and longer timeout`
- `TeachMovementScreen buttons do not reset name` (widget test, optional)

### Expected behavior improvement
- A failed or interrupted teaching session no longer feels like starting over.
- The user can see how many examples are in and what Nuvo wants next.
- The user can discard bad examples or try again from the start pose without renaming.
- The start-pose gate is less punishing.

## 7. What Not To Change

These areas are out of scope and should stay untouched unless explicitly approved:

- `lib/features/auth/data/*` and auth flow
- `lib/features/races/ai/motion_validators.dart`
- `lib/features/races/ai/pose_detector_service.dart` and `camera_image_converter.dart`
- `lib/features/races/presentation/ai_motion_proof_screen.dart`
- `lib/features/races/data/race_api.dart` and `race_repository.dart`
- `lib/features/races/presentation/race_controller.dart`
- `lib/features/races/ai/custom_pose/pose_similarity.dart` core math
- `lib/features/races/ai/custom_pose/pose_normalizer.dart`
- `ios/Podfile`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist`
- `pubspec.yaml`, `pubspec.lock`
- `server/worker/` backend

The verifier architecture — `PoseNormalizer`, `StablePoseCapture`, `PoseDemonstrationCapture`, `CustomPoseSequenceBuilder`, `CustomPoseVerifierSpec`, `CustomPoseSequenceRuntime` — should be reused, not replaced. Only thresholds, copy, flow state, and screen controls are in scope.
