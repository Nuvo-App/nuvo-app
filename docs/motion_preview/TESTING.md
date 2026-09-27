# Testing & visual QA

## Where previews appear in the app

- Route `/race/:id/proof` → `SubmitProofScreen` → `_PreVerifySetupCard`
  (300px preview card above the Begin button).
- Any preset race flows to it: Compete → create/join → race detail →
  Submit Proof.
- Debug rig scrubber: `/dev/rive-calibration` (debug builds only).

## Commands

```bash
# static analysis — required after any Dart change
flutter analyze --no-fatal-infos

# focused preview tests
flutter test test/rive_jumping_jack_preview_test.dart
flutter test test/rive_side_treadmill_preview_test.dart
flutter test test/side_rig_movement_sequences_test.dart
flutter test test/nuvo_semantic_motion_rig_test.dart
flutter test test/rive_pose_controller_test.dart
flutter test test/pose_calibration_test.dart

# rig/asset inspection (run when a preview is blank or bindings changed)
flutter test test/rive_nuvo_stickman_inspection_test.dart
flutter test test/rive_nuvo_stickman_property_probe_test.dart
flutter test test/rive_raw_smoke_test.dart

# screen-level
flutter test test/submit_proof_screen_test.dart
```

## Universal visual checklist (run per preset)

- [ ] correct movement for the activity
- [ ] correct rig/view (side for floor moves + treadmill; front otherwise)
- [ ] character centered, not clipped in the 300px card
- [ ] no blank frame, no flash to fallback
- [ ] correct start pose matches end pose (seamless loop)
- [ ] no dead pause or hard jump at the loop seam
- [ ] timing reads naturally (not frantic, not sluggish)
- [ ] no wrong-limb movement (e.g. arms doing the leg motion)
- [ ] cold restart still shows the preview
- [ ] remote `previewSequence` (if any) still resolves — invalid data must
      fall back to bundled, not break
- [ ] verifier, scoring, and proof flow untouched

## Screenshot loop for the teammate

1. `flutter run`, navigate to `/race/:id/proof` for the target activity.
2. Screenshot the preview card (or screen-record one full loop).
3. Send the screenshot with the preset name — that is the whole bug report
   Claude needs.
