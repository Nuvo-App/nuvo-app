# Motion Runtime — Versioning & Compatibility

## 1. Version surfaces

| Surface | Field | Owner |
|---|---|---|
| Release identity | `verifier_releases.id` (immutable) | Worker |
| Release integrity | `checksum` (sha256 of canonical spec_json) | Worker publish |
| Engine contract | `spec_schema_version` + `engine_type` | Shared |
| Package format | `package.packageSchemaVersion` | Shared |
| Client floor | `minimum_app_build` | Worker |
| Feature gate | `required_capabilities[]` | Shared |
| Migration unit | `compatibility_group` | Worker |

## 2. Schema version ladder

| specSchemaVersion | Adds | Min app |
|---|---|---|
| 1 | `state_machine_v1`, `alternating_rep_v1`, `hold_v1` landmark-threshold rules | current builds |
| 2 | `feature` conditions (`derived_features_v2`), `sequence_match_v1`, `package` envelope, `activity` block, `taught_motion_v1` | new build |

Parser rule (both directions):

- Client at schema N reading spec N+1 → reject (`unsupported_schema`), keep
  cached release. Never silently coerce.
- Worker never emits spec N+1 to a race whose assigned client set can't
  parse it — capability + min-build checks at assignment time.

## 3. Compatibility matrix

| New release content | Old client behavior | Safe? |
|---|---|---|
| Tuned thresholds (schema 1) | Executes normally | Yes — the remote-release design today |
| `previewSequence` on activity | Parses or ignores; falls back to bundled preview | Yes (proven by migration 0027) |
| `package` block + schema-1 spec | Ignores `package` (envelope-level additive) | Yes if parser tolerant at envelope level — must verify `VerifierRelease.fromJson` ignores unknown siblings (RemoteVerifierSpec is strict; envelope must not be) |
| New engine id | `requiredCapabilities` + `minimum_app_build` reject at catalog/session | Yes — hidden/ineligible |
| Schema-2 spec | Rejects parse → unavailable, bundled fallback | Yes — never falls back to a *different* motion's verifier |

**Hard rule:** unknown activity/engine/spec → "not available" state. Never
map an unknown activity to a known verifier (the current
`remote_activity_not_supported_by_runtime` behavior is correct; it must
simply become unreachable for *installed* packages after identity
unblocking — see `architecture.md` §4.4).

## 4. Compatibility groups

`compatibility_group` defines `follow_compatible_patch` adoption:

- Same group + `change_class IN (patch, minor)` → adoptable between
  sessions.
- `major` or new group → requires explicit re-publish of the assignment
  (existing behavior; keeps race semantics stable mid-race).
- Package format changes that alter scoring semantics must use a new
  compatibility group. Cosmetic package changes (preview swap) keep it.

## 5. Release lifecycle states

```
draft → evaluated → stable (promoted to channel) → [rollback target]
  └→ disabled (terminal — never served again)
```

- Immutable content: `spec_json`, `package_json`, assets — once published,
  any change is a new release id (`<activity>-remote-<date>.<n>`).
- Status moves only forward except `stable → stable` via channel pointer
  (which is the rollback mechanism, not content mutation).
- `packageSchemaVersion` bumps are rare and additive-only (new asset types
  or fields). Removing/renaming a field = next schema version.

## 6. Client cache versioning

- Cache key = `releaseId`; contents expected-checksum-validated on read.
- Package dir = `packages/<releaseId>/`; activation atomic via manifest
  `.tmp` rename.
- App upgrade never auto-invalidates caches — capability gates decide
  usability per release, so a downgraded app simply rejects what it can't
  run while keeping usable packages.
- Retention: releases pinned by active races/sessions are never evicted;
  others LRU within the storage cap.

## 7. Race V2 / old payload compatibility

- Races created pre-registry (no `verifier_release_id`) keep the legacy
  native path — untouched.
- Race detail payloads with unknown `verifierSpec` engine →
  `unsupported_explicit_activity`/remote-ineligible → manual proof or
  unavailable state; no crash, no fallback-to-wrong-motion.
- `follow_compatible_patch` on a schema-1 group never receives a schema-2
  release (Worker gate), so old members never see an unparseable spec
  mid-race.
