# AI Motion Activity System Plan

## Implemented
- Added a reusable movement catalog and typed parser.
- Supported AI activities:
  - `jumping_jacks`
  - `squats`
  - `high_knees`
  - `arm_raises`
  - `plank_hold`
- Unsupported activities, including push-ups, stay manual.
- Create Race now uses one natural typed race idea field.
- Quick starts use the same parser as typed input.
- AI Motion Proof screen uses a validator registry.

## Validators
- Jumping Jacks: existing open/closed logic preserved in registry form.
- Squats: standing to squat to standing.
- High Knees: alternating raised knees with lowering guard.
- Arm Raises: arms down to above shoulders to down.
- Plank Hold: counts valid posture time only.

## Verification
- Flutter analyze passed with only existing auth style infos.
- Physical movement validation was not run in this Codex session.
