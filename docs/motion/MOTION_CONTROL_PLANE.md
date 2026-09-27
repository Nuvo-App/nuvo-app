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

## 12. Production data audit (2026-09-27)

`nuvo_db` (prod) currently contains **27 users**: 8 `demo+*@nuvo.internal`
seeded accounts, ~6 `@getnuvo.net` internal/review accounts, ~11 external
beta identities (gmail/outlook/icloud/Apple private-relay), 2 deleted.
`nuvo_db_dev` contains only disposable test accounts.

Per the launch decision (public App Store release = clean start, no beta
migration): these beta identities currently live **in** production D1 —
they are not a separate beta environment. Before launch, decide and execute
deliberately: either provision a fresh production database/worker pair for
the public app, or run a scoped beta-identity purge. Do not delete blind —
this table is the complete inventory to decide from. `@getnuvo.net` and
`demo+` accounts may be intentionally retained; external beta identities
are the carry-over population the launch decision excludes.

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
