# Tuning motions over the air

Goal: improve how any motion counts without an App Store release.

## The loop (about 10 minutes per motion)

1. **Record.** Do the motion 10 times in the app. Every verification session
   uploads its pose log automatically.
2. **Pull it.** From `server/worker` with `NUVO_INTERNAL_KEY` set:
   `node scripts/nuvo-motion.mjs session-latest <activityId> --out s.json`
   (or `sessions-failed` to find sessions that failed, then `session-get <id>`).
3. **Replay + look at it.** From the repo root:
   `tool/motion-replay.sh s.json --out replay.html` and open the page. It runs
   the real validator code on the recorded frames: skeleton scrubber, the
   signals the verifier reads, green lines where a rep was counted, and the
   replay count next to what the app counted.
   Under the viewer, mark the recording **Correct / Wrong / Unusable**, enter
   the reps you actually did, and press Save: it downloads a `label_<session>.json`
   (`useForTraining` is true only for Correct). Use those files to decide which
   recordings the AI model should train on, and as ground truth for tuning.
4. **Try a threshold.** `tool/motion-replay.sh s.json --set raiseLift=-0.5`
   (for `native_tuned_v1` motions). For `rep_tree_v1` motions, copy the spec,
   edit it and pass `--spec copy.json`.
5. **Publish.** Edit `server/worker/motion_specs/<id>.json`, then draft →
   promote internal → beta → stable (see `motion_specs/README.md`). Roll back
   with one command.

## What can change over the air

Every compiled motion except two (listed in `test/motion_ota_coverage_test.dart`,
with reasons) has a spec file. Squats family, jumping jacks, lunges and arm
raises use `rep_tree_v1` (conditions and thresholds). Everything else uses
`native_tuned_v1` (named thresholds on the existing logic).

Over the air = thresholds, conditions, and which signals combine.
Needs an app update = a brand new signal, new kind of logic, or a motion whose
logic is structurally wrong. `test/motion_ota_coverage_test.dart` fails the
build if a motion is added without an over-the-air path.

## Before every app submission

Replays only prove the verifier matches what was recorded. Whether a motion
works on a real camera is only known from real recordings, so before you
submit: run each motion in the build ~5 times on a phone, pull the sessions,
replay them, and hide (`activity-visibility <id> --set hidden`) anything that
does not count reliably. Races pin the release that was stable when created;
new releases apply to new races.

## Managing motions from Cloudflare

Everything runs through `server/worker/scripts/nuvo-motion.mjs` (needs
`NUVO_INTERNAL_KEY`). No app update for any of it, as long as the motion uses an
engine the shipped app has (`state_machine_v1`, `alternating_rep_v1`,
`hold_v1`, `sequence_match_v1`, `rep_tree_v1`).

**Create a new motion**
1. `node scripts/nuvo-motion.mjs activity-create new_motion.json` — creates it
   hidden. File shape: `{ "id": "side_reaches", "displayName": "Side Reaches",
   "category": "upper_body", "proofLabel": "side reaches",
   "measurementType": "repetitions" | "duration", "suggestedTargets": [10, 20],
   "supportedFormats": ["first_to_goal"], "iconKey": "fitness_center",
   "instructions": ["..."], "aliases": ["..."], "cameraOrientation": "front" }`.
   `measurementType` is fixed after this (races are stored against it).
2. `draft spec.json --release-id side_reaches-2026.10.0 --semver 2026.10.0`
   (no `--parent` for the first release; the spec needs an `activity` block).
3. `promote ... --channel internal`, then beta, then stable.
4. `activity-visibility side_reaches --set supported` — now it is in the app.

**Edit a motion's details:** `activity-update <id> changes.json` with any of
displayName, category, proofLabel, suggestedTargets, supportedFormats, iconKey,
sortPriority, featured, instructions, aliases, cameraOrientation. Works for
compiled motions too (name, targets, instructions, order); a compiled motion's
type, reps-vs-seconds, and preview stay fixed in the app.

**Update logic / roll back / retire:** `draft` + `promote` a new release,
`rollback`, or `activity-visibility <id> --set hidden`.

**Not possible without an app update:** a motion that needs a body measurement
or engine the app doesn't have, or changing a motion's measurement type.
