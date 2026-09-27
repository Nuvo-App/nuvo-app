# Motion Runtime — Security Model

The package system deliberately widens what Cloudflare can push to phones.
This document defines what packages can and cannot do, and the layers that
keep a bad package from harming a user or a race.

## 1. Trust boundaries

| Boundary | Rule |
|---|---|
| Worker → phone | Packages are **data only**. No Dart, JS, native libs, or eval-able expressions — ever. |
| Parser | Strict: unknown fields rejected, allowlisted enums/features/operators, bounded lists and strings, clamped numbers. `RemoteVerifierSpec` already does this; every new parser follows the same discipline. |
| Assets | Inert payloads (JSON keyframes, embedding data, ONNX weights). Verified by SHA-256 against the manifest, size-capped, immutable. |
| Engine runtime | Engines interpret spec — they cannot produce effects outside {count, progress, confidence, guidance text}. No network, no storage outside the package dir, no reflection. |
| Frame loop | No downloads inside the live camera loop. Install/prefetch happens at race open and session create only. |

## 2. Integrity chain

```
release id + checksum (D1, immutable)
  └─ package manifest (checksumed, inside release spec_json)
       └─ per-asset sha256 + declared byte count
            └─ R2 object (content-addressed, immutable)
```

- Client verifies: release checksum on fetch, manifest sha256 consistency,
  each asset sha256 post-download, byte count match.
- Same releaseId with different bytes → reject; keep last-known-good.
- Atomic install: assets to `packages/<releaseId>/`, manifest written last
  via `.tmp` rename. A crash mid-install leaves the previous package live.
- No signature requirement in V1 — the trust chain is Worker-authenticated
  publishing + immutable checksums + capability gating. (Signing remains a
  V2 option if authoring broadens beyond the internal API.)

## 3. Threat model

| Threat | Mitigation |
|---|---|
| Malformed spec crashes/clamps the verifier | Strict parser + bounds; parse failure → release rejected → bundled/cached fallback. Parse is pure — no partial state. |
| Oversized asset exhausts storage | Per-type byte caps, total package cap, declared-vs-actual byte check, LRU eviction of unpinned packages. |
| Hot-swap of asset bytes under same id | R2 objects immutable; sha256 in manifest; mismatch rejects install. |
| Rollback tampering (replay old vulnerable release) | Releases immutable; only the channel pointer moves. Rollback targets must be `status='stable'` and pass validation on re-serve. |
| Malicious internal publish | `X-Internal-Key` (Worker secret) gates all authoring endpoints; promotion additionally requires assets/eval to exist. Audit via release history + session telemetry. |
| Spec references a landmark/feature not in allowlist | Parser rejects unknown names; engine drops unsatisfiable rules rather than guessing. |
| `taught_motion_v1` spec DoS (huge windows/embeddings) | Window/frame/embedding bounds in parser; encoder call rate-limited by window stride. |
| Preview payload attacks renderer | `preview_v1` is bounded keyframe JSON into the existing rig interpolator — no images/code; invalid → bundled fallback. |
| Privacy: pose data exfiltration | Packages can't request uploads; session telemetry ships only diagnostics (counts/timing/engine ids) — never landmarks/frames. No camera frames ever leave the device. |
| Capability confusion | Unknown required capability → reject server-side (never assigned) and client-side (never installed). Capabilities are a closed set maintained in `MotionCapabilities`. |

## 4. Failure isolation

- A package that throws/returns invalid results is contained by the
  `VerifierRuntime` contract — worst case it counts wrong for its own
  sessions; it cannot affect other engines.
- Session freeze pins release+checksum: a bad rollout only affects races
  assigned after promotion; rollback restores prior behavior for new
  sessions, and installed good packages remain usable offline.
- Runtime watchdog: frame-handler exceptions are caught at the adapter
  boundary; a throwing engine transitions the session to a failed state
  with `engine_error` telemetry rather than crashing the proof flow.

## 5. Kill switches

- Server: release `status='disabled'` → catalog drops it, sessions reject
  it; channel pointer removal stops new assignments instantly.
- Client: remote installs can be globally skipped via catalog header
  (`X-Motion-Remote: disabled`) — per `cloudflare_delivery.md` §7.
- Per-engine: each engine id can be removed from the server allowlist —
  releases referencing it validate-fail on next publish, and clients lacking
  the capability already reject it.

## 6. What packages can never do

- Execute arbitrary code or expressions.
- Read/write outside their package directory.
- Open sockets or fetch remote resources at verify time.
- Override activity identity to impersonate a different activity (spec
  `activityId` must equal release `activity_id`; session pins both).
- Change score/proof submission semantics — they only produce count +
  evidence signals; the Worker still owns race settlement.
