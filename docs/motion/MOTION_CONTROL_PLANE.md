# Motion Control Plane

The canonical operating document for tuning Nuvo's AI Motion verifiers from
Cloudflare **without shipping a new app build**, where the shipped runtime
supports it.

Verified live against `nuvo-api` (prod) and `nuvo-api-dev` (dev) on
2026-09-27. Related reading: `docs/motion_runtime/OPERATIONS.md` (command
reference), `docs/NUVO_MOTION_CONTROL_PLANE_PRD.md` (target architecture),
`docs/MOTION_CONTROL_PLANE_BASELINE_2026-09.md` (stage-0 inventory).

---

## 1. The loop

```
OBSERVE → TUNE → VALIDATE → PUBLISH → CLIENT SAFELY ADOPTS → MEASURE → ROLLBACK
```

Concrete path:

```
verifier_audit_log + motion_sessions        (observe)
  → spec.json authored / edited             (tune)
  → POST /internal/motion/releases/drafts   (validate — drafting IS the gate)
  → POST /internal/motion/evaluations       (evidence)
  → POST /internal/motion/releases/:id/promote --channel internal|beta|stable
  → app reads /races/activities + /motion/releases/:id  (safe adoption)
  → motion_sessions carry releaseId+checksum           (measure)
  → POST /internal/motion/channels/:a/:c/rollback
  → POST /internal/motion/releases/:id/disable         (kill switch)
```

All mutation endpoints live under `/internal/*` and require the
`X-Internal-Key` shared secret. Every mutation writes `verifier_audit_log`.

## 2. What is remotely tunable

Real knobs only — these exist today:

| Knob | How |
| --- | --- |
| Declarative verifier parameters (thresholds, phase rules, visibility, timing bounds) | New immutable release with an edited spec on an engine the app ships (`state_machine_v1`, `alternating_rep_v1`, `hold_v1`, `sequence_match_v1`, `object_composition_v1`) |
| Which release an activity serves, per channel | `promote` / `rollback` moves the `activity_channel_releases` pointer |
| Staged rollout | `rolloutPercent` 0–100, deterministic bucketing `sha256(userId:releaseId) % 100` |
| Per-movement enable/disable | `disable` (kill switch — fails closed for new resolution, never bricks pinned sessions) |
| Preview animations | `previewSequence` metadata (inline keyframes) or declared package assets |
| Display metadata | `instructions`, `cameraOrientation`, `aliases`, display name/category on the registry activity |
| New movements | A release on a shipped engine + a registry activity — no app update needed when `requiredCapabilities`/`minimumAppBuild` are satisfied |

**Not tunable without an App Store build:** the internals of `native_v1`
validators (compiled into the binary — push_ups, plank_hold, and the other
20 preset validators currently serving prod), new runtime engines, and
anything that would download executable code. `native_v1` releases are
metadata handles: remote control over them is limited to which release the
channel points to, metadata, previews, and enable/disable.

## 3. Config contract

The versioned unit is the **verifier release** (not a single global config
blob). Shape served by `GET /motion/releases/:releaseId`:

```json
{
  "id": "arm_raises-remote-2026.09.1",
  "activityId": "arm_raises",
  "engineType": "state_machine_v1",
  "specSchemaVersion": 1,
  "spec": { "...": "engine payload, allowlisted fields only" },
  "checksum": "…",
  "requiredCapabilities": ["pose_landmarks_v1", "state_machine_v1"],
  "minimumAppBuild": "1.0.0"
}
```

- Releases are **immutable** — new content = new releaseId = new checksum.
- Per-movement overrides are intrinsic: each activity carries its own
  releases and its own channel pointer. Tuning one movement never touches
  another.
- `spec.releaseId`/`spec.activityId`/`spec.engineType` must match the
  envelope — the client rejects identity mismatches.
- Every diagnostic can be traced: `releaseId` + `checksum` + `engineType` +
  `specSchemaVersion` are pinned on the session, and the catalog reports a
  `catalogVersion`.

## 4. Fetch, cache, fallback

Client path (`lib/features/races/data/`):

