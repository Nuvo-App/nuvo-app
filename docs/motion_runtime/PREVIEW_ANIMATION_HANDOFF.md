# Preview Animation Handoff

Audience: the developer working on **motion preview animations** (the
pre-verify "watch the move" figures and any future preview polish).

Baseline: `main` @ integration checkpoint with `sequence_match_v1` (D1) landed.
This doc describes what exists **now** — not the roadmap.

---

## 1. Current preview pipeline

```
MotionActivityType / remote activityId
  → RiveMovementPreview (lib/features/races/presentation/widgets/rive_movement_preview.dart)
      ├─ remotePreviewJson? → RemotePreviewSpec.tryParse
      │     ├─ rig: 'front' → RemoteFrontKeyframeSequence
      │     └─ rig: 'side'  → RemoteSideKeyframeSequence
      ├─ (fallback, compiled) riveMovementSequenceFor(movement)  → front rig
      └─ (fallback, compiled) sideRigMovementSequenceFor(movement) → side rig
  → poseAt(t) → RivePoseFrame / SideRigPose
  → RivePoseController.apply() → Rive View Model number properties
  → assets/animations/preverify/nuvo_stickman.riv   (front)
    assets/animations/preverify/nuvo_stickman_side.riv (side)
```

Wiring point: `SubmitProofScreen` (~line 607) fetches
`catalog.previewSequenceFor(activityId)` and passes it as
`remotePreviewJson` into `RiveMovementPreview`.

Key files:

- `movement_preview/remote_movement_preview.dart` — `RemotePreviewSpec`
  (rig/durationMs/keyframes), generic interpolators. **Pure data, fail-safe.**
- `movement_preview/rive_movement_sequences.dart` — compiled front-rig
  sequences + `riveMovementSequenceFor(type)` switch.
- `movement_preview/side_rig_movement_sequences.dart` — compiled side-rig
  sequences + `sideRigMovementSequenceFor(type)` switch.
- `movement_preview/rive_pose_frame.dart` — `RivePoseFrame` (8 joint angles,
  `fromJson`/`toJson`).
- `movement_preview/rive_pose_controller.dart` — pushes frames into the Rive
  view model (`leftShoulderAngle` … `rightKneeAngle`); logs missing props.
- `movement_preview/nuvo_semantic_pose.dart` — screen-space pose vocabulary
  (`NuvoDirection2D`, `NuvoArmPose`, …).
- `movement_preview/side_rig_treadmill_preview.dart` — treadmill special case.
- `data/motion_catalog.dart` — `MotionCatalogActivity.previewSequence`
  (decoded from Worker `metadata_json.previewSequence`).

## 2. What is data-driven today

- Full keyframe preview per activity via `metadata_json.previewSequence` in
  the Worker catalog: `{rig: 'front'|'side', durationMs, keyframes[]}`.
- `RivePoseFrame.fromJson` accepts all 8 joint channels per keyframe.
- Timing is spec-driven (`durationMs`, smoothstep interpolation between
  keyframes).
- Remote specs take priority over compiled sequences; a malformed spec parses
  to `null` and falls back silently — previews can never break verification.
- Live example: `0027_remote_preview_arm_raises.sql` ships a previewSequence
  for arm_raises via migration.

## 3. What is still hardcoded

- `riveMovementSequenceFor(MotionActivityType)` — front-rig switch (~10 cases,
  `rive_movement_sequences.dart:33`).
- `hasSideRigMovementPreview` / `sideRigMovementSequenceFor` — side-rig
  switch (pushUps, squats, highKnees, plankHold, sumoSquats, sideLunges,
  deepSquats, squatJacks, jumpSquats, lungeJumps).
- `TreadmillRunningSideSequence` — bespoke treadmill class referenced
  directly in `RiveMovementPreview.initState`.
- Rig asset choice: only two bundled .riv files; no remote asset swap.
- Reduced-motion static pose = `poseAt(0.5)` midpoint — fixed convention.
- Anything keyed on `MotionActivityType` enum is compile-time; remote-only
  activities (e.g. `remote_test_motion`) have **no compiled sequence** — they
  work *only* if the catalog provides `previewSequence`.

## 4. File ownership

