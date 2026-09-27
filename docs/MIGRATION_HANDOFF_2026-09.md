# Nuvo — Engineering Migration Handoff (2026-09-17)

> Written for: a new coding agent (GPT Astra / Codex) picking up this Flutter +
> Cloudflare Worker repo with no memory of the prior Claude Code session.
> Everything below is either (a) verified directly against the current repo
> tree/commits during this handoff, or (b) explicitly marked **UNVERIFIED /
> UNCERTAIN** where the prior session's docs describe it but this handoff did
> not re-read the underlying source in full. Do not treat an UNCERTAIN item as
> fact — open the named file and check before relying on it.

---

## 1. Executive Summary

Nuvo is a Flutter mobile app (iOS-first, Android second) backed by a single
Cloudflare Worker (Hono framework) + D1 (SQLite) database. Product loop: **set
a finish line → pull in your crew → submit proof → move the leaderboard.**
Core surfaces are five bottom-nav tabs (Arena / Crew("Pass") / Compete /
Move("Verify") / Profile) plus a race detail "leaderboard room," a proof
submission flow, and a from-camera "AI Motion Proof" rep-counting verifier.

State of the codebase as of commit `38e39f7` (HEAD, `main`, pushed to
`origin/main`, clean working tree except one untracked planning doc,
`docs/NUVO_MOTION_CONTROL_PLANE_PRD.md`, which this session did not author,
read, or touch):

- A real, previously-shipping **N+1 query waterfall** behind `GET /races` was
  found and fixed — this was the dominant root cause of "Compete/Verify load
  slowly while Arena loads instantly." Fixed and deployed to production.
- The client-side data-freshness contract (cache/revalidate/self-heal per
  doc `18-data-freshness-contract.md`) had two real gaps (cross-account stale
  request bug, asymmetric self-heal) which are now fixed uniformly across all
  four state controllers.
- A full design-system audit against an owner-supplied palette/button spec was
  done in stages; most violations are fixed. A few staged design items remain
  (see §17, §20).
- The most recent completed work (commit `38e39f7`) fixed: persistent
  bottom-nav/content overlap (structural `Scaffold` fix, not padding), a
  progress-marker bug in Arena's route visualization, an over-animated splash
  screen, and a missing "offline, but the app still works" state in Arena.
- **The one thing NOT done in this handoff session**: this document itself was
  the pending task; no application code was changed while producing it.

If you are picking this up cold, read in this order: this document, then
`docs/agents/00-start-here.md`, `08-codebase-navigation.md`,
`10-pitfalls-and-fixes.md`, `18-data-freshness-contract.md`, and
`19-social-platform-contract.md`. Those five are the highest-signal onboarding
docs and this handoff leans on them heavily (verified by direct reads this
session).

---

## 2. Current Repository State

- Branch: `main`. Remote: `https://github.com/Nuvo-App/nuvo-app.git`.
- Working tree: clean except one **untracked, unauthored-by-agent** file,
  `docs/NUVO_MOTION_CONTROL_PLANE_PRD.md` — do not assume its contents are
  agreed-upon direction; nobody in this session wrote or vetted it.
- Recent commit history (newest first, verified via `git log`):
  ```
  38e39f7 fix: eliminate shell nav overlap, route-shaped progress, offline-in-Arena
  66f67b3 fix: repair rendered UI composition across Arena/Compete/Verify/Crew/Profile
  b47fa71 design: close last two gaps from the design-guide failure-mode checklist
  dc3cbb1 fix: eliminate the N+1 request waterfall behind GET /races (Compete/Verify)
  1f62c78 fix: close two real gaps in the app-wide data freshness contract
  ```
  (Older history was **rebuilt from an orphan branch on 2026-08-31** — see
  §20/§24 — so `git log` beyond a handful of commits does not reflect the
  project's full real age; the pre-reset history is preserved on
  `backup/full-history-pre-checkpoint-20260831` and tag
  `checkpoint-backup-20260831` if ever needed.)
- Git workflow convention (per `docs/agents/10-pitfalls-and-fixes.md` §K): work
  directly on `main`, push directly to `main`, commit aggressively as
  milestones land. **No PR workflow currently in use.** This is a deliberate
  fast-iteration, pre-launch, zero-users choice — not necessarily permanent.
- `.gitignore` excludes `**/node_modules/`, `server/worker/build/`,
  `**/.dev.vars` (real secrets — commit only `.dev.vars.example`), model
  checkpoints under `tools/motion_v2/`.

---

## 3. High-Level System Architecture

```
lib/main.dart
  ProviderScope
    NuvoApp (MaterialApp.router)
      GoRouter + RouterNotifier (lib/features/auth/presentation/auth_gate.dart)
        auth/onboarding routes (unprotected: /splash, /welcome*, /auth/*, /invite/:token, /scan, /u/:id, /notifications)
        ShellRoute → MainShell: /arena /pass /compete /move /profile
        race/proof detail routes (/race/:id, /race/:id/settings, /race/:id/proof, ...)

server/worker/src/  (Cloudflare Worker, Hono)
  index.ts            entry, public endpoints (/health, /races/activities, /.well-known/*)
  routes/*.ts         one file per resource (races, arena, crew, profile, motion, invites, notifications, devices, ...)
  domain/*.ts         pure business rules (raceLifecycle, raceRanking, raceScoring, raceValidation, crewLifecycle, motionAnalysis, notifications, push)
  lib/*.ts            jwt, crypto, privacy, response helpers, validation, apple/google OAuth, resend (email), wellKnown, terms
  migrations/*.sql    0001..0014, D1 (SQLite), additive/ordered
```

The app starts at `/splash`. `AuthController` drives everything downstream:
its `AuthStatus` (`loading | authenticated | unauthenticated | offline`) is
watched by `RouterNotifier.redirect` (routing), `MainShell` (self-heal /
revalidate trigger), and every feature controller (auto-load-on-auth,
clear-on-sign-out).

---

## 4. Flutter Application Architecture

