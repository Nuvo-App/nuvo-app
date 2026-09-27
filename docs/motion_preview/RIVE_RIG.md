# Rive rig contract

Two bundled rigs drive all preset previews. **Do not edit the `.riv` files.**
Angles are degrees; scales are multipliers on authored limb length; root is
artboard-space px offset.

## Front rig

- Asset: `assets/animations/preverify/nuvo_stickman.riv`
- Artboard: `nuvo stickman elite`
- State machine: `nuvo pose`
- ViewModel: `NuvoPoseModel`
- Controller: `RivePoseController`
  (`movement_preview/rive_pose_controller.dart`)
- Pose type: `RivePoseFrame` (`movement_preview/rive_pose_frame.dart`)

### ViewModel number properties (front)

| Property | Meaning |
|---|---|
| `torsoAngle` | torso lean |
| `leftShoulderAngle` / `rightShoulderAngle` | upper-arm angle at shoulder |
| `leftElbowAngle` / `rightElbowAngle` | elbow bend |
| `leftHipAngle` / `rightHipAngle` | thigh angle at hip |
| `leftKneeAngle` / `rightKneeAngle` | knee bend |
| `leftUpperArmScale` … `rightLowerLegScale` (8 props) | limb length multipliers — leave at calibrated neutral for previews |
| `torsoScaleY` | torso squash/stretch |
| `rootX` / `rootY` | whole-body translate (bounce) |

### Apply paths (choose deliberately)

- `applyMotion(frame)` — writes the **8 limb angles only** (shoulder, elbow,
  hip, knee both sides). Torso/scales stay at calibrated values. Used by all
  front-rig non-jack sequences — if the torso should move, this is why it
  doesn't.
- `applyJumpingJackMotion(frame)` — writes only the 6 channels the jack rig
  uses; elbows/knees/scales fixed. Used by `_JumpingJackSequenceAdapter`.
- Full apply — writes everything including scales; used for calibration.

## Side rig

- Asset: `assets/animations/preverify/nuvo_stickman_side.riv`
- Artboard: `Nuvo stickman side` *(capital N — the lookup is case-sensitive)*
- State machine: `Nuvo State machine`
- ViewModel: `NuvoAngledataset`
- Controller: `SideRigPoseController`
  (`movement_preview/side_rig_treadmill_preview.dart:221`)
- Pose type: `SideRigPose` (`side_rig_treadmill_preview.dart:11`)

### ViewModel number properties (side)

Same layout as front but limbs are `front*`/`back*` (near/far leg and arm):

`torsoAngle`, `frontShoulderAngle`, `frontElbowAngle`,
`backShoulderAngle`, `backElbowAngle`, `frontHipAngle`, `frontKneeAngle`,
`backHipAngle`, `backKneeAngle`, plus 8 `*ArmScale`/`*LegScale` props and
`torsoScaleY`.

Root bob: `rootX`/`rootY` offsets against base `(244.5, 277.0)` — sequences
get it free via `poseWithBounce(pose, x:, y:)` in
`side_rig_movement_sequences.dart`.

## Semantic layer (front rig only)

`NuvoHumanPose`/`NuvoArmPose`/`NuvoLegPose` in `nuvo_semantic_pose.dart` →
`nuvo_rig_resolver.dart` converts semantic limbs to a `RivePoseFrame` →
`RivePoseController` writes ViewModel numbers. When a teammate says "legs
wider", that is a `NuvoLegPose`/resolver value, then the keyframe numbers in
the sequence table.

## Calibration

- `nuvo_rive_rig_calibration.dart` — neutral pose offsets measured against
  the artboard.
- `/dev/rive-calibration` (debug route,
  `rive_calibration_screen.dart`) — live property scrubber for the front
  rig. Find the angle you want visually, then hard-code it into the
  sequence keyframe.
- Both controllers populate `missingProperties` — if a preview is blank,
  check this first (property renamed in the `.riv`).

## Known quirks

- Rig selection in `RiveMovementPreview`: side rig wins when the activity is
  in `sideRigMovementPreviewActivities`, is `treadmillRunning`, or the remote
  spec says `rig: "side"` — even if a front sequence also exists.
- If the `.riv` re-exports with renamed properties, the preview degrades to
  the static cue, not a crash — blank preview ⇒ check `missingProperties`.
- Legacy CustomPainter demos (`nuvo_character_painter.dart`,
  `preset_movement_demos.dart`, `movement_demo.dart`,
  `arm_raises_animation.dart`) are orphaned — no live consumer imports them.
