# Nuvo Motion V2 — Session Export / Agent Handoff

Paste this into a fresh agent session to resume the work. Everything below is
verified against real device data and deployed infrastructure as of
2026-10-15, branch `motion-ota-tuning`, HEAD `a87fd9b`.

## Mission

Take ownership of the Nuvo production Flutter app. Make Teach Nuvo (custom
motion recognition) excellent, observable, and fixable after release via
Cloudflare/OTA wherever technically possible. The app has been submitted to
the App Store; post-release AI work must happen without shipping new
executable code (iOS cannot download code OTA — specs/thresholds/presets are
data and CAN ship OTA).

## Environment

- Repo: `/home/server1/projects/nuvo-app`, branch `motion-ota-tuning`,
  remote `github-nuvo-app:Nuvo-App/nuvo-app.git`
- Worker: `https://nuvo-api.getnuvoapp.workers.dev` (live)
- Deploy: `/home/server1/.local/bin/wrangler-nuvo deploy`
  (sources `~/.secrets/cloudflare-nuvo.env`; account `d618e374fb4ffb44dbc770dd07431f79`.
  `wrangler.toml` only defines `dev` — plain `deploy` hits production.)
- D1 database: `nuvo_db`
- Internal API key: `~/.config/nuvo/internal-api-key` (mode 600) — required
  to decrypt session artifacts via `server/worker/scripts/nuvo-motion.mjs`
  and `nuvo-ops.sh`. Never print its value.
- Pulled artifacts live in `~/.nuvo-sessions/` (NOT in the repo — do not
  commit them; pose data).

## Commands

- `flutter test test/...` — always use the Flutter runner; plain `dart` dies
  compiling ONNX FFI (`InvalidType` error).
- ONNX-dependent tests need
  `LD_LIBRARY_PATH=/home/server1/.pub-cache/hosted/pub.dev/onnxruntime-1.4.1/linux`
- `flutter analyze --no-fatal-infos` — baseline has 4 infos in
  `auth_controller.dart` + 2 initializing-formal infos in the V2 adapter.
- Worker: `cd server/worker && npm run typecheck && npm test` (374 tests).
- D1 query: `cd server/worker && wrangler-nuvo d1 execute nuvo_db --remote
  --json --command "SQL"`
- Pull teach session: `NUVO_INTERNAL_KEY="$(cat ~/.config/nuvo/internal-api-key)"
  node scripts/nuvo-motion.mjs teach-get <SESSION_ID>` → saves `.json.gz`
- Pull proof session: same with `session-get <id>` → saves `.json`
- Replay proof frames through a spec: `tool/motion-replay.sh <artifact>` or
  write a flutter test probe (see patterns used below).

## Architecture

**Two matchers coexist:**
- **V1 `custom_pose_sequence`** — hand-built pose-template matcher. Proven on
  real data it cannot represent pull-ups (failed pairwise consistency AND
  its own self-validation across 3 sessions). Kept as fallback for old races.
- **V2 `motion_v2`** — MotionBERT ONNX encoder → each demo becomes a
  reference embedding (proto + trajectory); the spec is ~1MB JSON (schema 4,
  3 refs, proto/traj spreads, demo_lengths, demo_active_vel, region_activity,
  rest_emb, metadata). `StreamingMotionV2` runs the sliding-window matcher.

**Teach flow:** record 3 demos → V1 build + V2 learn in parallel → V2
self-validation is the real arbiter (V1 cannot gate the V2 path) → live test
(drives `MotionV2NativeRuntime` directly, batches of 4) → "Use this movement"
→ `LearnedCustomMovement` carries BOTH specs → composer → `createCustomRace`
sends `verifierType: 'motion_v2'` + the full spec in `verifier_spec_json`
(1.5MB cap server-side).

**Proof flow:** `MotionV2VerifierRuntime` adapts the async V2 engine to the
synchronous per-frame `VerifierRuntime` contract: buffers frames during
engine load, pumps batches (coalesces to ≤12 frames when behind), emits
`CustomPoseRuntimeUpdate`/`CustomPoseRuntimeResult` so the proof screen
needs no custom plumbing. The proof screen distinguishes `_isCustom`
(session semantics) from `_usesCustomRuntimeOutput` (output shape) — remote
V2 releases use the latter only. `drain()` is awaited before `finish()` so
in-flight evals aren't dropped.

**Contract (worker `races.ts`):** `verifierType` match, `verifierVersion`
match, `metric: 'reps'`, `measurementType: 'count'`, `detectedValue ===
value`, `activityType` = custom name.

**OTA release machinery:** draft release → promote → channel → race
assignment → session mint → app fetches spec at proof time. Worker
`motionSpec.ts` accepts `engineType: 'motion_v2'` (structural validation:
verifier marker, 1–4 refs with proto+traj arrays, all-finite numbers; 1.5MB
cap vs 64KB for declarative). App advertises `'motion_v2'` in
`MotionCapabilities.current()`. `camera_verification_resolver` parses the
nested `motionV2Spec` + `activity` block into `CameraVerificationEligibility`
with `customMotionV2Spec` → resolves to `MotionV2VerifierRuntime`. Package
asset type `motion_v2_spec_v1` also exists (1.5MB cap).