### State management
Riverpod (`flutter_riverpod`), specifically `StateNotifierProvider` +
`StateNotifier<XState>` per domain — **not** Bloc, not Redux, no
service-locator, no event-sourcing (explicitly rejected as overengineering
during this session's data-lifecycle work). Screens `ref.watch` for read,
`ref.read(xProvider.notifier).method()` for mutation. See §5 for the full
provider table (from `docs/agents/08-codebase-navigation.md`, verified).

### Navigation
`go_router` with one `GoRouter` built once via `routerProvider`
(`lib/app/router.dart`), a `ShellRoute` wrapping the five tab screens in
`MainShell`, and a single `RouterNotifier` (`ChangeNotifierProvider`,
`lib/features/auth/presentation/auth_gate.dart`) supplying `redirect`. Full
route table verified this session by reading `lib/app/router.dart` directly —
see §23 for the complete list. Key invariants documented in
`docs/NAVIGATION_MAP.md` (not re-read this session, but referenced repeatedly
by the pitfalls doc — **read it before touching routing**):
- one route per screen — aliases are `redirect:`, never a second `pageBuilder`
  (e.g. `/race/:id/edit` → redirects to `/race/:id/settings`)
- every "open a race" tap in the whole app goes to `/race/:id` — verify /
  invite / settings / log-progress are actions *on* that screen, never a
  separate list-tap destination
- after a create/join/finish flow use `go`; after opening something to look at
  use `push`
- routes needing `extra:` must have a null-safe fallback (it does not survive
  a cold deep link)

### Feature areas (verified via `find`/`ls`, `docs/agents/08`)
```
lib/features/
  splash/       launch + auth-restore hand-off
  auth/         session, token storage, sign-in UI, router guard
  onboarding/   post-signup profile setup, member-pass intro
  arena/        "what needs my attention now" — the control-case-good screen
  compete/      start/join races
  move/         "Verify" tab
  pass/         "Crew" tab (people, QR, requests)
  profile/      identity, pass, history, settings entry
  race_detail/  the leaderboard room for one race
  races/        domain+data+presentation for race lifecycle, composer, proof
                submission, AI Motion Proof, Teach Nuvo, and races/ai/* (the
                whole camera/pose/verifier stack)
  proof/        thin redirect shim: /proof/:id → /race/:id/proof
  social/       NuvoDestination, deep-link controller, invite/QR screens
  crew/         public profile screen (phase D of the social platform)
  notifications/ inbox + preferences screens
  shell/        MainShell (bottom-nav host + the one app-wide freshness trigger)
```

---

## 5. Data and State Architecture

Canonical pattern: **doc `18-data-freshness-contract.md`**, read in full this
session — this is the definitive source, not paraphrase. Every shared
server-backed domain gets one `XController extends StateNotifier<XState>`
with:
- `{loading, refreshing, error, hasData}` on its state
- `loadX({force})`: 5-minute hard cache (`_cacheLifetime`) + single-flight
  de-dup (`_loadInFlight`)
- `revalidate()`: 45-second stale window (`_staleWindow`) — a silent
  background refresh if data is older than that, on app-resume / tab-tap
- `clearX()`: nulls the load timestamp **and** `_loadInFlight` (a load that was
  in flight at sign-out must not resurrect after sign-in — see §6)
- mutation write-through: apply the server's response to local state directly,
  bump `_loadedAt`, call `onMutated` so sibling caches invalidate correctly
  (never a second, independent cache)
- honest four/five-state rendering: loading / refreshing / loaded-with-data /
  loaded-empty / error — never a blank screen with no explanation

Providers (verified table, `docs/agents/08-codebase-navigation.md` §4):

| Provider | File | Owns |
|---|---|---|
| `authControllerProvider` | `auth/presentation/auth_controller.dart` | session, `AuthUser`, onboarding flags, sign-in/out. `AuthStatus`: loading / authenticated / unauthenticated / **offline** |
| `routerNotifierProvider` | `auth/presentation/auth_gate.dart` | `RouterNotifier.redirect` |
| `raceControllerProvider` | `races/presentation/race_controller.dart` | races list; create/join/leave/archive/cancel/delete; submit proof; crew add/remove. Auto-loads on first read if authenticated; 5-min cache + in-flight de-dup |
| `arenaControllerProvider` | `arena/presentation/arena_controller.dart` | next-move snapshot. Same cache/clear pattern. `onSessionExpired` → `authController.sessionExpired()` |
| `firstRaceGuideProvider`, `_composerDraftProvider`, `recentMovementIdsProvider`, `learnedCustomMovementProvider`, `demoReplayProvider` | various | onboarding coach-marks / composer draft / Teach Nuvo recents |
| `CrewController`, `NotificationController` | social platform (doc 19) | crew connections, notification inbox — standard doc-18 notifiers |

`MainShell` (`lib/features/shell/presentation/main_shell.dart`) is the single
app-wide freshness trigger point: self-heal on mount, revalidate on
`didChangeAppLifecycleState(resumed)`, revalidate on tab-tap. As of the most
recent commit it gates the mount/resume triggers on
`ref.read(authControllerProvider).status == AuthStatus.authenticated`
(`_authIsUp`) but **not** the tap-triggered revalidate, which is a deliberate
manual-retry allowance regardless of auth status.

**Request-generation guard** (fix from this session, applied to
`RaceController`, `ArenaController`, `CrewController`, `NotificationController`):
an `int _generation` field is bumped by `clearX()`; each async fetch captures
the generation at start and checks it before applying its result. This
prevents a request that started *before* sign-out from writing stale/wrong-
account data into state *after* `clearX()` ran — the concrete cross-account
stale-data bug this session fixed.

---

## 6. Important State Bugs Already Fixed

1. **Cross-account stale-request bug.** Symptom: sign out of account A, sign
   into account B quickly — a slow in-flight request from A's session could
   resolve after B's sign-in and overwrite B's freshly-loaded state with A's
   data. Root cause: no way to distinguish "this fetch belongs to the current
   session" from "this fetch belongs to a session that no longer exists."
   Fix: the `_generation` counter guard described in §5, applied uniformly to
   all four controllers that fetch server-backed shared state.
2. **Asymmetric self-heal.** Symptom: Compete had its own local
   "stuck-if-empty, retry" check; Arena/Crew/Notifications did not, so only
   Compete could ever recover from a stuck-empty state on its own. Fix:
   centralized the recovery check into `MainShell._selfHealIfStuck()`, which
   checks all four controllers uniformly (`!hasData && error==null &&
   !loading` → kick `loadX(force:false)`) and removed the Compete-only
   duplicate.

---

## 7. Major Performance Bug: `/races` N+1 Waterfall (CRITICAL — now fixed)

This was the dominant, real, measured root cause of "Arena loads instantly but
Compete/Verify do not" — found only after the user forced an evidence-based
re-investigation using Arena as a control case (see §25 for why the first
report claiming "the architecture was already correct" was wrong).

**Before (the bug):** `server/worker/src/routes/races.ts`'s `GET /races`
handler built each race's response by calling a per-race `buildRaceResponse()`
sequentially inside a loop, and `buildRaceResponse()` itself issued **~7
separate D1 queries per race** (participants, moves/proofs, invites, final
standings, plus visibility-context lookups repeated per race). For a viewer
with N visible races this was **1 + N×7** D1 round-trips, awaited one race at
a time. Arena's equivalent endpoint (`routes/arena.ts`'s `buildRealSnapshot`)
did the opposite from the start: exactly **2 total** D1 queries (one race-list
query, one batched `WHERE race_id IN (...)` participants query) — which is
why Arena felt instant while Compete/Verify (both driven by `GET /races`)
crawled.

**After (the fix, `dc3cbb1`):** `races.ts` now has:
- `shapeRaceResponse()` — a pure function that shapes one race's API response
  from already-fetched sub-collections + a precomputed visibility context (no
  I/O inside this function).
- `loadViewerVisibilityContext(db, viewerUserId)` — computes the viewer's
  crew/blocked-user sets **once**, not once per race.
- `groupByRaceId<T>(rows, {cap})` — buckets a flat batched query's rows by
  `race_id`, optionally capping rows per group client-side (Worker-side JS) to
  replicate what used to be a per-race SQL `LIMIT`.
- `buildRaceResponsesBatch(db, viewerUserId, races)` — the actual fix: one
  batched `WHERE id IN (...)` query per sub-collection (participants,
  moves/proofs, invites, final_standings) across **all** races in the
  response, run together via `Promise.all`, then grouped and mapped through
  `shapeRaceResponse`.
- `buildRaceResponse()` is now a thin wrapper around `shapeRaceResponse` used
  only by the single-race code paths (detail/create/join/proof).
