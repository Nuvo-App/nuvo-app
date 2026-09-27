# Cloudflare D1 Operations — Motion Control Plane

Operator manual for the D1/R2 infrastructure behind the remote motion
pipeline. Every command here was verified against the live repo on
2026-09-27 (wrangler 4.103.0).

## Resources

| Resource | Env | Binding | Cloudflare resource | ID |
|---|---|---|---|---|
| D1 (prod) | top-level | `DB` | `nuvo_db` | `c46cb25d-f2b1-47cb-9e50-d8d1324e640e` |
| D1 (dev) | `env.dev` | `DB` | `nuvo_db_dev` | `29193d3c-cf97-444a-8338-6f7c1b407a26` |
| R2 (prod) | top-level | `PROFILE_PHOTOS` | `nuvor2` | — |
| R2 (dev) | `env.dev` | `PROFILE_PHOTOS` | `nuvor2-dev` | — |
| Worker (prod) | top-level | — | `nuvo-api` | `https://nuvo-api.getnuvoapp.workers.dev` |
| Worker (dev) | `env.dev` | — | `nuvo-api-dev` | workers.dev route |

- No KV namespaces. No Durable Objects.
- `PROFILE_PHOTOS` serves two key spaces: profile media and motion package
  assets (`motion-packages/{releaseId}/{assetId}`, written only by the
  internal asset-upload route after checksum validation).
- Crons (`0 3 * * *`, `*/5 * * * *`) are declared at top level and therefore
  apply to every deployed environment — including `nuvo-api-dev` if deployed.

## Environment separation (truth, not aspiration)

There are exactly TWO environments: prod (`nuvo-api` → `nuvo_db`) and dev
(`nuvo-api-dev` → `nuvo_db_dev`). There is no staging. Each Worker binds its
own database and bucket, so prod writes can never reach dev data and vice
versa. `wrangler dev --env dev` runs locally with bindings pointed at the
dev resources; add `--remote` to hit the real dev D1/R2, otherwise wrangler
emulates locally.

Smallest safe improvement if a staging tier is ever needed: copy the
`env.dev` block to `env.staging` with dedicated `nuvo_db_staging` /
`nuvor2-staging` resources — do not reuse the dev or prod IDs.

## Wrangler auth

The CLI user has access to multiple Cloudflare accounts, and `d1` commands
fail non-interactively without an explicit account:

```bash
export CLOUDFLARE_ACCOUNT_ID=d618e374fb4ffb44dbc770dd07431f79
```

`wrangler deploy` honors `account_id` inside `wrangler.toml`, but export the
variable anyway for consistent behavior across all commands.

## Inspect migrations

```bash
cd server/worker
npx wrangler d1 migrations list nuvo_db --remote          # prod
npx wrangler d1 migrations list nuvo_db_dev --remote --env dev
```

"✅ No migrations to apply!" = remote is current. Otherwise it prints the
pending files by name.

## Apply migrations

Local (emulated dev DB only — harmless):

```bash
npx wrangler d1 migrations apply nuvo_db_dev --local --env dev
```

Remote:

```bash
npm run migrate:dev    # = wrangler d1 migrations apply nuvo_db_dev --remote --env dev
npm run migrate:prod   # = wrangler d1 migrations apply nuvo_db --remote
```

Always apply to dev first, verify, then prod. Wrangler is idempotent —
applied files are never re-run.

## Check schema

```bash
# all tables
npx wrangler d1 execute nuvo_db --remote --command \
  "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" --json

# channel/release state (control plane at a glance)
npx wrangler d1 execute nuvo_db --remote --command \
  "SELECT c.activity_id, c.channel, c.release_id, c.rollout_percent, r.status, r.engine_type
   FROM activity_channel_releases c JOIN verifier_releases r ON r.id = c.release_id
   ORDER BY c.activity_id, c.channel"

# one release row
npx wrangler d1 execute nuvo_db --remote --command \
  "SELECT id, activity_id, engine_type, checksum, status, minimum_app_build
   FROM verifier_releases WHERE id = 'remote_seq_squats-2026.10.0'"
```

`--json` on `d1 execute` returns machine-readable results.

## Control-plane tables

| Table | Purpose | Created by |
|---|---|---|
| `motion_activities` | Activity registry (display name, metric, availability, metadata) | 0015 |
| `verifier_releases` | Immutable release rows: spec_json + `sha256:` checksum + capabilities + minimum build | 0016 |
| `activity_channel_releases` | `(activity_id, channel) → release_id` pointers + rollout_percent; channels `internal`/`beta`/`stable` | 0015 |
| `verifier_audit_log` | Control-plane action audit | 0015 |
| `verifier_evaluation_runs` | Evaluation gates before promotion | 0017 |
| `motion_release_metrics` | Release health metrics | 0017 |
| `verification_sessions` | Session-pinned `release_id`/`release_checksum`; completion rejects drift | 0013 |
| `race_verifier_assignments` | Per-race verifier assignment (lazy backfill) | 0016 |
| `motion_model_releases` | Binary model artifact metadata (e.g. ONNX) | 0019–0021 |
| `motion_analysis_jobs`, `motion_sessions`, `motion_account_keys`, `motion_feedback_labels`, `motion_training_examples` | Analysis/training pipeline | 0012–0017 |
| `race_events`, `race_attempts` | Race V2 event log + attempt ledger | 0030 |

