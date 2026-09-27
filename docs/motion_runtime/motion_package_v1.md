# MotionPackage V1 — Schema

A MotionPackage is the unit Cloudflare delivers and the phone executes. It
is **data, never code**: every field is allowlisted, every list is bounded,
every number is clamped. The App Store binary owns all executable engines;
the package configures them.

## 1. Envelope

The package rides inside the existing immutable release. `verifier_releases`
already provides `id`, `activity_id`, `engine_type`, `checksum`,
`required_capabilities_json`, `minimum_app_build`, `compatibility_group`,
`spec_json`. V1 adds a sibling `package` object in `spec_json` — a peer of
`spec`, not inside it — because the `RemoteVerifierSpec` parser correctly
rejects unknown fields and we keep that strictness.

```json
{
  "specSchemaVersion": 2,
  "releaseId": "burpees-remote-2026.10.1",
  "activityId": "burpees_pro",
  "engineType": "sequence_match_v1",
  "measurementType": "repetitions",
  "requiredCapabilities": ["pose_landmarks_v1", "derived_features_v2", "sequence_match_v1"],
  "spec": { "...": "engine payload (see §3)" },
  "activity": { "...": "display/camera metadata (see §4)" },
  "package": {
    "packageSchemaVersion": 1,
    "assets": [
      {
        "id": "preview_front",
        "type": "preview_v1",
        "sha256": "…",
        "url": "r2://motion-packages/burpees_pro/preview_front.json",
        "bytes": 18340,
        "required": false
      },
      {
        "id": "reference_embedding",
        "type": "motion_v2_spec_v1",
        "sha256": "…",
        "url": "r2://motion-packages/burpees_pro/ref.bin",
        "bytes": 42000,
        "required": true
      },
      {
        "id": "test_vectors",
        "type": "test_vectors_v1",
        "sha256": "…",
        "url": "r2://motion-packages/burpees_pro/vectors.json",
        "bytes": 310000,
        "required": false
      }
    ]
  }
}
```

Rules:

- `package` is optional. Its absence = spec-only release (today's shape).
- `required: true` assets must download + verify before activation;
  `required: false` assets may degrade (preview falls back to bundled art,
  test vectors are dev-tool only and never fetched by shipping builds
  unless a diagnostics flag is set).
- `url` is host-relative or `r2://` — the client resolves against the
  configured artifact base; it never follows arbitrary third-party URLs.
- `bytes` is both an integrity check and a download guard; client refuses
  assets over the per-type cap even if declared.

## 2. Bounds (client enforces before activation)

| Field | Bound |
|---|---|
| assets per package | ≤ 8 |
| asset id / type length | ≤ 64 chars |
| total package bytes | ≤ 64 MB (default; per-type caps below) |
| preview_v1 | ≤ 256 KB |
| test_vectors_v1 | ≤ 2 MB |
| motion_v2_spec_v1 | ≤ 512 KB |
| onnx_model | ≤ 50 MB, declared `inputSchema`/`outputSchema`/`opset` required |
| url length | ≤ 512 chars, scheme/host allowlisted |

Per-asset SHA-256 verified after download, before activation. Atomic:
assets + manifest land under `packages/<releaseId>/`, manifest written
last via `.tmp` rename (same pattern as `verifier_release_cache_io.dart`).

## 3. Engine payloads (`spec` object)

### 3.1 `state_machine_v1` / `alternating_rep_v1` / `hold_v1`

Existing schema, unchanged. Spec v2 adds optional `feature`-based rules:

```json
{
  "startRules": [
    { "point": "leftKnee", "axis": "y", "operator": "lte", "threshold": 0.68 },
    { "feature": "kneeAngle", "side": "left", "operator": "lt", "threshold": 110 }
  ]
}
```

Allowlisted `feature` values (spec v2, `derived_features_v2` capability):

- `jointAngle` — `joint` ∈ {knee, hip, elbow, shoulder}, `side` ∈ {left,right}
- `landmarkDistance` — `a`, `b` landmarks, normalized by torso length
- `landmarkRatio` — `numerator`/`denominator` landmark pairs
- `verticalVelocity` — landmark, window-bounded
- `airborne` — boolean (baseline-relative, `AirborneStateTracker`)
- `heightAbove` — landmark vs baseline landmark, normalized

Each feature condition carries `minLikelihood` and is clamped to the same
bounds as landmark rules. Unknown feature names are rejected at parse.

### 3.2 `sequence_match_v1` (new)

Ordered phase machine over the same condition vocabulary:

```json
{
  "phases": [
    { "id": "standing", "conditions": [ {"feature":"kneeAngle","side":"left","operator":"gt","threshold":160} ] },
    { "id": "squat",    "conditions": [ {"feature":"kneeAngle","side":"left","operator":"lt","threshold":110} ] },
    { "id": "airborne", "conditions": [ {"feature":"airborne","operator":"eq","threshold":1} ] }
  ],
  "resetPhaseId": "standing",
  "phaseTimeoutMs": 3000,
  "requiredLandmarks": ["leftHip","rightHip","leftKnee","rightKnee","leftAnkle","rightAnkle"]
}
```

- ≤ 8 phases, ≤ 12 conditions per phase, `phaseTimeoutMs` ≤ 30 s.
- A rep completes when phases 0…N are satisfied in order and the machine
  returns to `resetPhaseId`. Timeout drops to phase 0 (no count).
- `MultiPhaseSequenceTracker` + `AirborneStateTracker` supply the runtime
  mechanics; the spec only names conditions and order.

### 3.3 `taught_motion_v1` (Motion V2 as package engine)

```json
{
  "spec": {
    "engineType": "taught_motion_v1",
    "referenceAssetId": "reference_embedding",
    "matchThreshold": 0.5,
    "windowFrames": 60,
    "fpsHint": 15,
    "measurementType": "repetitions",
    "requiredLandmarks": ["…": "…"]
  }
}
```

- The MotionBERT encoder is **bundled** (`motion_v2_onnx_encoder`); the
  package carries only the per-motion reference spec
  (`TaughtMotionV2Spec`-shaped, or a binary `motion_v2_spec_v1` asset).
- `matchThreshold`, window size, fps are bounded server-side
  (`0.3 ≤ threshold ≤ 0.9`, `8 ≤ windowFrames ≤ 300`).
- Same artifact may ship as `required` asset or inline JSON — asset
  preferred when >64 KB to keep `spec_json` small.

### 3.4 `object_composition_v1`

Existing schema; `model` block gains `assetId` pointing at a manifest
`onnx_model` asset instead of an implicit model-version URL. Legacy form
(model version → `/motion/models/:v/artifact`) stays supported.

### 3.5 `native_v1`

Unchanged: `{ "nativeKey": "<activity backend value>" }` — pointer to the
compiled validator. This is the bundled floor every remote package can roll
back to.

## 4. `activity` block (remote identity — new)

Replaces dependence on `motionActivityForType`/`MotionActivityType`:

```json
{
  "activity": {
    "displayName": "Burpees Pro",
    "measurementType": "repetitions",
    "defaultTarget": 10,
    "preferredCameraView": "front",
    "instructions": ["Whole body in frame.", "…"],
    "coachingTextActive": "Drive through the finish line.",
    "coachingTextIncomplete": "Step back so we can see you."
  }
}
```

Bounded: strings ≤ 140 chars, ≤ 6 instructions. Display metadata never
selects verifier behavior — engines read only `spec`.

## 5. Versioning hooks

- `specSchemaVersion`: 2 for feature-rules/sequence/packages. Old clients
  (schema 1) can't parse → capability/min-build gate rejects first.
- `packageSchemaVersion`: 1. Unknown → package treated as spec-only; if
  engine requires assets the release is rejected, never half-installed.
- `compatibilityGroup` / `minimumAppBuild` / `requiredCapabilities` —
  existing release fields, unchanged semantics.

See `versioning.md` for the full compat matrix.

## 6. Non-goals (V1)

No arbitrary expressions, no scripting, no remote UI, no downloadable Dart/
JS/native code, no marketplace. A package configures allowlisted engines —
that's all.