- The `GET /races` route calls `buildRaceResponsesBatch`, with a try/catch
  fallback to the old per-race sequential path **if the batch throws** — so
  one corrupt/edge-case race can't blank the entire list.

Result: `GET /races` query count for N races dropped from `1 + 7N` to a fixed
small constant (visibility context once + 4 batched IN-queries), independent
of N. Verified locally against `wrangler dev --local` + seeded D1 with real
HTTP requests and hand-minted JWTs (not just unit tests) before being deployed
to production. All 88 backend domain tests (`npm test`, `test/*.test.mjs`)
pass.

A pre-existing, unrelated schema quirk was hit while seeding local test data:
`race_invites.race_id` has a stale foreign key pointing at a legacy
`races_legacy` table rather than the current `races` table. Not touched or
fixed this session (out of scope) — noted here so a future agent isn't
surprised by an FK failure when seeding `race_invites` rows locally.

---

## 8. Current Cache/Freshness Model

- Hard cache lifetime: **5 minutes** per controller (`_cacheLifetime`).
- Stale-while-revalidate window: **45 seconds** (`_staleWindow`) — data older
  than this triggers a silent background `revalidate()` without blocking the
  UI, on: `MainShell` mount (if authenticated), app resume (if authenticated),
  tab tap (always, even if not authenticated — manual retry escape hatch).
- Single-flight de-dup via `_loadInFlight` per controller — critical gotcha:
  this field is **not** reset automatically on sign-out (a `StateNotifierProvider`
  is not recreated on sign-out, only its `state` is); every `clearX()` must
  explicitly null it, or a load that hung before sign-out silently blocks the
  next sign-in's reload forever (this is exactly bug A1 in
  `docs/agents/10-pitfalls-and-fixes.md` — already fixed, `commit 5df7064`,
  pre-existing before this session's work but load-bearing context for it).
- All three `*Api` clients (`RaceApi`, `AuthApi`, `ArenaApi`) have a hard 20s
  `.timeout()` mapping transport failures (`TimeoutException`,
  `SocketException`, `http.ClientException`) to `ApiException(408|0, ...)` —
  never an indefinite hang.
- `AuthStatus.offline`: stored credentials exist but the server was
  unreachable on restore. Tokens are **never** cleared in this state (only a
  definitive 401/404 from the server clears tokens). `RestoreResult` sealed
  class: `RestoreOk(AuthUser)` / `RestoreNoSession()` / `RestoreUnreachable()`.
  `retryRestore()` re-runs `_init()`.

---

## 9. Backend Architecture

Cloudflare Worker (Hono), D1 (SQLite), all under `server/worker/`.

```
server/worker/src/
  index.ts        entry point, public endpoints
  routes/         arena.ts auth.ts crew.ts devices.ts internal.ts invites.ts
                  motion.ts notifications.ts pass.ts profile.ts races.ts
                  reports.ts users.ts
  domain/         crewLifecycle.ts motionAnalysis.ts notifications.ts push.ts
                  raceActivities.ts raceLifecycle.ts raceMembership.ts
                  raceRanking.ts raceScoring.ts raceValidation.ts
  lib/            apple.ts google.ts crypto.ts demoArenaWorld.ts invites.ts
                  jwt.ts privacy.ts resend.ts response.ts terms.ts
                  validation.ts wellKnown.ts
  migrations/     0001..0014 (ordered, additive; some use CREATE TABLE IF NOT EXISTS)
  test/           8 *.test.mjs files, 88 tests total, run via `npm test`
```

Auth: JWT (`lib/jwt.ts`) — `JwtPayload {sub, iat, exp}`, HS256 HMAC via
`crypto.subtle`, `requireAuth` Hono middleware sets `c.get('userId')`.
`.dev.vars` (never committed) holds the local `JWT_SECRET` used to hand-mint
test tokens for local verification.

**UNVERIFIED / not re-read this session**: the internals of
`routes/motion.ts`, `pass.ts`, `profile.ts`, `crew.ts`, `notifications.ts`,
`invites.ts`, `users.ts`, `devices.ts`, `internal.ts`, `reports.ts`, and all of
`domain/raceLifecycle.ts`, `raceRanking.ts`, `raceScoring.ts`,
`raceValidation.ts`, `raceActivities.ts` beyond what's cited from
`14-preset-motion-creation.md` in §12. Open the file before making claims
about their exact behavior.

Deployment: `cd server/worker && npm run typecheck && npm test && npm run
deploy` (wrangler). API base:
`https://nuvo-api.getnuvoapp.workers.dev`
(override at build time with `--dart-define=NUVO_API_BASE_URL=...`). **The
Worker must be deployed by whoever makes the change** — a documented historical
failure (§25) shipped a client+source-level change that silently did nothing
in production for weeks because nobody redeployed the Worker.

---

## 10. Database/D1 Model

14 migrations (`0001_initial.sql` .. `0014_social_platform.sql`). Tables
reverse-engineered this session via `sqlite_master` during local N+1-fix
verification (not from reading every migration file in full — treat table
lists below as *observed*, not exhaustive):
`users`, `profiles`, `races` (current), `races_legacy` (superseded, but still
referenced by a stale FK from `race_invites.race_id` — §7), `race_members`,
`race_progress`, `move_logs`, `race_final_standings`, `race_invites`,
`crew_connections`, `blocked_users`. Migration `0013` adds `motion_sessions`
(telemetry, §12/§13). Migration `0014` adds the social-platform tables:
`invites`, `invite_uses`, `notifications`, `notification_preferences`,
`device_tokens` (per doc 19, §11 below — not independently re-verified against
the migration SQL text this session).

`crew_connections.status` ∈ `active | pending | declined | removed`, with
nullable `requested_by`/`updated_at` added in migration 0014; legacy rows with
no `requested_by` are treated as `active`.

---

## 11. Teach Nuvo / Motion Architecture

**UNCERTAIN — based on reading `docs/agents/13-motion-engine-v2.md` in full
this session, but the underlying Dart/Python source files themselves were
NOT opened.** Treat the file/API names below as what the doc claims exists;
verify against the actual files before depending on exact signatures.

Nuvo has two generations of "teach a movement, then recognize it live" tech:

- **V1** (`lib/features/races/ai/custom_pose/`) — hand-engineered pose
  features + similarity + thresholds + a large state machine. Documented as
  **not generalizing well**. Kept as a fallback/benchmark, reachable via
  `NUVO_DIAGNOSTICS` / `NUVO_FORCE_V1`. Do not tune its thresholds or add
  hand-crafted features "as V2 work" — that's an explicit anti-goal in the doc.
