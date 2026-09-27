# Nuvo Motion Runtime V1 — Architecture

Status: Phase A/B recon + design doc. Sections below describe the
pre-implementation state — read them as "what we found", then see the
implementation ledger for what actually shipped. Companion docs:

## Implementation status (updated at D2 landing)

SHIPPED:

- Remote activity identity end-to-end — server-owned IDs resolve, verify, and
  appear in proof payloads with the raw ID preserved (no `pushUps` fallback;
  `AiMotionActivity.remote` + `remoteActivityId` carry it). Acceptance
  fixture: `remote_test_motion` (migration `0033`).
- Package envelope parser — `lib/features/races/data/motion_package.dart`
  (content-addressed assets, per-type caps, `remoteActivityInfo`,
  `requiredCapabilities`, `spec_sha256`).
- Release control plane — immutable releases, checksums, channels
  (internal/beta/stable), deterministic rollout bucketing, kill switch,
  previous-stable fallback, evaluation gate for stable promotion.
- `sequence_match_v1` — linear phase-chain engine (closed predicate grammar:
  `landmark_axis` / `angle` / `axis_delta` / `segment_ratio`), dwell +
  hysteresis + lost-pose + rep-timeout semantics, mirrored Worker validation,
  capability `sequence_match_v1` advertised.
- Package installer + content-addressed store —
  `lib/features/races/data/motion_package_installer.dart` +
  `motion_package_store{,_io,_web}.dart`: staged download → byte cap →
  SHA-256 → per-type sanity → atomic `rename` promote. Required-asset failure
  gates the camera session; optional assets (previews/test vectors) degrade
  without blocking. Pin protection keeps an active session's package from
  pruning; launch-time sweep removes abandoned staging dirs.
- Worker package asset delivery — `POST/GET
  /motion/releases/:releaseId/assets/:assetId` (upload is internal-keyed,
  checksum-verified against the immutable manifest before it lands in R2;
  download is public, declares-only, drift-checked on serve).
- Capability API — `MotionCapabilityService` answers
  supported/installed/installPending/engine/release/reason per activityId
  without exposing package internals.

NOT YET SHIPPED (design only):

- `taught_motion_v1` adapter over the Motion V2 encoder.
- Release-pinned preview assets (`preview_v1`), feature-config block in the
  catalog, `nuvo-motion` authoring CLI, session-observability columns.
- Original doc below still marks several now-fixed seams as gaps (#4, #5, #6,
  #10 are resolved as noted above).

- `motion_package_v1.md` — package schema
- `cloudflare_delivery.md` — Worker/D1/R2 delivery design
- `security.md` — trust model and integrity
- `versioning.md` — schema/compat/version rules
- `package_authoring.md` — author → validate → publish → rollout → rollback

---

## 1. Success test

> If we upload a completely new motion package tomorrow, can Nuvo understand it
> without knowing that motion's name at compile time?

Today the honest answer is **partially**:

- The catalog can list a server-owned activity ID the build has never seen
  (`backendId`, appended after bundled activities).
- An immutable release can be fetched, verified, and cached offline.
- A remote declarative spec can drive the camera verifier — **but only when
  `spec.activityId` maps to a compiled `MotionActivityType`**.
  `camera_verification_resolver.dart` rejects `MotionActivityType.remote` as
  `remote_activity_not_supported_by_runtime`, and camera framing/instructions
  come from `motionActivityForType(movement)` — the compiled catalog.
- The proof payload's activity identity is `AiMotionActivity` (a second,
  separate enum) whose `fromBackendValue` falls back to `pushUps` for unknown
  values.

So: remote delivery exists, remote engines exist, but **activity identity and
runtime selection are still compile-time**. That is the gap Motion Runtime V1
closes.

---

## 2. Current architecture (verified Phase A recon)

```
Camera → pose_detector_service (ML Kit) → NuvoPoseFrame
       → PoseTrack/PoseNormalizer (custom-pose path) or raw landmarks (preset/remote)
       → verifier runtime (one of five families below)
       → AiMotionResult / ObjectComposition result / CustomPoseResult
       → proof payload → Worker verify → leaderboard
```

