# Cloudflare Delivery — Motion Runtime V1

The Worker is the control plane; the phone is the data plane. Cloudflare
delivers structured packages; execution is always local, bounded, and
engine-allowlisted.

## 1. Existing delivery surface (kept)

| Endpoint | Role |
|---|---|
| `GET /races/activities` | Activity catalog. D1 registry + ETag + static fallback. Returns release identity, checksum, engine, capabilities, min build, metadata, `previewSequence`. |
| `GET /motion/releases/:releaseId` | Immutable release JSON (`spec_json` incl. new `package` block). ETag `releaseId:checksum`, `max-age=300`. |
| `GET /motion/models/:version/artifact` | R2 model bytes (object-composition path today). |
| `POST /races/:raceId/verification-sessions` | Freezes releaseId+checksum; returns pinned spec. |
| `GET /internal/motion/*` | Draft/validate/promote/rollback/metrics, `X-Internal-Key` auth. |

Additive V1 changes — no existing contract renamed or removed.

## 2. D1 additions

```sql
-- package manifest alongside existing release row
ALTER TABLE verifier_releases ADD COLUMN package_json TEXT;
ALTER TABLE verifier_releases ADD COLUMN package_checksum TEXT;

-- asset registry (content-addressed, shared across releases)
CREATE TABLE IF NOT EXISTS motion_package_assets (
  id            TEXT PRIMARY KEY,        -- sha256 hex
  release_id    TEXT NOT NULL,
  asset_type    TEXT NOT NULL,           -- preview_v1 | motion_v2_spec_v1 | onnx_model | test_vectors_v1
  r2_key        TEXT NOT NULL,
  bytes         INTEGER NOT NULL,
  sha256        TEXT NOT NULL,
  required      INTEGER NOT NULL DEFAULT 1,
  created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Rollback compatibility: `package_json` is additive; an old binary reading a
V1 release sees a `spec` it can't execute (new engine id / new schema) and
rejects via capability/min-build gates — identical failure mode to any
unsupported release today.

## 3. R2 layout

```
motion-packages/<activityId>/<releaseId>/<assetId>   (package assets)
motion-models/<modelVersion>                          (existing ONNX path)
```

Assets immutable once published — same id → same bytes is enforced by
rejecting overwrite on publish (checksum mismatch = new asset id).

## 4. Catalog response (additive fields)

```json
{
  "id": "burpees_pro",
  "name": "Burpees Pro",
  "releaseId": "burpees-remote-2026.10.1",
  "releaseChecksum": "…",
  "engineType": "sequence_match_v1",
  "requiredCapabilities": ["pose_landmarks_v1","derived_features_v2","sequence_match_v1"],
  "minimumAppBuild": 42,
  "previewSequence": { "…": "existing inline path stays valid" },
  "packageAssetCount": 3
}
```

Capability filtering already hides unsupported engines from the composer —
new engines simply never appear on old builds.

## 5. New endpoint — package asset fetch

```
GET /motion/releases/:releaseId/assets/:assetId
→ 302 to R2 signed URL, or direct bytes with
   ETag: "<sha256>"  Cache-Control: public, max-age=31536000, immutable
```

Client verifies SHA-256 after download (`MotionModelArtifactIntegrity`
pattern). Content-addressed → cacheable forever → offline replay works.

## 6. Publication workflow (internal API, additive)

```
POST /internal/motion/releases/:releaseId/package-assets
   {assetId, type, r2Key, bytes, sha256, required}
   → validates bounds, registers rows, attaches package_json to release
POST /internal/motion/releases/draft        (existing — validates spec)
POST /internal/motion/releases/:id/evaluations   (existing — replay harness)
POST /internal/motion/releases/:id/promote  (existing — channel pointer)
POST /internal/motion/channels/:channel/rollback (existing)
```

Promotion rules (new checks, same endpoints):

- release `engine_type` ∈ allowlist + all required capabilities are known
  capability strings the registry understands;
- every `required` asset row exists in `motion_package_assets`, R2 object
  exists, sha256 matches row;
- package total bytes under cap;
- at least one evaluation row exists for `sequence_match_v1` /
  `taught_motion_v1` engines (rules engines keep today's lighter bar).

## 7. Rollout & rollback

- `rollout_percent` gains deterministic bucketing: bucket =
  `hash(raceId|userId, releaseId) mod 100 < rolloutPercent` evaluated when
  an assignment is created for `follow_compatible_patch` races (server side,
  sticky per race+user). Existing pointer move semantics unchanged.
- Rollback = move channel pointer to prior release (existing endpoint).
  Native releases from 0015 remain the floor for converted activities.
- Disable = `status='disabled'` on release + channel pointer removed;
  client treats missing release as today (bundled fallback for core
  motions, unavailable for remote-only activities).
- Kill switch (new, small): `GET /races/activities` response header
  `X-Motion-Remote: disabled` tells clients to skip remote installs for new
  sessions — pinned sessions still honor cached releases offline.

## 8. Caching / offline contract

- Catalog: ETag + last-known-good (unchanged).
- Release: immutable, `max-age=300` (unchanged).
- Package assets: immutable, effectively forever.
- After a release+assets are installed, **zero network** is needed to run
  that race — session create degrades to cached pinning when offline.
- Bundled core motions (`native_v1` floor) work with Cloudflare down.

## 9. Telemetry

Session artifact already carries releaseId. V1 adds `packageSchemaVersion`
and per-asset fetch results (duration, bytes, verified) to the session
artifact metadata — diagnostics only. (Pose-landmark upload is a separate,
consent-gated training pipeline: off by default, opt-in via "Help improve
Nuvo", encrypted, purged ~90d — see docs/compliance/DATA_FLOW_MAP.md.)