- **V2** — a pretrained motion encoder (MotionBERT-Lite family) + a thin
  few-shot matcher, three tiers:
  ```
  SERVER   big encoder, continual fine-tune, distillation teacher   [not built — post-launch]
    | distill + quantize
  ON DEVICE  small frozen encoder (MotionBERT-Lite ~16M), OTA-updated
    | (T,17,512) representation
  PER MOVEMENT  TaughtMotionV2 — prototypes + canonical trajectory + rest
                embedding, learned from 3 demos, ~KB. Name is metadata only,
                never used to verify.
  ```
  Per the doc, as of commit `3e79940`, **native V2 is the default Teach Nuvo
  engine** — no Python service, no dart-define flag required for normal use.
  ONNX Runtime Mobile is the chosen inference route (not Core ML) via the
  `onnxruntime` pub plugin + a bundled `assets/models/motion_v2_encoder.onnx`
  (81MB fp16). `flutter build ios --release --no-codesign` reportedly
  succeeds (182MB Runner.app); `flutter build apk --release` reportedly
  **fails** on an unrelated `sign_in_with_apple` 5.0.0 plugin issue
  (`Unresolved reference 'Registrar'`) — pre-existing per the doc, not
  something this session touched or fixed.
  Device inference latency is documented as **not yet measured** on a
  physical device as of the doc's last update.
  The Flutter-side capture UI is `TeachMovementScreen`
  (`/races/teach`, confirmed live in `lib/app/router.dart`), whose debug
  report ("Copy debug report") emits a raw pose-stream fixture consumed by
  `tools/motion_v2/fixtures/load.py` for offline research.

**Do not treat V1 and V2 as interchangeable or "the same feature done twice."**
V1 is the deprecated fallback; V2 is the shipping direction. A future agent
should re-verify the "native V2 is default" claim against
`lib/features/races/ai/motion_v2/` and the router before changing anything
here, since this handoff did not open those files directly.

---

## 12. Preset Movement/Verification System

This is a **separate system from Teach Nuvo/Motion V2** — read in full this
session from `docs/agents/14-preset-motion-creation.md` (high confidence,
verbatim contract doc for this area).

A **preset** (pushups, squats, running-in-place, etc.) is a deterministic,
hand-written biomechanics verifier — a frame-count state machine, **no ML
inference on the hot path**. Explicitly selected by the user in the race
composer, distinct from Teach Nuvo's learned-movement path. Never wire a
preset through V2/custom-pose, and never touch V2/custom-pose to fix a preset.

**Protected known-good presets — do not modify their core logic casually:**
Pushups (`PushupsValidator`), Jumping Jacks (`ConfigurableRepValidator` +
`jumpingJackRepDefinition`), Plank (`PlankHoldValidator`). Changing the shared
base classes (`_BaseValidator`, `RepCounterStateMachine`,
`ConfigurableRepValidator`) requires proving these three are unaffected
(run their tests before/after).

**Verifier architecture patterns (pick per-motion, don't force one):**
- **Rep state machine** (`RepCounterStateMachine` or a dedicated
  `_BaseValidator` subclass) — squats, pushups, calf raises, arm raises.
  `READY → MOVEMENT → REQUIRED RANGE/DEPTH → RETURN → +1 → RESET`.
- **Cadence** (`CadenceDetector` + `CadenceMovementDefinition`) — running,
  treadmill, walking, marching, step-ups, butt kicks, mountain climbers. A
  count fires only when the newly-confirmed side **differs** from the last
  confirmed side (no "return to neutral" phase needed). The signal function
  must be a **left-vs-right relative difference**, never an absolute
  landmark position — this is the single most important lesson in this doc,
  learned from two real production bugs (§13).
- **Multi-phase sequence** (`MultiPhaseSequenceValidator`) — burpees, jump
  squats, lunge jumps (≥3 ordered phases).
  **Duration/hold** (`PlankHoldValidator` + `HoldTimerStateMachine`) — plank
  only; count is seconds, not reps.

**Mandatory registration checklist** — a preset must exist at *every* layer
or it's the exact class of bug this doc exists to prevent (16-row checklist in
the doc; the two most consequential rows: **#13 the backend allowlist**
`server/worker/src/domain/raceActivities.ts` `RACE_ACTIVITY_CATALOG` +
`normalizeActivityId`, and **#14 — deploying the Worker yourself**. A
`raceActivities.ts` change does nothing in production until deployed; this is
documented as the single most common failure mode for this feature area, with
a real historical incident: 10 preset activities shipped client+source but
the Worker was never redeployed, so production rejected `POST /races` with
`"Choose a supported activity."` for weeks.) `test/preset_registration_contract_test.dart`
audits every catalog entry against every layer and prints a
`PRESET ROUTE AUDIT`.

**Fast-rep / double-count rules:** recognition never waits for UI (frame loop
calls `_runtime.update(frame)` unconditionally, no animation gating); any
per-rep cooldown must be `< phaseStableFrames` (a documented historical bug —
`PushupsValidator`'s cooldown of 3 vs. stableFrames of 2 swallowed fast
back-to-back reps, 5 counted as 3); state machines count frames, never
wall-clock (except the plank hold timer, by design).

**Body-relative measurement, never raw pixels:** normalize against hip width,
torso height, shoulder width, joint angles. Two real, documented cadence bugs:
(1) an original knee-height check was tuned to synthetic poses and never
armed on a real phone camera — fixed by reading the **difference** in height
between the two knees rather than either knee's absolute height; (2) a real
37-second treadmill session counted 2 of ~77 reps because the athlete was
small in frame (collapsing a hip-width-normalized threshold) and the real
motion showed up almost entirely as horizontal knee swing, not vertical — the
signal now sums a centered `Δx` and raw `Δy` of the knee pair, normalized by
torso height instead of hip width. Regression fixture:
`test/fixtures/treadmill_running_session_ms_64c7b6ee.json`.

**A preset is not "done" when its unit test passes** — it's done only when a
race with it can be created (no "Choose a supported activity"), loaded, and
verified end to end **on deployed production**, confirmed via
`curl https://nuvo-api.getnuvoapp.workers.dev/races/activities`.

**Motion Session telemetry** (§J2 of the doc): every preset/custom
verification attempt is recorded into a `MotionSessionArtifact`
(`lib/features/races/ai/motion_session/`) — the full landmark stream +
decision trace + result, uploaded best-effort via `MotionSessionUploadQueue`
to `POST /motion-sessions` → R2 + a D1 index row (migration 0013). Retrieval
for debugging is via `/internal/*` endpoints gated on an `X-Internal-Key`
header matching the `INTERNAL_API_KEY` wrangler secret — this lets a support
person or coding agent pull a user's actual session artifact without needing
a phone log.

---

## 13. Treadmill/Virtual Distance System

Two related but distinct mechanisms, both read from `14-preset-motion-creation.md`
this session (doc-level only — `virtual_distance_estimator.dart`,
`cadence_detector.dart`, and `airborne_state_tracker.dart` themselves were
**not opened**; treat specifics below as doc claims to verify before relying
on exact numbers):

- **Continuation** (`ContinuationProgress`,
  `lib/features/races/domain/motion_progress_presentation.dart`): a
  verification session is one more contribution to the *same* cumulative race
  progress. `sessionTarget = raceTarget − startingRaceProgress` (what the
  verifier aims at, always starting the session count from 0);
  `displayedProgress = startingRaceProgress + sessionContribution` (what the
  athlete sees); only `sessionContribution` is ever persisted to the server —
  never the whole displayed total. This makes every `createMotionValidator(...)`
  call get continuation "for free" since it always opens at `currentValue==0`.
- **Distance presentation** (`DistancePresentationPolicy`, same file area):
  virtual distance is explicitly treated as an *estimate*, and the UI must
  never imply metre-level precision. Milestone-burst cadence is chosen purely
  from the race's target distance: ≤25m → burst every 5m; ≤100m → every 10m;
  <400m → every 25m; ≥400m (mile-scale) → **no burst at all**, show
  distance+pace+intensity instead. A "burst" always labels the checkpoint
  distance reached ("15m"), never a delta ("+1m").
