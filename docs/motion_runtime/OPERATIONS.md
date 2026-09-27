# Motion Control Plane — Operations

How to change, publish, roll out, roll back, and kill a Nuvo verifier release
or preview **without an App Store build**. Every command below was verified
against the live Workers on 2026-09-27.

The workflow is `author → validate → draft → evaluate → promote`, never raw
D1 edits. All writes go through `X-Internal-Key`-gated endpoints on the
Worker; every mutation lands in `verifier_audit_log`.

## Setup

```bash
cd server/worker

# Cloudflare account (required non-interactively; matches wrangler.toml)
export CLOUDFLARE_ACCOUNT_ID=d618e374fb4ffb44dbc770dd07431f79

# Internal API key — read it from .dev.vars (never paste it into commands
# or docs). The dev Worker secret is aligned with this value.
export NUVO_INTERNAL_KEY=$(grep '^INTERNAL_API_KEY=' .dev.vars | cut -d= -f2-)
```

CLI: `scripts/nuvo-motion.mjs` (no deps, Node 18+). `--env dev` targets
`nuvo-api-dev`; omit for prod.

## 1. Check current state

```bash
# What the public catalog serves on a channel:
node scripts/nuvo-motion.mjs list --channel stable            # prod
node scripts/nuvo-motion.mjs list --channel internal --env dev

# Every release + channel pointer for one activity:
node scripts/nuvo-motion.mjs releases remote_seq_squats

# Failure telemetry feeding release decisions:
node scripts/nuvo-motion.mjs signals --activity-id remote_seq_squats
```

## 2. Validate a spec

There is no standalone validate endpoint — drafting IS the validation gate.
A spec that fails `validateMotionVerifierSpec` returns `400` with a machine
code (`sequence_chain_invalid`, `package_assets_invalid`, …) and writes
nothing. To dry-run without creating a draft, validate locally:

```bash
node -e "require('./dist/...')"   # or just draft it — drafts are invisible
```

## 3. Publish to dev (draft a release)

A spec file must contain `activityId`, `releaseId` (matching `--release-id`),
`engineType`, `specSchemaVersion`, and the engine payload. See migration
`0034_remote_sequence_squats.sql` for a canonical `sequence_match_v1` spec.

```bash
node scripts/nuvo-motion.mjs draft spec.json \
  --release-id remote_seq_squats-2026.11.0 \
  --parent remote_seq_squats-2026.10.0 \
  --semver 2026.11.0 --change-class patch --notes "tighten crouch" --env dev
```

Releases are **immutable**. New content = new release = new checksum.

## 4. Evaluate (required before any promotion)

The release must have a passing evaluation run:

```bash
node scripts/nuvo-motion.mjs evaluate \
  --release-id remote_seq_squats-2026.11.0 --file report.json --env dev
```

`report.json` shape: `{"datasetSnapshotId":"...","metrics":{...},"failures":[...]}`
(see `parseEvaluationReport` in `src/domain/motionEvaluation.ts`).
Promoting before evaluation → `409 Release must pass evaluation`.

## 5. Promote to internal, test on device

```bash
node scripts/nuvo-motion.mjs promote --release-id remote_seq_squats-2026.11.0 \
  --channel internal --env dev
```

On device, the app reads `GET /races/activities?channel=internal`
(internal builds). Confirm the catalog shows the new `currentReleaseId`,
then fetch `GET /motion/releases/<releaseId>` — the client runs exactly this
path (`MotionCatalogSnapshot` → `VerifierRelease` → `RemoteVerifierSpec` →
capability check).

## 6. Promote to stable

```bash
node scripts/nuvo-motion.mjs promote --release-id remote_seq_squats-2026.11.0 \
  --channel stable --env dev        # then, when verified:
node scripts/nuvo-motion.mjs promote --release-id remote_seq_squats-2026.11.0 \
  --channel stable                  # prod
```

Stable promotion re-checks that a passing evaluation exists. A `stable`
release cannot be demoted by another promote call — pointer moves go through
rollback/disable.

## 7. Roll back

```bash
node scripts/nuvo-motion.mjs rollback \
  --activity-id remote_seq_squats --channel stable \
  --release-id remote_seq_squats-2026.10.0
```