### 2.1 Five verifier families already exist

| Family | Engine id | Code | Data-driven? | Used by |
|---|---|---|---|---|
| Native preset | `native_v1` | `motion_validators.dart` `createMotionValidator` switch → `ConfigurableRepValidator`, `PushupsValidator`, `HighKneesValidator`, `PlankHoldValidator`, `MultiPhaseSequenceValidator`, `CadenceMotionValidator`, specialized validators | No — compile-time switch | 23 bundled activities |
| Declarative rules | `state_machine_v1`, `alternating_rep_v1`, `hold_v1` | `remote_verifier_spec.dart` + `remote_verifier_runtime.dart` | Yes — bounded JSON spec | 4 seeded releases (arm_raises, squats, jumping_jacks, plank_hold) |
| Object composition | `object_composition_v1` | `object_composition_spec.dart` + `object_composition_runtime.dart` | Yes — spec + remote ONNX artifact | basketball_shot |
| Custom geometric | `custom_pose_sequence` (verifierType on race, not a release engine) | `custom_pose_verifier_spec.dart` + `custom_pose_sequence_runtime.dart` | Yes — per-race inline spec | Teach Nuvo races |
| Learned model (Motion V2) | `motion_v2` (spec field `verifier: 'motion_v2'`) | `motion_v2/*` — bundled MotionBERT ONNX encoder + `StreamingMotionV2` matcher | Spec is data; engine bundled | Teach Nuvo screen only — never reaches race verification |

### 2.2 Control plane already built (Stages 0–4)

- `GET /races/activities` — D1 registry + ETag + static fallback catalog.
- `GET /motion/releases/:releaseId` — immutable release, ETag
  `"releaseId:checksum"`, `Cache-Control: public, max-age=300`.
- `race.verifier_release_id` + `race_verifier_assignments` — race pins a
  release (`pinned` or `follow_compatible_patch`).
- `POST /races/:id/verification-sessions` — freezes release id + checksum,
  returns the spec to run.
- Internal API (`X-Internal-Key`): draft → evaluate → promote → channel
  pointer (`internal`/`beta`/`stable` + `rollout_percent`) → rollback.
- Migrations: `0015` registry, `0016` declarative seeds, `0027` remote
  preview seed. Releases are immutable; rollback = move channel pointer to a
  prior stable release (native release remains the floor).
- Client: `MotionCatalogRepository` (ETag, last-known-good cache),
  `VerifierReleaseRepository` (per-release cache, atomic `.tmp` rename
  writes, expected-checksum check, prefetch of catalog-referenced releases).
- Remote preview: `metadata_json.previewSequence` → `RemotePreviewSpec` →
  `RemoteFrontKeyframeSequence`/`RemoteSideKeyframeSequence` (decorative
  only; verifier never reads it).
- Telemetry: `MotionSessionArtifact` gzip → upload queue →
  `/internal/motion/sessions` + feedback labels; adaptation pipeline doc
  exists (`MOTION_ADAPTATION_PIPELINE.md`).

### 2.3 What a release looks like today

`verifier_releases.spec_json` is the flat `RemoteVerifierSpec` (or the
`native_v1`/`object_composition_v1` equivalents). There is **no package
envelope**: no asset manifest, no preview payload inside the release, no
test vectors, no per-asset checksums. Preview lives on the activity row
(`metadata_json`), model bytes live behind `/motion/models/:v/artifact`
keyed by model version rather than release.

---

## 3. Hard-coded motion-logic inventory

Classification:

- **A — blocks remote generality.** Must become data-driven for V1.
- **B — bundled fallback.** Stays compiled, wrapped as a package/adapter.
- **C — correctly generic.** Keep as-is.
- **D — working system, needs adapter** into the package abstraction.