- Cadence-family presets (running in place, treadmill running, walking,
  marching, step-ups, butt kicks, mountain climbers) all convert a
  left/right alternation signal into distance/reps via the same
  `CadenceDetector`/`AlternatingGaitSignal` machinery described in §12 — the
  treadmill-specific real-session bug and its fix are the running example
  documented there.

---

## 14. Design System — Current State

Verified this session by direct file inspection during the earlier design-audit
rounds (see §24 for exact diffs), plus `docs/agents/08-codebase-navigation.md`'s
theme file map (verified):

```
lib/core/theme/
  app_colors.dart       NuvoColors (raw + semantic tokens), NuvoColorRole,
                         NuvoSemanticColors ThemeExtension
  app_text_styles.dart  AppTextStyles.* — Manrope scale
  app_geometry.dart     NuvoRadii, NuvoSpacing, NuvoBorders (hero vs quiet, etc.)
  app_shadows.dart      AppShadows.hard{Small,Medium,Large}, soft*
  nuvo_tokens.dart      NuvoTokens.* — grays, consolidated aliases (newer code)
  nuvo_responsive.dart  context.rs(px), TextStyle.scaled(context), width buckets,
                         NuvoTextScaleScope (app-wide TextScaler clamp [0.85, 1.30])
  app_theme.dart        Material 3 ThemeData, component themes, semantic ext wiring
lib/core/widgets/       ~26 shared widgets (nuvo_button, nuvo_empty_state,
                         nuvo_error_state, nuvo_podium, nuvo_avatar,
                         nuvo_race_components, nuvo_board_components, bottom_nav, ...)
```

**Owner-supplied palette** (pasted verbatim twice this session, drove the
multi-round design audit — treat as current source of truth over anything
older in the docs unless a doc has been updated since):
Green `#2ecc40` / shadow `#008a43`; Red `#e72025` / shadow `#8b1917`; Blue
`#1264ff` / shadow `#003d71`; Tan `#ead0bb` / shadow `#e0b48c`; Yellow
`#fcca1d` / shadow `#c49e00`; Orange `#f69304` / shadow `#f47603`. Note this
differs from the semantic values recorded as "current" in
`docs/agents/10-pitfalls-and-fixes.md` §F1 (green `#3BC448`, red `#DC2529`,
etc., from an *earlier* design pass) — **the hexcodes above are the newer,
owner-confirmed spec this session worked against; verify `app_colors.dart`'s
actual current values before assuming either doc is up to date.**