Releases are immutable; channels move by repointing
`activity_channel_releases`, never by editing `verifier_releases`.
"Disabled" = `verifier_releases.status` changed or the channel pointer
removed/rollout set to 0 — there is no `disabled` column.

## Add a migration

- Files live in `server/worker/migrations/NNNN_name.sql`; numbering is
  zero-padded sequential. Current head: **0034** (`0034_remote_sequence_squats`).
- Before numbering, `git pull` and `ls migrations/` — other agents add
  migrations concurrently; the live tree is authoritative, never a plan doc.
- Keep migrations ADDITIVE (CREATE/ALTER-ADD/INSERT OR IGNORE or REPLACE).
  DROP/DELETE/mass-UPDATE requires explicit review.
- Validate fixture specs by running `validateMotionVerifierSpec` from
  `src/domain/motionSpec.ts` against the spec_json before shipping — an
  invalid spec silently 404s at `/motion/releases/:id`.
- Release checksums: `sha256:` + sha256-hex of the canonical
  `JSON.stringify(spec)` (same convention as the internal publish route).
- Rollback of an additive seed: disable the channel pointer in a NEW
  migration (e.g. `UPDATE activity_channel_releases SET rollout_percent=0`)
  or flip `verifier_releases.status` — never hand-edit the DB.

## Seed control-plane data (approved process)

Canonical path for fixtures/defaults: a numbered migration with
`INSERT OR IGNORE` (activity + release) and `INSERT OR REPLACE` (channel
pointer). See 0033/0034. Long-term authoring should go through the internal
control-plane routes in `src/routes/internal.ts` (draft → evaluate →
promote), not D1 console edits.

## Promote a release

Internal API (requires `INTERNAL_API_KEY` secret, header per
`src/routes/internal.ts`): publish release → set channel pointer with
`rollout_percent`. Channel pointers support `internal`, `beta`, `stable`;
rollout 0–100 gates client-side eligibility.

## Roll back

Repoint the channel row to the previous release id via the internal route,
or ship a corrective migration `UPDATE activity_channel_releases SET
release_id='<prev>' WHERE activity_id='<id>' AND channel='stable'`.
`verifier_releases` stays immutable — rollback is pointer movement only.

## Emergency disable

Fastest kill: `UPDATE activity_channel_releases SET rollout_percent = 0`
for the activity/channel — existing sessions keep their pinned release
(completion still validates against the pin), new resolution stops.
A hard kill flips `verifier_releases.status` away from `stable` — catalog
still joins the row, but the release-serving path and evaluation gates
reject non-stable status.

## Deploy the Worker

```bash
npm run typecheck && npm test     # gates
npm run deploy:prod               # = wrangler deploy (prod, top-level env)
npm run deploy:dev                # = wrangler deploy --env dev
```

After deploy, verify the live read path, not localhost:

```bash
curl -s https://nuvo-api.getnuvoapp.workers.dev/races/activities | python3 -m json.tool | less
curl -s https://nuvo-api.getnuvoapp.workers.dev/motion/releases/<releaseId>
```

## Secrets (names only — verified configured remotely 2026-09-27)

| Secret | Used for | Prod | Dev |
|---|---|---|---|
| `INTERNAL_API_KEY` | Internal control-plane + asset-upload routes | yes | yes |
| `JWT_SECRET` | Session token signing | yes | yes |
| `GOOGLE_IOS_CLIENT_ID` | Google sign-in | yes | yes |
| `RESEND_API_KEY` | Email delivery | yes | yes |
| `REVIEWER_PASSWORD_HASH` | Reviewer tools | yes | yes |
| `MOTION_DATA_MASTER_KEY` | Motion-data encryption (privacy features) | NOT set — call-site throws if used | NOT set |
| `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT` | Push notifications | NOT set — push paths no-op | NOT set |

`wrangler secret list [--env dev]` prints names only.

## Never do

- Never hand-edit prod rows via `d1 execute` for normal motion ops — D1 is
  persistence; authoring goes through migrations (fixtures) or the internal
  control-plane API (real releases).
- Never `UPDATE`/`DELETE` `verifier_releases` — releases are immutable;
  move channel pointers instead.
- Never commit secret values or put them in `wrangler.toml` vars.
- Never apply a migration file that renumbers or rewrites an already-applied
  migration — append a new number.
- Never deploy with a generic `wrangler deploy` without knowing which env
  you're on — top-level = prod.
