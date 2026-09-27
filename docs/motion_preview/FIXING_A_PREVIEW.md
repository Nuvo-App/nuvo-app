# Fixing a preset preview

One preset = one `switch` case returning keyframes + a `Duration`. You edit
numbers, never plumbing.

## Workflow (every preset)

1. **Find the activity ID** — `MotionActivityType` in
   `lib/features/races/domain/motion_activity.dart`.
2. **Find its sequence:**
   - front rig → `movement_preview/rive_movement_sequences.dart`
   - side rig → `movement_preview/side_rig_movement_sequences.dart`
     (treadmill: `side_rig_treadmill_preview.dart`)
   Rig choice is in `widgets/rive_movement_preview.dart` —
   `sideRigMovementPreviewActivities` + `treadmillRunning` go side.
3. **See it live:**
   ```bash
   flutter run -d <device>
   ```
   open a race with that activity → Submit Proof (`/race/:id/proof`) →
   preview card under the setup section.
   Or `/dev/rive-calibration` (debug) to scrub the front rig by hand.
4. **Edit keyframes:** pose fields (angles, `front*`/`back*` on side rig,
   `NuvoLegPose`/`NuvoArmPose` on front) and the sequence `Duration`. Keep
   the first and last frames identical — that is the loop seam.
5. **Hot restart** (pose lists are const-ish, hot reload usually suffices;
   restart if the sequence object is cached).
6. **Check the loop seam** — the #1 defect is a jump or dead pause between
   loops.
7. **Verify:**
   ```bash
   flutter analyze --no-fatal-infos
   flutter test test/rive_jumping_jack_preview_test.dart \
                   test/rive_side_treadmill_preview_test.dart \
                   test/side_rig_movement_sequences_test.dart \
                   test/nuvo_semantic_motion_rig_test.dart \
                   test/rive_pose_controller_test.dart
   ```
8. Report what changed (see "Reporting" below), get a screenshot, iterate.

## Cookbook

- **"Legs aren't wide enough"** → widen the hip/spread values in the pose
  keyframes (`NuvoLegPose` spread fields front, `frontHipAngle`/`backHipAngle`
  side). Do not touch the resolver.
- **"Too fast / too slow"** → the sequence `Duration`, or re-balance keyframe
  `t` values if only part of the move is mistimed.
- **"Arms wrong"** → `NuvoArmPose` (front) or `front/backShoulderAngle` +
  `front/backElbowAngle` (side).
- **"Bounce feels off"** → `poseWithBounce(pose, x:, y:)` offsets (side) or
  `rootX/rootY` on the frame (front).
- **"Blank preview"** → the fallback `_StaticPreVerifyCue` is showing.
  Check: (a) activity in a sequence map? (b) `controller.missingProperties`
  — a renamed ViewModel property in the `.riv`? (c) remote spec invalid →
  silently fell back? Trace in `RiveMovementPreview.supports(...)`.
- **"Wrong rig"** → `sideRigMovementPreviewActivities` membership, or remote
  `rig` field. `treadmillRunning` is always side.
- **"Torso never moves (front rig)"** → `applyMotion` writes only the 8 limb
  angles; torso stays calibrated. That is intentional for front previews —
  don't "fix" it globally, adjust the pose if it looks wrong.

## Rules

- Edit existing keyframe data only. No new renderers, no new rig files, no
  new architecture.
- First and last keyframe must match (loop seam).
- Keep loops 0.9–2.6s; previews sit in a 300px card, subtle reads better
  than dramatic.
- Never touch verifier code, scoring, proof logic, or Worker routes.
- If a remote `previewSequence` exists for the activity, fix the bundled
  sequence anyway — remote is an override, not a dependency.