**Button family spec** (verbatim, owner's words): "3d buttons should be
formatted exactly like the above example with the main color on top and a
3px outline with the shadow color around it, with a shadow underneath
slightly offset. The 2d buttons should be the same except no shadow, just an
outline."

---

## 15. New UI/Color Design Direction

The design work this session ran in explicit stages against the palette in
§14:
1. A written **audit** of every screen against the palette/button rules
   (planning only, no implementation).
2. A **staged remediation plan** (`docs/design/SCREEN_REMEDIATION_PLAN.md`,
   `docs/design/DESIGN_GUIDE_AUDIT_2026-09.md`,
   `docs/design/DESIGN_SYSTEM_GOVERNANCE.md` — created this session, not
   independently re-read for this handoff beyond knowing they exist and were
   the planning artifacts).
3. **Two rounds of screenshot-driven visual QA** against the owner's real
   phone screenshots (not simulator renders), each fixing concrete,
   itemized, user-named defects rather than doing another abstract token
   audit. Round 2 (most recent, commit `38e39f7`) is the last completed
   design work — see §24 for its full change list.

Direction going forward should keep following the pattern that worked this
session: **screenshot-driven, itemized, geometry-tested fixes** over
speculative "improve the design system" passes — the user explicitly rejected
citing documentation/architecture-on-paper as evidence of a fix (§25); the
same standard applies to visual work — a real screenshot beats a described
intention every time.

---

## 16. Desired Design-System Architecture

Not separately re-specified beyond what's in §14/§15's palette + button
rules and the borders-hierarchy rule already enforced in code
(`NuvoBorders.hero` reserved for the single primary focal card per screen;
`NuvoBorders.quiet` for secondary/list containers — this distinction was a
real bug found and fixed this session: 11+ places were using `hero`-weight
borders on containers that should have been visually quieter, flattening the
screen's depth hierarchy). No further "target-state" architecture document
exists that this handoff could verify; treat the existing token files
(§14) plus the borders-hierarchy rule as the whole of the current desired
architecture until a more formal spec is written.

---

## 17. Current UI Priorities

Directly from the most recent completed round's 6-part spec (verbatim
excerpts preserved because they carry real constraints, not just goals):

1. ~~Eliminate nav overlap~~ — **DONE**, via a `MainShell` `Scaffold`
   refactor (§19), not more bottom padding.
2. ~~Improve first-viewport density~~ — **DONE** on Arena (§19).
3. ~~Replace Arena's progress bar with a real route~~ — **DONE** (§19).
4. ~~Simplify the splash loading screen~~ — **DONE** (§19).
5. ~~Move connection-failure UI from Splash into Arena~~ — **DONE** (§19).
6. General polish (44×44 touch targets, no raw error strings surfaced to
   users, etc.) — **DONE** where itemized in the round-2 screenshots; **not**
   exhaustively swept across every screen — a future agent should treat "does
   every tap target meet 44×44" as still an open sweep, not a closed one.

Remaining, not yet started as of this handoff:
- Phase 4 per-screen focal-point passes referenced in an earlier plan
  (onboarding, Race Composer polish, Move/Verify, Edit Profile) — see the
  stale plan captured in §28.
- Physical-device confirmation of every geometry-tested fix in §19 — this
  session explicitly could not install/use a simulator and relied on
  fixed-size widget tests + geometry assertions instead. **A real device
  pass is still owed.**

---

## 18. Important Product Terminology

From `docs/agents/00-start-here.md` and `10-pitfalls-and-fixes.md` §M
(verified, both read in full this session): use **race, crew, proof,
progress, leaderboard, start line, finish line, submit proof, member pass,
AI Motion Proof, arena**. Never use: challenge, event, journey, unlock,
discover, "coming soon," betting, payout, Firebase (as user-facing copy).
Screen ownership is fixed and must not be blurred to make a local UI problem
disappear: Arena = "what needs my attention now," Compete = start/join a
race, Crew = people/invitations, Profile = identity/pass/history/settings,
Race Detail = one race's leaderboard room, Submit Proof = choose/complete
proof, AI Motion Proof = **live camera verification only**.

---

## 19. Critical Product Rules/Invariants

- **Never fake a performance fix or fabricate data.** (Explicit standing
  instruction from the systems-architect mandate this session — §25.)
- **Never label a proof as verified before the backend/runtime actually says
  so.** An unrecognized/unmapped proof status defaults to `needsReview`, never
  `accepted` (a real bug fixed pre-this-session, `RaceProof.fromJson`).
- **Never dereference `authState.user!` on a path reachable while
  `AuthStatus.offline`** — `AuthState.user` is null in that state. This
  session's router change (`auth_gate.dart`) places the `offline` branch
  *before* the `authenticated` branch's `final user = authState.user!;` line
  specifically to make that line structurally unreachable while offline —
  covered by `test/router_offline_routing_test.dart`.
- **Never log a user out solely because the server is unreachable.** Only a
  definitive 401/404 clears tokens; timeouts/5xx/offline → `AuthStatus.offline`,
  tokens kept, `retryRestore()` is the recovery path.
- **`MainShell` must not be starved of its one entry point (Arena) while
  offline** — any other protected route bounces to `/arena`, `/splash` is left
  alone (not force-redirected).
- **One route per screen; every "open a race" tap → `/race/:id`.**
- **Do not touch pose detection / thresholds / camera bridge / native files
  casually** — these are explicitly no-touch without named, scoped approval
  (§20).
- **A preset is not done until verified on deployed production**, not just
  passing local tests (§12).
- **Do not overengineer**: no Redux/Bloc/service-locator/event-sourcing for
  state; `StateNotifier` + the doc-18 contract is the whole pattern.

---

## 20. Known Technical Debt

- `docs/design/*` planning docs created this session were not independently
  re-verified against the current code state for this handoff — treat them
  as historical planning artifacts, not necessarily current truth.
- No-touch files list (`docs/agents/10-pitfalls-and-fixes.md` §M, verified):
  `auth_*` (api/repo/controller/gate/token store), `ai_motion_proof_screen.dart`,
  `motion_validators.dart`, `pose_detector_service.dart`,
  `camera_image_converter.dart`, iOS native files, `pubspec.yaml`/`pubspec.lock`,
  `server/worker/` (as a whole, treated as a separately-scoped release surface).
  "Make it work" does not authorize bypassing these — changes here need
  explicit, named, scoped approval.
- Motion V2 device-inference latency is documented as **never measured on a
  physical device** (§11) — a real gap before this can be trusted as
  production-ready.
- `flutter build apk --release` reportedly fails on an unrelated
  `sign_in_with_apple` 5.0.0 plugin issue (`Unresolved reference 'Registrar'`)
  per the Motion V2 doc — **not verified independently this session**, and not
  fixed; a future agent should re-confirm this is still true before assuming
  Android release builds are blocked.
- `race_invites.race_id`'s stale FK to the legacy `races_legacy` table (§7) —
  pre-existing, unrelated to the N+1 fix, not fixed.
- Social platform (doc 19) phase F (push notifications) is **scaffolded but
  dormant** — needs Firebase config (`GoogleService-Info.plist`,
  `google-services.json`, APNs `.p8`) and two Worker secrets
  (`FCM_SERVICE_ACCOUNT`, `FCM_PROJECT_ID`) that only the owner can provide.
- Social platform phase G (universal links) needs an Apple Developer portal
  "Associated Domains" capability toggle and an Android release keystore
  SHA-256 fingerprint in `assetlinks.json` — neither doable from code.
- Apple sign-in cannot complete end-to-end — needs `APPLE_BUNDLE_ID` +
  Services ID + nonce config on the Worker side that the owner has not set up.
  The button is kept and made visually consistent with Google/email; the flow
  itself is not fake, just not configured.
- A standing baseline of **pre-existing test failures** exists (~37 in the
  focused UI suite per `docs/agents/10-pitfalls-and-fixes.md` §I2, mostly
  ML-threshold tests like `airborne_state_tracker_test.dart` that are
  documented as out of scope). Judge any future change by **new** failures
  only, via the baseline-diff technique in that doc.

---

## 21. Testing Infrastructure

Flutter:
```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --concurrency=4 test/*.dart test/arena/    # NEVER bare `flutter test`
```
**Never run `flutter test` bare** — `test/motion_qa/` contains long-run
harnesses (hundreds of thousands of search iterations, ~1GB of artifacts) that
a bare invocation will pick up and that will not finish in reasonable time;
`--exclude-tags` does not help since they aren't tagged. Only run
`test/motion_qa/` when that is the explicit task.

Worker:
```bash
cd server/worker && npm run typecheck && npm test
```
`npm test` does `rm -rf .tmp-test-dist && tsc ... && node --test test/*.test.mjs`
— 88 tests across 8 files, all passing as of this handoff.

Regression-baseline technique (from `docs/agents/10-pitfalls-and-fixes.md`
§I2, used repeatedly this session via `git worktree add`): capture the failing-
test-name set on the untouched tree, capture it again after a change, diff —
only new failures matter.

Widget-testing gotchas discovered/fixed this session (all now embedded as
comments in the relevant test files, §24):
- `precacheImage()`'s real asset decoding needs `tester.runAsync()` — a fake-
  clock `pump(duration)` loop alone never lets it complete.
- Semantics assertions are more reliable read directly off
  `tester.widgetList<Semantics>(...).properties.label` than via
  `find.bySemanticsLabel`, when ancestor `Semantics` widgets merge nodes.
- Building a `GoRouter` inside a `Consumer` that rebuilds on provider changes
  throws `LateError` — build it once via a plain `ProviderContainer` +
  `UncontrolledProviderScope` outside the widget tree instead.
- A fake repo method that resolves via `async => value` (no real delay)
  resolves on the very next microtask — too fast to ever observe an
  intermediate "loading" state in a test. Use an uncompleted
  `Completer<T>().future` to hold state open deliberately.

---

## 22. Deployment/Development Workflow

```bash
flutter run --dart-define=NUVO_API_BASE_URL=...   # point at a specific Worker
cd server/worker && npm test && npm run deploy     # you deploy it yourself — see §7/§12
```
Never put secrets in Dart source or commit `.dev.vars`. Local Worker
verification uses `wrangler dev --local` + `wrangler d1 execute --local` /
`wrangler d1 migrations apply --local`, with hand-minted JWTs signed via the
local `.dev.vars`' `JWT_SECRET` (this session's technique for proving the N+1
fix against real HTTP + real D1, not just unit tests).

---

## 23. Important File Map

The full route table, verified this session by reading `lib/app/router.dart`
directly:

| Path | Screen | Notes |
|---|---|---|
| `/splash` | `SplashScreen` | entry, no transition |
| `/welcome`, `/welcome/intro` | `WelcomeAuthScreen`, `WelcomeRaceBuilderScreen` | |
| `/invite/:token` | `InviteScreen` | universal-link/QR landing, works logged out |
| `/scan` | `QrScanScreen` | |
| `/u/:id` | `PublicProfileScreen` | |
| `/notifications`, `/settings/notifications` | `NotificationsScreen`, `NotificationPrefsScreen` | |
| `/auth/email`, `/auth/verify` | `EmailStartScreen`, `EmailVerifyScreen` | |
| `/onboarding/profile`, `/onboarding/member-pass` | `OnboardingScreen`, `OnboardingMemberPassScreen` | |
| `/arena` `/pass` `/compete` `/move` `/profile` | tab screens | inside `ShellRoute` → `MainShell`, `NoTransitionPage` |
| `/races/new`, `/races/join`, `/races/teach` | composer, join, Teach Nuvo | |
| `/internal/teach-movement` | — | legacy `redirect:` to `/races/teach` |
| `/race/:id` | `RaceDetailScreen` | the leaderboard room |
| `/race/:id/settings` | `RaceSettingsScreen` | |
| `/race/:id/edit` | — | legacy `redirect:` to `/race/:id/settings` |
| `/race/:id/invite` | `InviteCrewScreen` | |
| `/race/:id/proof` | `SubmitProofScreen` | |
| `/race/:id/proof/ai-motion` | `AiMotionProofScreen` | |
| `/race/:id/board-moved` | `BoardMovedScreen` (celebration) | has a null-safe `extra:` fallback |
| `/race/:id/proofs/:proofId` | `ProofReviewScreen` | |
| `/proof/:id` | `ProofScreen` | thin redirect shim → `/race/:id/proof` |
| `/profile/edit` | `EditProfileScreen` | |

