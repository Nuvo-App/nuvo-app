# Motion Package Authoring — Author → Validate → Publish → Rollout → Rollback

This is the operational recipe for adding a motion Nuvo has never compiled.
Target workflow, end to end:

```
"We want Burpees." → build MotionPackage → validate → evaluate → publish
→ stage rollout → monitor → rollback/disable if needed
```

No Dart changes, no App Store release — provided every engine/capability
the package needs is already in shipped builds.

## 1. Authoring a package

A package definition (hand-authored JSON or generator output):

```
package_def/
  release.json          — identity, engineType, spec, activity block, manifest
  assets/
    preview_front.json  — preview_v1 keyframes (optional)
    vectors.json        — test_vectors_v1 (required for sequence/taught engines)
    ref.bin             — motion_v2_spec_v1 (taught_motion_v1 only)
```

Rules:

- `engineType` must be one the current release line ships:
  `state_machine_v1 | alternating_rep_v1 | hold_v1 | sequence_match_v1 |
  taught_motion_v1 | object_composition_v1 | native_v1`.
- `spec.activityId`, `releaseId`, `engineType` must match the release row.
- `activity` block supplies displayName, camera view, instructions,
  coaching copy — everything the proof screen needs without a compiled
  definition.
- Every asset needs `id`, `type`, `sha256`, `bytes`, `required`.

## 2. Validate (local, before upload)

`nuvo-motion validate <dir>` (internal CLI over the same Dart validators):

- Parse `release.json` through `RemoteVerifierSpec`/engine parsers — the
  same strict code the client runs.
- Recompute every asset sha256, check declared bytes, enforce per-type and
  total caps.
- Dry-run the engine against bundled synthetic frames (schema smoke test).
- Check `requiredCapabilities` are all known capability strings.

Validation failure exits non-zero with the same error strings the client
produces — CI parity by construction.

## 3. Evaluate (replay harness)

For `sequence_match_v1` / `taught_motion_v1` packages, run recorded pose
replays through the spec:

```
POST /internal/motion/releases/:releaseId/evaluations
  {vectors: "r2://motion-packages/…/vectors.json", expectedCounts: {…}}
```

Worker replays each vector's landmark stream through a Dart-faithful (or
device-captured golden) harness and records pass/fail per vector.
Promotion requires ≥1 evaluation row and ≥ threshold pass rate for
model/sequence engines.

Vectors ship inside the package (`required: false`) so the app itself can
self-check in diagnostics builds.

## 4. Publish

```
POST /internal/motion/releases/draft
  → validates spec, computes checksum, writes row status='draft'

POST /internal/motion/releases/:id/package-assets
  → per asset: registers sha256/bytes/r2_key; uploads R2 object

POST /internal/motion/releases/:id/promote
  {channel: 'internal', rolloutPercent: 100}
  → flips status='stable' + moves activity_channel_releases pointer
```

New activity: insert `motion_activities` row (id, title, metadata incl.
optional `previewSequence`) before promotion so the catalog advertises it.

## 5. Stage rollout

| Channel | Audience | Mechanism |
|---|---|---|
| `internal` | dev builds | pointer move, 100% |
| `beta` | opted-in cohort | pointer + rolloutPercent + deterministic bucketing |
| `stable` | everyone | pointer at 100% after soak |

Bucket rule (new): server computes `bucket = hash(userId|releaseId) % 100`
at assignment creation for `follow_compatible_patch` races; sticky per
user+release. `pinned` races ignore percent (deterministic).

Monitor: `/internal/motion/sessions` telemetry — rep counts, engine errors,
`engine_error`/`unsupported` reasons, per-release session counts.

## 6. Rollback & disable

- **Rollback**: `POST /internal/motion/channels/stable/rollback` moves the
  pointer to the prior stable release. New sessions pin the old release;
  installed clients keep working (immutable cache). Native releases are
  the permanent floor for converted motions.
- **Disable**: `status='disabled'` — catalog drops it, sessions reject it,
  clients treat it as unavailable (bundled fallback for core motions).
- **Emergency**: `X-Motion-Remote: disabled` catalog header halts all new
  remote installs globally without blocking cached/pinned verification.

## 7. Offline & compatibility guarantees (checklist per package)

- [ ] Installs once; verifies offline thereafter.
- [ ] Old builds reject it via capability/min-build, never crash.
- [ ] Bad asset sha → keeps last-known-good, reports `asset_integrity` failure.
- [ ] Unknown activity id carries full `activity` block (no compiled def needed).
- [ ] Core bundled motions untouched.

## 8. Teach Nuvo → package path

Teach Nuvo produces a `taught_motion_v1` payload today (the
`TaughtMotionV2Spec` it already builds in-screen). The adapter:

1. Serialize the V2 spec as `motion_v2_spec_v1` asset + thin `spec`.
2. Race creation attaches it as the race verifier spec (inline, race-scoped
   like today's `custom_pose_sequence`) or promotes it to a user-scoped
   release for reuse across races.
3. Proof runs `StreamingMotionV2` through the package adapter — same
   ONNX encoder Teach already uses, no new binaries.

This replaces `createCustomRace`'s V1 `CustomPoseVerifierSpec` path when
V2 is enabled (`NUVO_FORCE_V1` keeps the geometric fallback available).
