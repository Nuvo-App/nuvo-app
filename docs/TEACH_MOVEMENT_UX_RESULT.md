# Teach Movement UX Result

## Summary
The Teach Movement flow has been rewritten as a single-session, consumer-style capture experience. The old developer-oriented steps (separate start pose capture, three manual demonstration rows, retry links, and a "Build movement template" button) are gone. In their place is a camera-first flow that asks the user for a movement name, counts down, silently captures a stable start pose, records the movement, and then automatically builds the verifier behind a "Learning your movement…" message.

## What changed

### State machine: `SingleSessionTeachingCapture`
- `lib/features/races/ai/custom_pose/pose_calibration_flow.dart` now owns the new state machine.
- One tap starts a 3-second countdown, then automatically captures a stable start pose.
- Repetitions are segmented by departures from, and returns to, the start pose.
- Bad or too-short examples are silently discarded and the user is asked to repeat (`"Do that one more time."`, `"Do the movement a little more slowly."`, etc.).
- When two or more strong examples are captured, `CustomPoseSequenceBuilder` runs automatically.
- Internal builder error codes (`inconsistent_demonstrations`, `low_feature_coverage`, `no_active_features`, `ambiguous_completion_strategy`, etc.) are translated to friendly messages in production and only exposed in `kDebugMode`.

### UI: `TeachMovementScreen`
- `lib/features/races/presentation/custom_pose/teach_movement_screen.dart` was rewritten.
- New screen: name entry, single camera teaching screen, countdown, progress dots (`● ○ ○`), and automatic capture.
- Summary state shows "Movement learned", a "Test movement" button, and a race creation form when the live test passes.
- Debug diagnostics live behind a `kDebugMode` panel only.

### Tests
- `test/pose_calibration_test.dart` now covers the new `SingleSessionTeachingCapture`:
  - one tap starts countdown and captures start pose
  - return-to-start divides repetitions
  - bad example discarded with a normal, non-technical message
  - attempt count bounded to 5
  - builder runs automatically after accepted examples
- Existing `custom_pose_sequence_builder_test.dart` and `custom_pose_sequence_runtime_test.dart` still pass.

## Verification

```bash
flutter analyze --no-fatal-infos
# No issues found

flutter test test/pose_calibration_test.dart test/custom_pose_sequence_builder_test.dart test/custom_pose_sequence_runtime_test.dart
# All tests passed

flutter build ios --no-codesign
# Built build/ios/iphoneos/Runner.app (69.4MB)
```

## Manual iPhone test plan
1. Open the project in Xcode and select a signing team.
2. Run `flutter run` with a physical iPhone connected, or install `build/ios/iphoneos/Runner.app` after codesigning.
3. Navigate to **Teach Nuvo**.
4. Name the movement, for example `Arms overhead`.
5. Tap **Start teaching**.
6. Hold still in the starting position (arms at sides) while the countdown completes.
7. When recording begins, perform the movement three times, pausing briefly in the starting position between each repetition.
8. Expected result:
   - Progress dots advance: `● ○ ○`, then `● ● ○`, then `● ● ●`.
   - After the third good example, the screen shows "Movement learned".
   - Tap **Test movement**, perform the movement again, then create a race with it.

## Notes
- The build output is unsigned (`--no-codesign`). A provisioning profile / signing team is needed to install on a physical device.
- Existing verifier builder and runtime tests are preserved; no backend changes were made.