SAFE for preview work:

- `lib/features/races/presentation/movement_preview/**`
- `lib/features/races/presentation/widgets/rive_movement_preview.dart`
- `assets/animations/preverify/**`
- `test/rive_*`, `test/side_rig_*`, `test/learned_movement_preview_test.dart`,
  `test/nuvo_semantic_motion_rig_test.dart`
- `docs/motion_runtime/` preview sections, `docs/nuvo_motion_rig.md`

COORDINATE with Agent 4 (motion runtime owner) before touching:

- `lib/features/races/data/motion_catalog.dart`
- `lib/features/races/data/motion_package.dart` (package schema)
- `remote_verifier_spec.dart` / `remote_verifier_runtime.dart`
- `camera_verification_resolver.dart`, `submit_proof_screen.dart`
- `server/worker/src/domain/motion*`, migrations

DO NOT touch:

- `sequence_match_v1` runtime semantics, verifier correctness, proof payload
  identity, release/checksum/channel logic.

## 5. Remote preview direction

The architecture goal: **the app ships the rig + interpolator; Cloudflare
ships data.** A new motion should be able to publish a `previewSequence`
(keyframes + timing) and get a working preview with zero Dart changes. That
is already true for the two bundled rigs.

Planned (NOT yet implemented — don't build on it):

- `preview_v1` package assets pinned to releases (today the preview lives in
  mutable activity metadata, not release-pinned).
- Remote-supplied rig assets beyond the two bundled .riv files.

Invariant, permanently: preview is decorative. Preview failure → fallback
visual. Verifier failure → motion unavailable. Never cross the streams.

## 6. How to run

```bash
flutter pub get
flutter analyze --no-fatal-infos   # baseline: info-level lints only
flutter test test/rive_jumping_jack_preview_test.dart \
  test/side_rig_movement_sequences_test.dart \
  test/nuvo_semantic_motion_rig_test.dart \
  test/rive_pose_controller_test.dart

# Full suite minus the research lab (motion_qa is hour-scale experiments):
flutter test $(find test -name "*_test.dart" | grep -v test/motion_qa)

# Physical iPhone (simulator blocked by Google plugin arch):
flutter build ios --release --no-codesign
flutter run -d <device> --release
```

Rive assets live in `assets/animations/preverify/` and are pubspec-declared —
do not delete or rename. Presentation demo account:
`testing@getnuvo.net` (always demo data) or `sideswifter2010@gmail.com`
(Profile toggle).

## 7. Known issues

- **Fresh clone quirk**: the Podfile requires
  `ios/.symlinks/plugins/google_mlkit_commons/ios/scripts/apple_silicon_simulator`
  at pod-parse time, but the current Flutter tool doesn't regenerate
  `.symlinks` before `pod install` on a brand-new checkout. If `pod install`
  fails with `cannot load such file -- ...apple_silicon_simulator`, run one
  `flutter build ios --release --no-codesign` from a tree that already has
  `.symlinks`, or symlink it manually:
  `mkdir -p ios/.symlinks/plugins && ln -s ~/.pub-cache/hosted/pub.dev/google_mlkit_commons-<ver> ios/.symlinks/plugins/google_mlkit_commons`.
  Pre-existing quirk, not new.
- `test/welcome_opening_cinematic_test.dart` is **intentionally untracked**:
  it was written for a composed-cinematic redesign that never landed (it
  expects text inside `WelcomeOpeningCinematic`, a pure path-painter). Do not
  commit it until the source it tests exists.
- Remote activities with no `previewSequence` render a neutral/first-frame
  pose rather than an animation — expected; the fix is data, not code.
- `submit_proof_screen.dart` remote-preview fetch happens inside the widget
  build path; offline catalog miss → compiled fallback only (no generic idle
  animation for unknown remote motions yet).
- `RemotePreviewSpec` accepts arbitrary keyframe maps; invalid frames are
  dropped per-frame at `RivePoseFrame.fromJson` — noisy-but-valid specs
  degrade gracefully rather than reject.
- `nuvo_stickman.riv` rig has exactly 8 numeric pose channels; a preview
  needing more (fingers, lean, props) requires a new .riv + controller
  properties — a compiled change.
