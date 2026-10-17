# Motion specs (over-the-air verifier releases)

Each `*.json` here is an over-the-air release for a motion that is also compiled
into the app: `rep_tree_v1` (squats family, jumping jacks, lunges, arm raises) or
`native_tuned_v1` (push_ups, high_knees, plank_hold, mountain_climbers,
lateral_steps, calf_raises). The app counts reps from the spec when the Worker's stable
channel points at it, and falls back to the compiled validator otherwise.
`test/rep_tree_parity_test.dart` proves each spec counts exactly like its
compiled twin, frame by frame — change a threshold here on purpose and the
parity test will tell you it no longer matches the compiled behavior.

## Publish (no app update needed)

```bash
export NUVO_INTERNAL_KEY=...            # the INTERNAL_API_KEY secret
cd server/worker
# 1. edit the spec: motion_specs/squats.json (bump releaseId, e.g. squats-tree-2026.10.1)
node scripts/nuvo-motion.mjs releases squats                      # find the current stable release id (the parent)
node scripts/nuvo-motion.mjs draft motion_specs/squats.json \
  --release-id squats-tree-2026.10.1 --parent <current-stable-id> --semver 2026.10.1
node scripts/nuvo-motion.mjs promote --release-id squats-tree-2026.10.1 --channel internal
node scripts/nuvo-motion.mjs promote --release-id squats-tree-2026.10.1 --channel beta --rollout 10
node scripts/nuvo-motion.mjs promote --release-id squats-tree-2026.10.1 --channel stable --rollout 100
# roll back instantly if it misbehaves:
node scripts/nuvo-motion.mjs rollback --activity-id squats --channel stable --release-id <previous-id>
# hide a motion that does not work yet:
node scripts/nuvo-motion.mjs activity-visibility squats --set hidden
```

Races pin the release that was stable when they were created, so a new release
applies to new races; in-flight races finish on the release they started with.

## `rep_tree_v1` grammar

```json
"repTree": { "start": <cond>, "active": <cond> }
<cond> := {"signal": S, "gt": n} | {"signal": S, "lt": n}
        | {"flag": F} | {"all": [<cond>...]} | {"any": [<cond>...]}
```

A rep is START → ACTIVE → START, each held `stableFrames` frames (the same
counter the compiled validators use). Every landmark a signal reads must be in
`requiredLandmarks`.

Signals: `hipToKneeRatio` (lower = deeper squat), `ankleWidthToBodyWidth`,
`kneeSeparationToHipWidth`, `leftKneeAngle`, `rightKneeAngle`,
`leftElbowAngle`, `rightElbowAngle`, `wristsAboveShoulderMargin`,
`wristsBelowShoulderMargin`, `wristsBelowHipMargin`, plus torso-relative
`wristsAboveShoulderTorso`, `wristsBelowShoulderTorso`, `leftWristBelowHipTorso`
(used by `arm_raises`, which is checked on raise/lower cycles in
`test/rep_tree_arm_raises_test.dart` rather than random poses).
Flags: `wristsAboveShoulders`, `wristsNearBody`.

New signals need an app update (they are code). The list lives in
`lib/features/races/ai/rep_tree.dart` and `src/domain/motionSpec.ts`, kept in
sync by `test/fixtures/rep_tree_signals.json`.

## `sequence_match_v1` additions (capability `sequence_features_v2`)

* Virtual landmarks `midShoulder`, `midElbow`, `midWrist`, `midHip`,
  `midKnee`, `midAnkle` may be used in any predicate point field.
* Predicate `axis_ratio`: `(a.axis − b.axis) / |refA − refB|`, optionally with
  `refAxis` to measure the reference on one axis only (e.g. torso height).
  Scale-invariant, so one threshold works at any camera distance.

Releases that use these should list `sequence_features_v2` (or `rep_tree_v1`)
in `requiredCapabilities` so builds without them never receive the release.

## `native_tuned_v1` (stateful motions)

For motions with their own running state, the release runs the app's compiled
validator and only overrides named thresholds:

```json
"engineType": "native_tuned_v1",
"params": { "raiseLift": -0.4, "lowerLift": -0.8 }
```

Each file lists every tunable with its compiled default, so editing one number
and publishing is the whole change. Allowed keys and bounds per motion live in
`kNativeTunables` (`motion_validators.dart`) and `NATIVE_TUNABLES`
(`motionSpec.ts`), kept in sync by `test/fixtures/native_tunables.json`; an
unknown key or out-of-range value is rejected at draft time. Adding a new
tunable is an app update; changing its value is not. Capability:
`native_tuned_v1`. Verified by `test/native_tuned_test.dart` (defaults count
identically to the untuned validator).