Verified live: catalog `currentReleaseId` flips back to the prior release on
the next request. A `disabled` target is refused. Rollback sets
`rollout_percent = 100`.

## 8. Disable a bad release (kill switch)

```bash
node scripts/nuvo-motion.mjs disable --release-id remote_seq_squats-2026.11.0
```

Truth: `verifier_releases.status` is the kill switch — there is no channel
`disabled` flag. `status='disabled'` fails closed for all NEW resolution
(`stableReleaseForActivity` requires `'stable'`; session creation re-checks
it). If a disabled release is the channel pointer, the public catalog masks
its release fields instead of advertising it. Pinned sessions keep working —
a kill never bricks an in-flight proof. Fetch by ID still serves the release
so pinned sessions resolve.

## 9. Inspect audit + metrics

```bash
node scripts/nuvo-motion.mjs audit --activity-id remote_seq_squats
node scripts/nuvo-motion.mjs audit --action release_disabled
node scripts/nuvo-motion.mjs signals --release-id remote_seq_squats-2026.11.0
```

Every draft / evaluation / promotion / rollback / disable / preview update /
asset upload writes `verifier_audit_log` with actor, prior release, and
details.

## 10. Preview update workflow

Two delivery modes:

**A. Inline keyframe preview** (activity metadata → public catalog
`previewSequence` → `RemoteMovementPreview`; client falls back to bundled
animation on any malformed data):

```bash
# {"rig":"front"|"side","durationMs":1600,"keyframes":[{...},{...},...]}
node scripts/nuvo-motion.mjs preview remote_seq_squats seq.json --env dev
node scripts/nuvo-motion.mjs preview remote_seq_squats --clear --env dev
```

Works for native presets too — the client looks up `previewSequence` by
activity ID for every movement.

**B. Binary preview/asset** (`preview_v1` and other types ride the package
envelope). Declare the asset in the spec's `package.assets` block
(`id`, `type`, `sha256`, `bytes`), draft the release, then upload — the
server refuses bytes that don't match the declared checksum:

```bash
node scripts/nuvo-motion.mjs upload-asset \
  --release-id remote_seq_squats-2026.11.0 --asset-id preview.riv \
  --file preview.riv --env dev
```

Assets are immutable once a release reaches `stable`.

## 11. Emergency recovery

```bash
# Broken release live on stable:
node scripts/nuvo-motion.mjs disable --release-id <bad>          # kill new use
node scripts/nuvo-motion.mjs rollback --activity-id <a> \
  --channel stable --release-id <last-good>                       # restore
node scripts/nuvo-motion.mjs audit --activity-id <a>              # verify trail
```

Direct SQL is diagnosis-only. The D1 console is emergency tooling:
`npx wrangler d1 execute nuvo_db --remote --command "..."` (see
`cloudflare_d1_operations.md`). Never UPDATE `verifier_releases.spec_json` —
releases are immutable; the catalog checksum would no longer match the spec.

## 12. Exact prod/dev commands

```bash
# Migrations (review SQL first — additive only):
npm run migrate:dev     # nuvo_db_dev
npm run migrate:prod    # nuvo_db

# Deploys:
npm run deploy:dev      # nuvo-api-dev
npm run deploy:prod     # nuvo-api

# Ops (every command takes --env dev; default is prod):
node scripts/nuvo-motion.mjs <list|releases|draft|evaluate|promote|rollback|disable|preview|upload-asset|audit|signals> ...
```

## What is NOT remotely controllable today

- **Native preset logic.** `native_v1` releases are metadata-only handles on
  validators compiled into the app binary. Thresholds inside `push_ups`,
  `plank`, etc. still require an App Store build. What IS remote: which
  release a channel points to, display metadata, previews, and whether the
  release is enabled.
- **New runtime engines.** A release can only use an engine the installed
  client already ships (`native_v1`, `state_machine_v1`,
  `alternating_rep_v1`, `hold_v1`, `sequence_match_v1`,
  `object_composition_v1`). The spec's `requiredCapabilities` /
  `minimumAppBuild` fields gate this; incompatible installs report
  unsupported instead of crashing.
- **Rollout semantics.** `rollout_percent` is real, deterministic bucketing
  (`sha256(userId:releaseId) % 100`) with previous-stable fallback — but it
  only affects NEW race/session assignment; nothing force-migrates a pinned
  session.