Directory map (verified, `docs/agents/08-codebase-navigation.md` + direct
`ls`): see §4 for feature areas and §9 for the Worker tree.

The **4-layer rule** for any feature (verified, same doc): `presentation/`
(screens, screen-local widgets, `*Controller`) → `domain/` (pure functions,
no `BuildContext`/`http`) → `data/` (`*Api` HTTP+JSON, `*Repository`
token+mapping) → `core/` (cross-feature theme/widgets/nav helpers). Flow is
one direction only: `presentation → domain + data`, `data → core`. A screen
never calls an `*Api` directly.

File-naming glossary (verified): a one-line `*_screen.dart` is a re-export
shim — the real screen is `*_screen_fixed.dart` (e.g. `arena_screen.dart` →
`arena_screen_fixed.dart`, `compete_screen.dart` → `compete_screen_fixed.dart`).
Edit the `_fixed` file. `*_io.dart`/`*_web.dart` are conditional-import
platform splits (`ai_motion_proof_screen.dart` picks one at compile time).

---

## 24. Recent Change History

In chronological order, all on `main`, all pushed:

1. **`1f62c78`** — closed the two client-side data-freshness gaps (§6):
   cross-account stale-request guard (`_generation` counter) and unified
   self-heal in `MainShell`.
2. **`dc3cbb1`** — the `GET /races` N+1 fix (§7): `shapeRaceResponse`,
   `loadViewerVisibilityContext`, `groupByRaceId`, `buildRaceResponsesBatch` in
   `server/worker/src/routes/races.ts`. Deployed to production.
3. **`b47fa71`** — closed the last two gaps from a design-guide failure-mode
   checklist (specific items not independently re-verified for this handoff
   beyond the commit existing).
4. **`66f67b3`** — round-1 screenshot-driven UI fixes across
   Arena/Compete/Verify/Crew/Profile:
   - `app_text_styles.dart`: `sectionTitle` reverted 17px→14px after breaking
     an Arena fold-margin test (see the sizing-formula postmortem below).
   - `nuvo_race_components.dart`: `RaceWaitingSummary`/`RaceFinishedSummary`/
     `RaceQuickStart` borders `hero`→`quiet`; `RaceRow.minHeight` 64→58.
   - `compete_screen_fixed.dart`: 4 `hero`→`quiet` border fixes.
   - `move_screen.dart`: 3 border fixes; `_RecentProofRow` gained a
     `warning`-colored pending-status branch.
   - `pass_screen.dart`: removed a colored-stripe section label; softened
     borders.
   - `member_pass_card.dart`: compact dark variant rewritten to a horizontal
     Row layout (64px QR + identity beside it).
   - `profile_screen.dart`: "Moves"/"Avg" stats recolored to `NuvoColors.navy`
     (were arbitrarily colored); softened borders.
5. **`38e39f7`** (HEAD) — round-2 fixes, the most recent completed work:
   - **`main_shell.dart`**: unified to one unconditional
     `Scaffold(extendBody: false, body: SafeArea(bottom:false, child:
     widget.child), bottomNavigationBar: navigation)` for every tab — the
     previous Arena-special `Stack`-based layout is gone. Added `_authIsUp`
     gate on the self-heal/resume triggers (not the tap trigger).
   - **`bottom_nav.dart`**: `NuvoBottomNav.bottomPadding(context)` shrunk from
     the dock's full ~130px floating-overlay footprint to a small cosmetic gap
     (`_contentGap * 2`) — now safe because the Scaffold, not manual padding,
     structurally reserves the nav's height.
   - **`auth_gate.dart`**: added an `offline` branch to `RouterNotifier.redirect`,
     placed *before* the `authenticated` branch, per the null-safety rule in §19.
   - **`splash_screen.dart`**: removed the `_ambientController` (3.6s repeating
     animated 18×31 dot grid, deleted ~35 lines of sin-wave pulse math),
     removed `_showOfflineRetry`/`_OfflineRetry` entirely — offline now hands
     off straight to `/arena`, which owns the connection-failure UI itself.
   - **`arena_screen_fixed.dart`**: `_RaceProgressPainter` rewritten with a
     real `_routePath(Size)` (two cubic Beziers) — the completed portion is
     drawn via `PathMetric.extractPath(0, coveredLength)` and the marker is
     positioned via `metric.getTangentForOffset(coveredLength)` (previously
     hardcoded to the start point — a real, previously-unnoticed bug: the
     marker never moved regardless of actual progress). Added an
     `isOffline`/`retryConnection`-driven `NuvoOfflineBanner` (cached-data
     path) and a full `NuvoErrorState(title:'No connection', ...)` branch
     (no-cached-data path).
   - **`nuvo_error_state.dart`**: extended with optional `title`/`icon`/
     `retryLabel`; added `NuvoOfflineBanner`.
   - New tests: `test/main_shell_layout_test.dart`,
     `test/arena/race_progress_route_test.dart`,
     `test/auth_controller_offline_test.dart`,
     `test/router_offline_routing_test.dart`,
     `test/splash_screen_offline_test.dart`,
     `test/arena/arena_offline_state_test.dart` — 27 new tests, all passing
     (verified by direct read of all 6 files this session).

---

## 25. What Has Been Tried and Did Not Solve the Full Problem

- **Citing `docs/agents/18-data-freshness-contract.md` as proof the
  architecture was already correct**, after the first round of data-lifecycle
  fixes. The user explicitly and forcefully rejected this: "A document
  describing the intended architecture does NOT prove the implementation
  behaves that way... DOCUMENTATION = intended behavior. RUNNING CODE +
  TRACES + TESTS = actual behavior." The real bug (the `GET /races` N+1
  waterfall, §7) was only found after switching to using Arena as a working
  control case and tracing actual query counts, not by re-reading the
  architecture doc harder.
- **Reducing Arena's hero-card sizing constants** (`desired`, `contentFloor`,
  the `usableViewport` cap) to shrink dead space directly — broke the
  proportional-sizing test across two device widths. The real fix was
  changing `_NextMoveHero`'s `mainAxisAlignment` from a size-dependent
  `spaceBetween`/`center` to a fixed `MainAxisAlignment.start` + small gap —
  a layout-mechanism fix, not a numeric-tuning one.
- **Bumping the shared `sectionTitle` text style itself** from 14→17px to fix
  Arena's all-caps tracked labels "once, so it cascades everywhere" — broke
  the same fold-margin test because it cascaded into three Arena headings at
  once. Reverted; fixed locally at the one call site instead
  (`titleMedium.copyWith(fontWeight: w700)`, same 17px size, non-uppercase).
- **Removing icons from Arena's "New"/"Join" buttons** to fix a 0.25px
  overflow — broke a smoke test that (correctly) still expected the icons to
  exist alongside new labels. Fixed via flex-ratio rebalancing instead of
  removing content.
