# Motion Preview — the pre-verify animation system

**What it is:** the looping character animation shown on the Submit Proof
screen before the camera opens ("here's the move you're about to prove").
It is **decorative only** — the camera verifier never reads it.

## The pipeline (all existing — do not redesign)

```
previewSequence (remote, optional)
  Worker GET /races/activities → motion_activities.metadata_json.previewSequence
  → MotionCatalogSnapshot.previewSequenceFor(activityId)
        │ valid RemotePreviewSpec?            │ absent/invalid
        ▼                                     ▼
Remote{Front,Side}KeyframeSequence   bundled compiled sequence
(remote_movement_preview.dart)       (rive_movement_sequences.dart /
                                      side_rig_movement_sequences.dart)
        └──────────────┬──────────────────────┘
                       ▼
            RiveMovementPreview
   (widgets/rive_movement_preview.dart)
                       ▼
   front rig: assets/animations/preverify/nuvo_stickman.riv
     artboard 'nuvo stickman elite' · VM 'NuvoPoseModel' · SM 'Nuvo pose'
   side rig:  assets/animations/preverify/nuvo_stickman_side.riv
     artboard 'Nuvo stickman side' · VM 'NuvoAngledataset' · SM 'Nuvo State machine'
                       ▼
   RivePoseController / SideRigPoseController  (ViewModel number writes)
```

**Consumer:** `SubmitProofScreen._PreVerifySetupCard`
(`lib/features/races/presentation/submit_proof_screen.dart` ~line 597).
Route: `/race/:id/proof`. Fallback when no preview exists:
`_StaticPreVerifyCue` (a static "Camera opens after Begin" card).

## Fixing a preset

Every preset is one entry in a switch inside
`movement_preview/rive_movement_sequences.dart` (front rig) or
`movement_preview/side_rig_movement_sequences.dart` (side rig) — a list of
`RivePoseFrame`/`SideRigPose` keyframes plus a `Duration`. To fix a preview
you edit **keyframe numbers and durations only**. Full workflow:
[FIXING_A_PREVIEW.md](FIXING_A_PREVIEW.md).

## Presets

24 presets have sequences (6 front-rig + treadmill side + 17 side-rig
shared). Full per-preset table: [PRESET_PREVIEWS.md](PRESET_PREVIEWS.md).

## Do NOT touch

- `lib/features/races/ai/**` — verifiers, validators, pose detector
- `server/worker/**` — except the documented `previewSequence` metadata field
- `lib/features/races/data/motion_package_*.dart` — Agent 4's installer
- the `.riv` assets — unless you are re-exporting the rig (calibration
  contract changes; see [RIVE_RIG.md](RIVE_RIG.md))
- `lib/features/races/presentation/custom_pose/learned_movement_preview.dart`
  — Teach Nuvo's separate learned-motion preview pipeline

## Calibration tool

Debug-only screen at route `/dev/rive-calibration` (kDebugMode builds):
scrubs every ViewModel property on the front rig live. Use it to find the
angle value you need before writing it into a keyframe.