1. `GET /races/activities?channel=…` — ETag'd catalog; per-activity
   `currentReleaseId`/`currentReleaseChecksum`/`engineType` (masked to null
   when the pointed release isn't `stable` — fail closed). If the registry
   read fails, the Worker returns the compiled legacy catalog
   (`registryFallback: true`) instead of an error.
2. `GET /motion/releases/:id` — immutable spec download, ETag'd,
   checksum-addressed. Fetched once per new releaseId, not per session.
3. `VerifierReleaseRepository` validates (`VerifierRelease.fromJson` →
   `RemoteVerifierSpec.fromJson` strict parse: unknown fields, schema
   version, engine allowlist, bounded ints, required landmarks), then
   persists to `nuvo_verifier_releases.json` via atomic tmp+rename.
4. Fallback order: fresh fetch → **last-known-good cached release** →
   **bundled native validator** (every preset ships a compiled validator;
   `native_v1` releases need no download). Corrupt cache entries are dropped
   individually; a network failure returns the cached release. Motion never
   depends on Cloudflare being up at session time.

## 5. Atomic apply

- Race/session creation resolves an assignment and **pins**
  `release_id` + `release_checksum` on the session row.
- Attempts must echo the same releaseId+checksum or are rejected — a
  session can never adopt a new config mid-flight.
- Channel-pointer moves affect only NEW resolution. Nothing migrates a
  pinned session.

## 6. Publish safety

States on `verifier_releases.status`: `draft` → `validated` →
`internal`/`beta` → `stable` (plus `disabled`).

- Drafts are invisible to every channel.
- Stable promotion **requires a passing evaluation run**
  (`verifier_evaluation_runs`): `sampleCount >= 20`, `hardGatesPassed`,
  full baseline+candidate metric sets, regression guardrails
  (rep recall, false positives, readiness, frame latency, unsupported spec,
  proof mismatch). Verified live: `409` without one.
- A `stable` release cannot be demoted by `promote` (`409`) — pointer moves
  go through `rollback`/`disable`.
- Assets are immutable once a release reaches `stable`; uploads are
  checksum-enforced against the declared manifest.

## 7. Rollback / kill switch

```bash
# Restore prior good release on a channel (no eval gate — this IS the
# emergency path):
node scripts/nuvo-motion.mjs rollback \
  --activity-id <a> --channel stable --release-id <last-good>

# Kill a bad release everywhere it would newly resolve:
node scripts/nuvo-motion.mjs disable --release-id <bad>
```

`disable` truth: `status='disabled'` fails closed for new resolution; the
public catalog masks its fields; fetch-by-ID still serves it so pinned
sessions resolve. Verified live on dev 2026-09-27: pointer flip visible in
the public catalog on the next request, in both directions.

## 8. Environments

| | Prod | Dev |
| --- | --- | --- |
| Worker | `nuvo-api` | `nuvo-api-dev` |
| D1 | `nuvo_db` (`c46cb25d-…`) | `nuvo_db_dev` (`29193d3c-…`) |
| R2 | `nuvor2` | `nuvor2-dev` |
| Flutter | `https://nuvo-api.getnuvoapp.workers.dev` (compiled default) | `--dart-define=NUVO_API_BASE_URL=https://nuvo-api-dev…` |

Channels are per-database — a dev promotion can never touch prod.
CLI: `node scripts/nuvo-motion.mjs <cmd> --env dev` (omit `--env` for prod).
Channels: `internal` → `beta` → `stable`; internal builds read
`?channel=internal`, release builds read `stable`.

## 9. Diagnostics

- `motion_sessions` rows + encrypted R2 artifacts carry session/release
  identity: `releaseId`, `releaseChecksum`, `engineType`,
  `specSchemaVersion`, app version, outcome, quality. Consent-gated;
  pseudonymous `account_ref` — no raw user ID.
- Internal inspection: `GET /internal/motion-sessions/:id`,
  `GET /internal/motion-sessions/failed`,
  `GET /internal/activities/:a/motion-sessions/latest`,
  `GET /internal/motion/adaptation/signals` (failure-reason clustering →
  recommended tuning action).
- "Pushups stopped working" → pull the session's releaseId/checksum, fetch
  the exact spec, replay against the labeled attempt.

## 10. Observability

- `verifier_audit_log`: every draft/eval/promote/rollback/disable/preview
  with actor, prior release, details (`nuvo-motion.mjs audit`).
- `catalogVersion` timestamps catalog state.
- `signals` aggregates failure reasons per activity/release.
- `verifier_evaluation_runs` records evidence per release.

## 11. Launch baseline (frozen 2026-09-27)

Prod `stable` channel — verified via the live public catalog
(`catalogVersion 2026-09-27 15:02:55`, 26 activities):

- 23 presets → `*-legacy-2026.09.0` (`native_v1`, rollout 100)
- `basketball_shot` → `basketball_shot-composition-2026.09.1` (`object_composition_v1`)
- `remote_seq_squats` ("Squat Jumps") → `remote_seq_squats-2026.10.0` (`sequence_match_v1`)
- `remote_test_motion` ("Reach Taps") → `remote_test_motion-2026.10.0` (`alternating_rep_v1`)

Rollback floor: every preset's `native_v1` release is immutable and stays
in D1 — `rollback --release-id <activity>-legacy-2026.09.0` always restores
the shipped-baseline behavior. Remote-eligible releases already staged as
`stable` but not pointed: `arm_raises-remote-2026.09.1`,
`squats-remote-2026.09.1`, `jumping_jacks-remote-2026.09.1`,
`plank_hold-remote-2026.09.1` (promote after a passing evaluation).

Runtime/model identifiers: analysis schema `1`,
server model `nuvo-motion-baseline-v1`,
server validator `nuvo-motion-server-rules-v1`,
client pose label `mlkit-pose-base`, `specSchemaVersion 1`.

## 12. Production data audit (2026-09-27, cleanup completed)

`nuvo_db` (prod) was reset for the clean-start launch: all 8 external beta
identities were deleted through the canonical `DELETE /auth/account` path
(verified: zero carry-over on same-email re-signup). Remaining active users:
8 `demo+*@nuvo.internal` seeded accounts, 5 `@getnuvo.net` internal/review
accounts, and 4 flagged accounts with founder/teammate signals (preserved
for a founder decision — they are not external beta users). `nuvo_db_dev`
contains only disposable test accounts. Full audit trail is in the session
transcript; the pre-cleanup D1 export lives outside git in `/tmp`.

## 13. Apple boundary

Per App Store Review Guideline 2.5.2 (no downloaded executable code;
interpreted code only if it doesn't change the app's primary purpose or
bypass review):

- **SAFE:** declarative spec/threshold tuning on shipped engines, channel
  pointers, rollout percent, enable/disable, metadata, preview keyframes —
  data consumed by reviewed, already-installed runtimes.
- **NEEDS CAUTION:** new remote-defined *movements* (reviewed engines, new
  activity — content-like, generally fine), binary package assets (`.riv`
  previews — media, fine), ML model artifact delivery via
  `GET /motion/models/:v/artifact` (weights/data for an existing runtime —
  keep hash-addressed, purpose-unchanged).
- **REQUIRES APP UPDATE:** new runtime engines, native validator internals,
  any executable code, anything that changes what the verifier
  fundamentally does beyond its reviewed purpose.

The control plane deliberately ships **no executable payloads** — specs are
bounded declarative JSON validated on both Worker and client.

## 14. How to tune a movement safely

1. `signals --activity-id <a>` — see why attempts fail.
2. Copy the current release's spec; edit only engine payload fields.
3. `draft spec.json --release-id <a>-YYYY.MM.n --env dev`.
4. `evaluate --release-id <a>-YYYY.MM.n --file report.json --env dev`
   (real replay report — the gate enforces sample size + guardrails).
5. `promote --channel internal --env dev` → verify on a dev build.
6. `promote --channel stable --env dev` → verify dev stable catalog.
7. Repeat against prod. Watch `signals` for the release.
8. Bad? `disable` the release, then `rollback` the channel to last-good.

Never edit `verifier_releases.spec_json` in place — releases are
immutable; the catalog checksum would desync.

---

# System B — Nuvo Motion Intelligence (general model control)

Everything above is **System A**: movement-specific verifier releases
(pushups, squats, remote-defined motions). This section covers the
independent second system: the **general motion intelligence model** — the
MotionBERT-derived ONNX encoder behind Teach Nuvo, few-shot learning,
embeddings, and arbitrary-motion matching. The two planes share channels,
rollout, rollback, and kill-switch mechanics but have separate tables,
separate releases, and separate acceptance gates.

## B1. The current general model

| Field | Value |
| --- | --- |
| Artifact | `assets/models/motion_v2_encoder.onnx` (bundled, ~85 MB) |
| Model | MotionBERT action-finetuned encoder, fp16 export |
| SHA-256 | `8d43b34084111ad9e358f65724c1f017a3ad501221ce0ead3d2200584232a188` |
| modelFamily | `motion_v2_encoder` |
| runtimeFamily | `motionbert_rep_v1` |
| Embedding | 256-dim rep vector (`MotionV2OnnxEncoder.dimRep`) |

## B2. Compatibility contract (the boundary)

A remote model release may replace the bundled artifact **without an App
Store update** only when every field matches the runtime shipped in the
reviewed binary. Declared on every `MotionModelRelease` and checked
client-side before any download:

- `runtimeFamily` — must be `motionbert_rep_v1` (the only runtime shipped)
- `inputSchemaVersion` — 243-float windowed pose tensor (81 landmarks × 3)
- `outputSchemaVersion` — 256-dim rep embedding
- `preprocessingVersion` — ML Kit pose → normalized sequence pipeline
- `normalizationVersion` — joint-centering/scale normalization
- `embeddingSchemaVersion` — embedding semantics for learned-spec matching
- `minimumAppBuild` — oldest app build the artifact supports
- `artifactSha256` + `artifactSizeBytes` — integrity contract

Any mismatch → the model **requires an App Store update** and the app
never downloads it. The runtime is generic; the artifact is data.

## B3. Server control plane

Migration `0041_motion_model_control.sql` adds:

- `motion_model_releases` — immutable release metadata (all contract fields
  above + `status`, `evaluation_id`, `artifact_key`, `metadata_json`)
- `motion_model_channel_releases` — per-`modelFamily` channel pointers
  (`internal`/`beta`/`stable`, `previous_release_id`, `rollout_percent`)
- `motion_model_evaluations` — evaluation evidence attached to releases

Domain logic: `src/domain/motionModels.ts`. Internal routes under
`/internal/motion/models/*` (all `X-Internal-Key` guarded, all audited).
Public routes in `src/routes/motion.ts`:

- `GET /motion/models/current?modelFamily=…&channel=…` — authenticated;
  resolves the channel pointer, applies deterministic rollout bucketing
  (`sha256(userId:releaseId) % 100`, out-of-bucket users fall back to
  `previous_release_id`), returns release metadata. Omitting
  `modelFamily` keeps the **legacy `basketball_yolox` contract** —
  general-encoder releases can never leak into the old endpoint.
- `GET /motion/models/:modelVersion/artifact` — streams the R2 object with
  `x-model-version` / `x-model-sha256` headers; 404 unless the release is
  published to a channel and enabled.

## B4. Client delivery chain

`MotionV2OnnxEncoder.load()` resolves through
`MotionV2ModelSource` → `MotionModelResolver`
(`lib/features/races/ai/motion_model_*.dart`):

1. `GET /motion/models/current?modelFamily=motion_v2_encoder` — resolves
   the remote release for this user/channel.
2. Compatibility check against §B2 — incompatible releases are refused
   before any download (fail closed).
3. Cache hit (verified release, matching SHA-256 + size) → use cached file.
4. Otherwise `GET /motion/models/:modelVersion/artifact`; the response's
   `x-model-version` must equal the requested release and the body's
   SHA-256 must equal `artifactSha256` (`MotionModelArtifactIntegrity`).
5. Atomic install: bytes written to `<tmp>` then renamed — a crash
   mid-write can never leave a partial model file.
6. On **any** failure → last-known-good cache → bundled launch model.
   Network outage, Cloudflare down, corrupt R2 object, or a disabled
   release can never break Motion.

## B5. Session pinning & Teach Nuvo provenance

- `MotionV2ModelSource.load()` pins a `MotionV2ModelSession` — an
  `OrtSession` plus the resolved release identity — for the lifetime of a
  Teach Nuvo/general-motion session. A channel move mid-session changes
  only NEW sessions; the pinned session finishes on its model.
- Learned specs (`TaughtMotionV2Spec`) record **provenance**:
  `modelReleaseId` + `encoderId` + `dimRep`. `MotionV2NativeRuntime.load`
  refuses a spec whose encoder/embedding contract doesn't match the loaded
  model — an A-generated reference can never be silently compared under an
  incompatible B embedding space. (The fp16→fp32 swap keeps the same
  embedding schema, so A-learned specs remain valid under B; a future
  schema change fails closed instead of corrupting matches.)
- `MotionDiagnosticSession` lines include model version + checksum +
  source (`remote`/`cache`/`bundled`) — every diagnostic answers both
  "which verifier?" and "which general model?".

## B6. Release flow & gates

```
DRAFT → artifact uploaded to R2 (checksum-enforced)
      → evaluation recorded (baseline-vs-candidate metrics)
      → promote internal   (no eval gate — operator/testing channel)
      → promote beta/stable (eval REQUIRED: 409 model_evaluation_required)
      → disable / rollback (kill switch / pointer restore)
```

- Upload computes SHA-256 server-side; a declared-vs-actual mismatch is
  `422 artifact_checksum_mismatch`.
- Promotion validates `runtimeFamily` is known (`409
  model_runtime_family_unknown`) and the artifact exists (`409
  model_artifact_required`).
- Re-promoting the pointed release never self-references
  `previous_release_id`; rollback to the current release is a `409`.

## B7. Operator commands

```bash
# inspect
node scripts/nuvo-motion.mjs models --env dev
node scripts/nuvo-motion.mjs model-status --env dev

# release a candidate (release.json carries the full §B2 contract)
node scripts/nuvo-motion.mjs model-register release.json --env dev
node scripts/nuvo-motion.mjs model-upload \
  --release-id <id> --file model.onnx --env dev
node scripts/nuvo-motion.mjs model-evaluate \
  --release-id <id> --file report.json --env dev

# adoption control
node scripts/nuvo-motion.mjs model-promote \
  --release-id <id> --channel stable --rollout 50 --env dev

# EMERGENCY — bad model live
node scripts/nuvo-motion.mjs model-disable --release-id <id> --env dev
node scripts/nuvo-motion.mjs model-rollback \
  --family motion_v2_encoder --channel stable --release-id <last-good> --env dev
```

## B8. Disaster recovery (deterministic answers)

| Scenario | Answer |
| --- | --- |
| Model B is terrible | `model-rollback --family motion_v2_encoder --channel stable --release-id <A>` — pointer returns to the named last-good release; apps pick up A on next session start |
| Model B crashes devices | `model-disable --release-id <B>` — artifact endpoint goes 404, channel repoints to previous release, next sessions fall back |
| Cloudflare is down | Last-known-good cached model, else bundled launch model |
| R2 download fails/corrupt | Checksum verify fails → LKG cache → bundled |
| New model incompatible with old build | `minimumAppBuild` + contract check → old build never downloads it; keeps A/bundled |

## B9. Apple boundary (models)

App Store Review Guideline 2.5.2: the reviewed binary ships a **generic
ONNX runtime** (`onnxruntime` Flutter plugin) and a fixed preprocessing/
matching pipeline. A compatible `.onnx` artifact is **model data consumed
by that reviewed runtime** — the same category as shipping weights for an
already-reviewed ML feature — not executable code. The control plane can
never deliver Dart, Swift, JS, native modules, or scripts: artifacts are
hash-addressed binary blobs validated before install. A model that needs a
new runtime family, input/output schema, preprocessing, normalization, or
embedding contract is rejected by the client and requires an App Store
update that ships the new runtime.

## B10. Launch model baseline

The launch baseline is the bundled fp16 encoder (§B1). Registered on dev
as `motion_v2_encoder_fp16_2026.10.0` (release `47153fd6-…`) and pointed
by the dev `stable` channel after testing. **Production is intentionally
not migrated** — migration `0041` has been applied to dev only; prod keeps
serving the legacy `basketball_yolox` endpoint and the bundled model until
an explicit decision registers the launch release on prod. No experimental
model is stable anywhere.