- **Solving nav overlap by increasing `NuvoBottomNav.bottomPadding`** — this
  was explicitly rejected by the user as the wrong fix *before* it was even
  attempted this round ("This is caused by shell composition, not
  insufficient final scroll padding... Do not solve it by adding more
  `NuvoBottomNav.bottomPadding`"), because it's a convention every screen has
  to independently guess right, not a structural guarantee. The actual fix
  was making the `Scaffold` itself reserve the nav's height (§24 point 5).
- **An ancestor-state-lookup widget** (`context.findAncestorStateOfType`)
  briefly introduced while simplifying the splash screen — self-caught as an
  anti-pattern mid-session and reverted to a plain inline conditional in
  `build()`.

---

## 26. Current Product Behavior That Has Been Verified

- `GET /races` now issues a small constant number of D1 queries regardless of
  race count, verified against a real local `wrangler dev --local` + seeded D1
  + real HTTP requests (not just unit tests), and the fix is live in
  production.
- All 88 backend domain tests pass (`server/worker`, `npm test`).
- 27 new Flutter tests covering the round-2 UI work pass, plus the
  pre-existing suite shows no new regressions versus the pre-change baseline
  (verified via the `git worktree` diff technique, §21).
- Arena's progress marker now genuinely reflects the underlying `progressPercent`
  (verified via a widget test asserting `getTangentForOffset` returns three
  distinct positions at 0/50/100%).
- The offline auth path (`RestoreUnreachable`) never clears tokens and never
  dereferences a null user during redirect resolution (verified via
  `router_offline_routing_test.dart`'s explicit `tester.takeException()`
  assertions).

---

## 27. Current Open Questions

- Is the palette in §14 (green `#2ecc40` etc.) actually reflected in
  `app_colors.dart`'s current values, or only in the design-audit docs
  created this session? **Not independently re-verified for this handoff —
  check before assuming.**
- Is "native V2 is the default Teach Nuvo engine" (§11) still true, and has
  device-inference latency been measured yet? Neither was independently
  re-verified this session.
- Is the `sign_in_with_apple` 5.0.0 Android build failure (§20) still
  reproducible, or has it since been fixed/worked around?
- Are `docs/design/SCREEN_REMEDIATION_PLAN.md` / `DESIGN_GUIDE_AUDIT_2026-09.md`
  / `DESIGN_SYSTEM_GOVERNANCE.md` still an accurate plan, or superseded by the
  two completed screenshot-driven rounds (§24)?
- What is `docs/NUVO_MOTION_CONTROL_PLANE_PRD.md` (untracked, unauthored by
  any agent this session)? Its existence and purpose were not investigated —
  a future agent should ask the owner before assuming it's authoritative or
  irrelevant.
- Has a physical-device pass confirmed the round-2 geometry fixes (§17, §24)
  actually render correctly? This was explicitly deferred — no simulator was
  available this session, only widget-test geometry assertions.

---

## 28. Recommended First Steps for the New Agent

1. Read, in order: `docs/agents/00-start-here.md`,
   `08-codebase-navigation.md`, `10-pitfalls-and-fixes.md`,
   `18-data-freshness-contract.md`, `19-social-platform-contract.md`, this
   document.
2. Run `flutter analyze --no-fatal-infos`, `flutter test --concurrency=4
   test/*.dart test/arena/`, and `cd server/worker && npm run typecheck &&
   npm test` to confirm the repo is in the state this handoff claims (green
   analyzer, passing tests) before trusting anything else in this document.
3. If asked to do UI work: get real phone screenshots from the owner before
   changing anything — this session's two most productive rounds were both
   screenshot-driven, and speculative "improve the design system" work
   without concrete screenshots repeatedly needed rework.
4. If asked to fix a "slow" or "not updating" screen: do NOT assume the
   architecture doc describes the actual behavior. Trace real query counts /
   real network calls first, the way the `GET /races` N+1 bug was actually
   found (§7, §25).
5. If touching anything under `server/worker/`: you must deploy it yourself
   and confirm production actually serves the change — see the historical
   incident in §12 where a fully-correct, fully-tested change did nothing in
   production for weeks because nobody deployed it.
6. A stale plan file exists at
   `/Users/akshaysanjai/.claude/plans/lazy-chasing-shore.md` (a much earlier,
   broader "full UI/UX audit + foundation rebuild" plan). Much of it appears
   to have already been executed (its own progress log lists most phases
   done). Treat it as historical context, not a live task list, unless the
   owner explicitly says otherwise — cross-check its "still to do" section
   against the current repo state before resuming any of it, since several
   items it lists as open may have been completed in the two screenshot-driven
   rounds described in §24.

---

## 29. Do-Not-Do List

- Do not touch `auth_*` files, `ai_motion_proof_screen.dart`,
  `motion_validators.dart`, `pose_detector_service.dart`,
  `camera_image_converter.dart`, iOS native files, `pubspec.yaml`/`.lock`, or
  `server/worker/` without explicit, named, scoped approval.
- Do not change preset-motion thresholds/state-machine internals for
  Pushups/Jumping Jacks/Plank without proving their tests are unaffected.
- Do not tune V1 (`custom_pose/`) thresholds or add hand-crafted per-movement
  features "as V2 work" — that's the explicit anti-goal for Motion V2.
- Do not add a second cache system for anything — extend the existing doc-18
  contract.
- Do not add Redux/Bloc/a service locator/event sourcing.
- Do not "fix" nav/layout overlap with more padding constants — fix the
  structural composition that requires the guess in the first place.
- Do not cite an architecture/contract document as evidence that running code
  behaves a certain way. Trace it.
- Do not report a preset, a Worker change, or a performance fix as "done" if
  it hasn't been verified against deployed production / real traces.
- Do not run bare `flutter test` (see §21 — it will pick up multi-hour
  `test/motion_qa/` harnesses).
- Do not silently weaken a test assertion, add fake success/fallback data to a
  production path, or swallow an API error to make a test pass.
- Do not introduce a `loc.startsWith('/auth/')`-style origin-route branch into
  post-auth redirect logic — it's the exact bug that made email sign-in behave
  differently from Google (fixed pre-this-session; don't reintroduce it).

---

## 30. Final "State of Nuvo" Snapshot (2026-09-17)

Nuvo is a pre-launch, zero-users, fast-iterating Flutter + Cloudflare Worker
app. The core data-freshness architecture is sound and now uniformly applied
across all four shared-state controllers, with the dominant real-world
performance complaint (Compete/Verify loading slowly) traced to and fixed at
its actual root cause — a backend N+1 query pattern, not a client
architecture problem — and deployed to production. The visual design system
has been through two full screenshot-driven correction passes against an
owner-supplied palette/button spec and is now free of the structural
nav-overlap bug, the frozen-progress-marker bug, and the over-animated splash
screen; a physical-device confirmation pass is still owed. Two parallel
motion-recognition systems exist by design — a deterministic preset-verifier
stack (mature, well-documented, protected) and a learned Teach-Nuvo/Motion-V2
stack (newer, claims native on-device default status, latency unmeasured on
a real device) — and they must never be conflated or cross-wired. The social
platform (invites/QR/crew/notifications) is substantially built (phases A–E,
H done) with push notifications and universal links scaffolded but dormant
pending owner-side external configuration (Firebase credentials, Apple
Developer portal capabilities, an Android release keystore fingerprint) that
no amount of code changes can unblock. The single most important discipline
this session reinforced, repeatedly, the hard way: **prove behavior against
running code and real traces, never against what a document says the
architecture is supposed to do.**
