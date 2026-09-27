# Claude handoff prompt — paste this into Claude

> Copy everything below the line into a fresh Claude session opened at the
> repo root. Then iterate with short messages like "Fix jumping jacks."

---

You are fixing preset movement previews in the Nuvo Flutter app. Your
ownership is **PRESET MOVEMENT PREVIEWS ONLY** — the small looping character
animations on the Submit Proof screen.

## First: read these docs (they are the spec — follow them exactly)

```
docs/motion_preview/README.md
docs/motion_preview/PRESET_PREVIEWS.md
docs/motion_preview/RIVE_RIG.md
docs/motion_preview/CLOUDFLARE_PREVIEW_PATH.md
docs/motion_preview/FIXING_A_PREVIEW.md
docs/motion_preview/TESTING.md
```

## Then: read these code entrypoints

```
lib/features/races/presentation/widgets/rive_movement_preview.dart
lib/features/races/presentation/movement_preview/rive_movement_sequences.dart
lib/features/races/presentation/movement_preview/side_rig_movement_sequences.dart
lib/features/races/presentation/movement_preview/side_rig_treadmill_preview.dart
lib/features/races/presentation/movement_preview/remote_movement_preview.dart
lib/features/races/presentation/movement_preview/rive_pose_controller.dart
lib/features/races/presentation/movement_preview/nuvo_semantic_pose.dart
lib/features/races/presentation/movement_preview/nuvo_rig_resolver.dart
lib/features/races/domain/motion_activity.dart
lib/features/races/data/motion_catalog.dart
lib/features/races/presentation/submit_proof_screen.dart   (host card only)
```

## Your workflow — one preset at a time

1. Pick the preset the user named.
2. Find its sequence per the docs (front rig vs side rig).
3. Inspect the current keyframes/duration.
4. Edit **existing keyframe data only** — pose angles, limb poses, timing.
5. Run the preview (commands in `TESTING.md`).
6. Ask for a screenshot, or evaluate one the user sends.
7. Iterate until the checklist passes. Report, then wait for the next preset.

## What you must NOT touch

- `lib/features/races/ai/**` — verifiers, validators, pose detector
- Camera / AI Motion Proof screens or proof submission logic
- Race semantics, scoring, leaderboards
- `lib/features/races/data/motion_package_*.dart` — Agent 4's installer/cache
- `server/worker/**` — routes, release semantics, R2 (the *value* of
  `previewSequence` in catalog metadata is the only Worker-adjacent thing a
  preview task can ever change, and only if the user asks for a remote fix)
- The `.riv` assets in `assets/animations/preverify/`
- `custom_pose/learned_movement_preview.dart` — separate Teach Nuvo pipeline
- `pubspec.yaml`, auth, iOS native files

Do NOT invent a new renderer, a new rig, a new package format, or a second
preview architecture. The system already exists — you tune its data.

## Reporting after each preset

```
Preset:   <activityId>
Rig:      front | side
Changed:  <file> — what values and why
Verified: analyze + which tests passed
Visual:   what the loop now looks like / what to check in the screenshot
```

## Example interactions

**USER:** "Fix jumping jacks."
**YOU:** Open `jumping_jack_preview_sequence.dart` +
`jumping_jack_human_motion_profile.dart` (jumping jacks uses a real-session
timing profile, not inline keyframes). Inspect current frames, run the
preview, adjust existing values, report what changed, ask for a screenshot.

**USER:** "The arms are good but legs aren't wide enough."
**YOU:** Widen only the leg/hip pose values in the existing keyframes.
Do not redesign anything.

**USER:** "Pushup preview is blank."
**YOU:** Trace the existing pipeline: is `pushUps` in
`sideRigMovementPreviewActivities`? Did `SideRigPoseController.missingProperties`
populate (renamed `.riv` property)? Is an invalid remote `previewSequence`
swallowing it? Fix the existing pipeline — never build a new renderer.

Start by confirming you've read the docs, then wait for the preset name.
