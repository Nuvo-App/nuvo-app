# Preset preview inventory

`MotionActivityType` lives in
`lib/features/races/domain/motion_activity.dart`. Every preset maps to one
compiled sequence — none have remote `previewSequence` data in the bundled
catalog today (remote is override-capable, see CLOUDFLARE_PREVIEW_PATH.md).

How to test any row: run the app, open a race with that activity →
`/race/:id/proof` (Submit Proof) → the 300px preview card sits under the
setup section. Or use a quick widget harness that pumps
`RiveMovementPreview(movement: <type>, fallback: SizedBox())`.

## Front rig — `nuvo_stickman.riv` (`nuvo stickman elite`)

Sequences in `movement_preview/rive_movement_sequences.dart`.

| activityId | Enum | Sequence class | Duration | Notes |
|---|---|---|---|---|
| jumping_jacks | jumpingJacks | `_JumpingJackSequenceAdapter` → `JumpingJackPreviewSequence` | 1000ms | The gold standard — endpoints driven by a real-session timing profile (`jumping_jack_human_motion_profile.dart`, Cloudflare R2 session medians). Uses `applyJumpingJackMotion` (6 channels only). |
| lunges | lunges | `_LungesSequence` | 2200ms | standing→R lunge→standing→L lunge→standing |
| arm_raises | armRaises | `_ArmRaisesSequence` | 1800ms | down→raised→down |
| running_in_place | runningInPlace | `_GaitSequence` | 900ms | shared gait profile |
| marching_in_place | marchingInPlace | `_GaitSequence` | 1250ms | higher knee lift |
| treadmill_running | treadmillRunning | `TreadmillRunningSideSequence` (side rig) | 900ms | dedicated side sequence, see below |

## Side rig — `nuvo_stickman_side.riv` (`Nuvo stickman side`)

Sequences in `movement_preview/side_rig_movement_sequences.dart`; treadmill
in `side_rig_treadmill_preview.dart`. All keyframed `_standing`/pose lerps
with `poseWithBounce` root bob.

| activityId | Enum | Keyframes | Duration |
|---|---|---|---|
| treadmill_running | treadmillRunning | dedicated `TreadmillRunningSideSequence` | 900ms |
| push_ups | pushUps | standing → pushUpDown → standing | 1800ms |
| squats | squats | standing → squat → standing | 1800ms |
| high_knees | highKnees | alternating gait (hip 132°/knee 72°) | 900ms |
| plank_hold | plankHold | standing → plank → plank → standing | 1600ms |
| sumo_squats | sumoSquats | standing → sumoSquat → standing | 1900ms |
| side_lunges | sideLunges | standing → sideLunge → stand → stand | 2200ms |
| deep_squats | deepSquats | standing → deepSquat → standing | 2200ms |
| squat_jacks | squatJacks | standing → squatJack → standing | 1700ms |
| jump_squats | jumpSquats | standing → squat → jump → standing | 1500ms |
| lunge_jumps | lungeJumps | stand→splitL→jump→splitR→stand | 1700ms |
| walking_in_place | walkingInPlace | alternating gait (112°/42°) | 1250ms |
| butt_kicks | buttKicks | alternating heel-to-glute poses | 950ms |
| mountain_climbers | mountainClimbers | plank→climberL→plank→climberR→plank | 1200ms |
| burpees | burpees | stand→squat→plank→squat→stand | 2600ms |
| step_ups | stepUps | alternating gait (118°/48°) | 1400ms |
| calf_raises | calfRaises | standing → calfRaise → standing | 1200ms |
| lateral_steps | lateralSteps | stand→step→stand→stepBack | 1300ms |
| basketball_shot | basketballShot | stand→crouch→release→stand | 1800ms |

## Not covered

- `MotionActivityType.remote` — registry activities with no compiled enum.
  They animate **only** when the catalog row carries a valid
  `previewSequence`; otherwise `_StaticPreVerifyCue`.
- Custom (Teach Nuvo) movements — separate pipeline:
  `presentation/custom_pose/learned_movement_preview.dart`.

## Known issues / starting points

- Side-rig arm poses are approximate for most presets (front/back arm
  angles share few calibration references — verify against the side rig
  with `/dev/rive-calibration` adapted to `nuvo_stickman_side.riv`, or
  visually).
- `plankHold` spends half its loop standing (intro/exit frames); if it
  reads wrong, shorten the standing keyframes' share, not the pose.
- `jumpingJacks` is the reference implementation — when unsure how a fix
  should feel, compare against it.