| # | Location | What it does | Class |
|---|---|---|---|
| 1 | `motion_validators.dart` `createMotionValidator` | 23-case `switch` on `AiMotionActivity` | **B** — native fallback; remote never reaches it |
| 2 | `camera_verification_resolver.dart:177` | `MotionActivityType.fromBackendValue(spec.activityId)`; rejects `remote` | **A** — rejects genuinely new activities |
| 3 | `camera_verification_resolver.dart:184` + `CameraVerificationEligibility.movementDefinition` | camera view + instructions from compiled `motionActivityForType` | **A** — remote-only activity has no compiled definition |
| 4 | `ai_motion_models.dart` `AiMotionActivity` | proof-payload activity enum; unknown → `pushUps` fallback | **A** — mislabels remote proofs |
| 5 | `remote_verifier_spec.dart` | only single-landmark x/y threshold rules; no angles/ratios/sequences; no `sequence_match_v1` | **A** — DSL too weak for most motions |
| 6 | `remote_verifier_runtime.dart` | 3 runtimes only; no sequence or model engine | **A** (extend) |
| 7 | `rive_movement_preview.dart`, `side_rig_movement_sequences.dart`, `rive_movement_sequences.dart`, `preset_movement_demos.dart` | per-activity switch for bundled preview animation | **B** — remote `previewSequence` already overrides for catalog activities |
| 8 | `submit_proof_screen.dart:603` `previewSequenceFor` | catalog-driven preview lookup | **C** |
| 9 | `motion_activity.dart` `MotionActivityType` + `motion_activity_catalog.dart` | compiled activity metadata (labels, instructions, camera view, defaults) | **B** — bundled fallback + display seed |
| 10 | `MotionActivityType.remote` | display-only placeholder enum | **C** for display; **A** for proof identity (see #4) |
| 11 | `preset_movement_work_orders.dart` `workOrderForType` | compile-time taxonomy of factory families | **B/C** — useful migration map; seeds package specs |
| 12 | `factory_capabilities.dart` | inventory of reusable pose primitives (angles, ratios, air detect) | **C** — source list for remote DSL feature allowlist |
| 13 | `race_api.dart` `createCustomRace` | POSTs `CustomPoseVerifierSpec` inline on the race; bypasses release registry | **D** — Teach Nuvo adapter target |
| 14 | Motion V2 (`streaming_motion_v2`, `taught_motion_v2`, ONNX encoder) | learned-motion matcher; teach screen only | **D** — becomes `motion_v2` package engine |
| 15 | `object_composition_*` + `/motion/models/:v/artifact` + `motion_model_artifact_integrity.dart` | remote ONNX artifact w/ SHA-256, keyed by model version | **D** — generalize to package asset manifest |
| 16 | `motion_capabilities.dart` `MotionCapabilities.current()` | static capability set + dynamic object-dot caps | **C** — add new engine capabilities here |
| 17 | `motion_catalog*.dart` | bundled + remote merge, ETag, LKG cache | **C** |
| 18 | `verifier_release*.dart` | immutable release fetch/cache/checksum | **C** — extend to package envelope |
| 19 | `verifier_runtime.dart` `VerifierRuntime` + `VerifierRuntimeResolution` | adapter contract + eligibility→runtime wiring | **C** — the seam MotionRuntime builds on |
| 20 | Worker static catalog fallback + `motionSpec.ts` validator allowlist | engine allowlist: `native_v1, state_machine_v1, alternating_rep_v1, hold_v1, object_composition_v1` | **C** — add new engine ids here |
| 21 | `verificationSessions.ts` | session freeze of releaseId+checksum; spec hand-off | **C** |
| 22 | `verification_sessions` legacy path | races pre-registry may lack assignment — safe fallback exists | **C** |
| 23 | `localPresentationRace` / demo paths | compile-time demo races | **B** |
| 24 | `rollout_percent` channel pointer | rollout gating: `rollout_percent > 0` filter only — **no deterministic per-device bucketing** | **A** — staged rollout needs client bucketing |
| 25 | `inferSupportedMotionActivity` (title inference) | legacy races infer activity from title | **B** — keep for pre-registry races only |

---

## 4. Runtime primitives needed

### 4.1 MotionPackage envelope (new)

Extend the release payload with a `package` block (see
`motion_package_v1.md`): asset manifest (model/preview/vector files with
SHA-256 + size caps), package-level engine declaration, compat metadata.
Additive at the **release envelope level** — never inside
`RemoteVerifierSpec.spec`, because the Dart parser rejects unknown fields
and that strictness is a feature.

### 4.2 Uniform engine adapter → `VerifierRuntime`

`verifier_runtime.dart` already defines the runtime contract
(`update(frame)`, count/progress/confidence, `finish() → AiMotionResult`).
MotionRuntime = factory `MotionPackage → VerifierRuntime` over six adapters:

| Adapter | Engine | Status |
|---|---|---|
| Native | `native_v1` | Wraps compiled validators; bundled fallback for the 23 preset activities |
| Rules | `state_machine_v1`, `alternating_rep_v1`, `hold_v1` | Exists; needs derived-feature conditions to express most motions |
| Sequence | `sequence_match_v1` | **New** — ordered phase machine over allowlisted conditions (angles, ratios, airborne, landmark gates); covers burpees/jump-squats/multi-phase motions. `MultiPhaseSequenceTracker` + `AirborneStateTracker` already provide the mechanics |
| Learned | `taught_motion_v1` (Motion V2) | `StreamingMotionV2` behind the adapter; spec carries learned references. Key insight: the ONNX MotionBERT encoder is **generic and already bundled** — a remote motion package needs only the per-motion reference embeddings/spec, not a new model file |
| Object | `object_composition_v1` | Exists; folds into package asset manifest |
| (reserved) | custom_pose_sequence | Stays race-scoped via Teach Nuvo until/unless it becomes a package engine |

### 4.3 Derived-feature layer for the rules DSL

Current spec rules compare one landmark's x/y to a threshold. Most real
motions need: joint angles, segment ratios, distances, wrist/ankle-relative
positions, airborne state, temporal cadence. These primitives already exist
in `factory_capabilities.dart` + `motion_validators.dart` helpers — expose
them as an allowlisted `feature` field in spec v2 (bounded, no expressions).

### 4.4 Remote activity identity without compiled enums

- `RemoteMotionActivityDefinition` (exists partially via catalog `backendId`)
  must carry everything the proof flow needs: camera view, instructions,
  measurement type, default target, display metadata.
- `resolveCameraVerification` stops requiring `MotionActivityType`
  membership for release-backed activities.
- Proof payload activity becomes the server-owned activity id string, not
  the `AiMotionActivity` enum (or the enum grows a `remote` member whose
  `backendValue` is the race's `effectiveAiActivityType`). Eliminates the
  dangerous `→ pushUps` fallback for remote motions.

### 4.5 Package installer

`VerifierReleaseRepository` already does immutable, checksummed,
atomic-write caching per release. Package installer extends it:

- Download assets listed in manifest (R2 signed/public URLs), verify each
  SHA-256 (`MotionModelArtifactIntegrity` pattern already exists).
- Atomic activation: assets land in `packages/<releaseId>/`, manifest last.
- Pin retention: releases referenced by active races/sessions are never
  evicted. Other packages evictable LRU by config cap.
- Install happens at race open / session create — never inside the frame
  loop.

### 4.6 Capability delivery

`MotionCapabilities.current()` advertises engines/features. Package
required-capabilities gate both server assignment and client install.
Unknown required capability → package rejected before download (server)
and before activation (client). New engines land behind capability flags
(`sequence_match_v1`, `taught_motion_v1`, `onnx_runtime_v1`).

---

## 5. Migration plan

Existing releases/assignments/sessions keep working — the package block is
additive and old clients ignore unknown envelope keys **only if** they are
outside `spec_json.spec` (strict parser). Rollout ordering:

1. Phase 1 — envelope + installer, no new engines.
2. Phase 2 — remote identity unblocked (resolver + proof identity).
3. Phase 3 — engine adapters + `sequence_match_v1` + spec v2 features.
4. Phase 4 — bundled motion through runtime (native adapter proof).
5. Phase 5 — remote rules motion (unknown-activity acceptance test).
6. Phase 6 — Motion V2 as remote package (model-based acceptance test).
7. Phase 7 — rollout bucketing, kill switch, test-vector replay tooling.

Detail in `package_authoring.md` §lifecycle and §9 below.

## 6. Race V2 integration risk

- Race payload embeds `verifierSpec` JSON; release-bound packages keep the
  same shape and add the `package` envelope — old clients must ignore it.
  Verify `VerifierRelease.fromJson` tolerates unknown top-level keys
  (RemoteVerifierSpec is strict; the release envelope should not be).
- `follow_compatible_patch` races adopt new patch releases between sessions;
  package format must not change what "compatible patch" means
  (`compatibility_group` unchanged ⇒ adoptable).
- Legacy races without `verifier_release_id` keep the static/native path —
  no behavior change.
- Old clients: engine allowlist + minimum app build + required capabilities
  already reject unknown engines safely (`remote_activity_not_supported…`
  → today; `package_not_supported` → after V1). Keep rejection silent and
  non-destructive: fall back to pinned/native behavior, never guess a
  verifier.

## 7. Teach Nuvo integration plan

Current flow: capture 3 demos → `TaughtMotionV2Spec` (+ legacy
`CustomPoseVerifierSpec`) → race POSTs the **V1 geometric spec** inline →
proof runs `CustomPoseSequenceRuntime`. Motion V2 stays teach-screen-only.

Target flow: Teach produces a `taught_motion_v1` package payload
(V2 spec: references/embedding data, threshold, window config) → stored as
the race's inline verifier spec **or** published as a user-scoped release →
proof runs `StreamingMotionV2` via the package adapter. `NUVO_FORCE_V1`
becomes a teach-time engine choice, not a runtime branch. No App Store step:
the encoder is bundled; per-motion data rides in the package.

## 8. Performance risks

- No downloads in the frame loop — install at session start only (already
  true for spec fetch; keep for assets).
- Asset size caps per type (preview ~100KB, vectors ~1MB, model ~50MB
  configurable); total package cap enforced at publish.
- Rules DSL stays O(rules) per frame; `sequence_match_v1` bounded to ≤8
  phases, ≤12 conditions/phase.
- Model path runs the bundled encoder at ~15fps windowed — already proven
  on-device in Teach Nuvo.
- Cache: LRU eviction must skip race-pinned releases; pin set computed from
  active races.

## 9. Security risks (summary — see security.md)

- Packages are data, never executable. Strict parsers, field allowlists,
  bounded lists/thresholds — extend existing `RemoteVerifierSpec` discipline.
- Integrity: per-asset SHA-256 + package checksum over canonical manifest.
  Same releaseId + different bytes → reject and keep cache.
- ONNX artifacts are inert weights; runtime is bundled. Op-set safety is the
  runtime's job — verifier accepts only declared input/output schema.
- No per-user secrets in packages; INTERNAL_API_KEY gates authoring
  endpoints (already in place).

## 10. Implementation phases

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | This doc set | Docs reviewed |
| 1 | `MotionPackage` envelope parse/validate client+Worker; assets fetcher + integrity + atomic install | unit + cache tests |
| 2 | Remote activity identity end-to-end (resolver, eligibility, proof payload, catalog metadata) | unknown-activity rules release verifies on device |
| 3 | Spec v2 derived features + `sequence_match_v1` runtime + adapter table | engine unit tests + replay vectors |
| 4 | Squats (bundled) executes through MotionRuntime native adapter | parity vs current validator |
| 5 | Brand-new remote motion (e.g. "burpees_pro" activity+release published w/o app change) verifies | acceptance test |
| 6 | `taught_motion_v1` package: Teach-produced V2 spec runs in race proof | model-based acceptance test |
| 7 | Bucketing, kill switch, package metrics, test-vector replay harness | staged rollout + rollback drill |