**Observability:** teach sessions → `motion_teach_sessions` (outcome,
failure_stage, v2_learned, self_validation_passed, live_test_matched,
used_for_race) + encrypted artifacts in R2. Proof sessions →
`motion_sessions` (kind, outcome, detected_value, confidence, frame_count).
Failed teaches upload at the failed screen AND on dispose; queue retries.

## Bugs found on real data and fixed

| Commit | Bug | Evidence |
|---|---|---|
| `1a13345` | `measurementType: 'repetitions'` → every submit 400'd | Worker requires `'count'` |
| `1a13345` | Rep counted on ANY same-family window — walking to the bar counted | ms_c39db497: rep at t=891ms, trajSim 0.997 on approach |
| `156776d` | Attempt durations used `DateTime.now()` — burst feeding passed duration gates in 730ms of motion | probe replay |
| `156776d` | Motion floor `0.08` rejected real captures | wave = 0.036–0.05 |
| `8a86e03` | Floor recalibrated to `0.015` — dead-capture only; metrics overlap (wave ~0.05 vs hang ~0.036) so it cannot gate "wrong content" | MV2-20261015-73C7C6 |
| `a146828` | Count froze at 1: re-arm needed score drop, but hanging-between-reps is inside the family → match never broke for 17s | ms_c39db497; fix: re-arm when canonical progress ≤ `repRearmProgress` (0.30) |
| `1612b85` | V2 learned trimmed demos — `_autoTrimSetup` (motion-start −300ms) cut slow lead-ins; V2 gets untrimmed `_v2Demos` (its own `segmentAction` finds the active region) | 84A985: 139→41 frames |
| `8c4748d` | Adapter fed exactly 4 frames per ONNX call — engine lagged the 15fps stream; counting eval never landed in a 9.4s session | ms_3cdb701f: matched, count 0; offline replay counts at eval ~11 |
| `8c4748d` | `finish()` dropped in-flight evals | added `drain()` |
| `16198cd` | No remote path for learned specs → `motion_v2` engine + resolver + capability + proof-screen output/session separation | tests |

## Spec tuning block (OTA-tunable, rides in `verifier_spec_json`)

`streaming_motion_v2.dart` reads `spec.tuning`: `matchScore` (0.5),
`neutralDrop` (0.55), `repMinProgress` (0.55), `repRearmProgress` (0.30).
Patch a live race's strictness with a D1 `UPDATE` — no app update.

## Real session data (ground truth)

- `MV2-20261015-92AFAC` — wave: learned, self-validated, live test matched,
  race `1e49bec7` created as `motion_v2`. First green end-to-end.
- `ms_3cdb701fe9be4fff96ce671ddb58c81e` — wave proof: matched 9.4s, count 0
  → adapter lag (fixed).
- `MV2-20261014-84A985` — pull-ups: learned stillness (demos = walk-up +
  hang; wrist pinned to bar, nose conf 0, region_activity 0.036). Race
  `131d7478` `motion_v2`.
- `ms_c39db49784a8427a98a73fc8709ca50f` — pull-up proof: approach counted,
  actual pulls rejected (votes 0, conf 0.29).
- `MV2-20261015-73C7C6` — wave: killed by the miscalibrated floor (before
  `8a86e03`).

## Current state

- Worker deployed: latest version accepts `motion_v2` races + learned-spec
  releases.
- App HEAD `a87fd9b` (pushed): floor fix + adapter coalescing/drain +
  re-arm + untrimmed demos + remote V2 releases.
- **Retest needed:** wave race proof on a build ≥ `a87fd9b`. First rep needs
  ~2.4s continuous motion (duration gate = half shortest demo).
- Pull-ups remain unproven — capture physics (wrist pinned, head out of
  frame). Demos must contain visible torso/shoulder rise.

## Known gaps / pending

- `motion_sessions.engine_type` stored null — provenance field.
- The learn floor only catches dead captures; wrong-content demos (user
  demos stillness, labels it pull-ups) are only caught by the live test —
  consider making live test mandatory before "Use this movement".
- Learn-time `_minRegionActivity` is compile-time (no spec exists yet);
  could ride in a remote model-release config later.
- Old clients can't verify `motion_v2` races (fail closed — by design).
- iOS cannot receive new algorithm code OTA — parameters/specs only.

## Repo rules (AGENTS.md — enforced)

- NO AI attribution in commits — no Co-Authored-By, no tool signatures.
- Declare file list + behavior + risk before broad/medium+ edits.
- No-touch: auth, `ai_motion_proof_screen.dart`, `motion_validators.dart`,
  camera/pose bridge, iOS native files, `pubspec.*`, backend contract
  changes need explicit approval.
- Worker changes: `npm run typecheck` must pass.
- Flutter changes: `flutter analyze --no-fatal-infos` clean.

## Debug probes (deleted from repo — recreate when needed)

Pattern: flutter test file that reads `~/.nuvo-sessions/<artifact>`,
rebuilds `NuvoPoseFrame`s (proof artifacts use `landmarks` with x/y/z/
confidence; teach artifacts use `smoothed`/`raw` arrays `[x,y,z,c]` with
epoch-ms `t`), then either `MotionV2NativeRuntime().learn(demos:…)` to
test learning or `load(spec)` + `update(batches)` to replay proof frames.
Log per-eval: state, matched, count, conf, prog, votes, traj, proto, sep.
