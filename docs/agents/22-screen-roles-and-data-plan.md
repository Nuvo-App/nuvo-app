# Nuvo Screen Roles & Data Plan — One Job Per Screen, Aggressive Caching

Status: **PLAN ONLY** (planning sub-phase — no code has changed). Read with
[`18-data-freshness-contract.md`](18-data-freshness-contract.md) (the in-memory
cache rules this plan builds on) and
[`19-social-platform-contract.md`](19-social-platform-contract.md) (crew,
notifications, invites). Where this plan and a contract disagree, the contract
stays in force until a numbered change in §7 replaces it. Where any doc and the
code disagree, the code wins.

Evidence for §4 came from six read-only code audits (requests, client caches,
worker cost, proof chain, per-screen loads, persistence options). Nothing was
run on a device; claims marked *(unverified)* were not confirmed in code.

Vocabulary: the product says **crew**; the API and tables say **squad**
(`/squads`, `squads`, `squad_members`, `squad_races`). They are the same thing.

---

## 0. The two problems this plan solves

1. **Screens overlap.** The app has several screens answering the same
   question. Three screens each render a hero for "the race to act on" (Arena's
   next-move hero, Compete's "Continue competing" card, Verify's "Up next"
   hero). Finished races appear in four places (Compete's finished summary,
   Verify's Completed tab, Crew → Races → Recent, Crew → Activity). A person
   can't tell which tab to use for what.
2. **The app re-downloads everything, all the time.** Nothing from the server is
   kept on disk. A cold start fires about seven requests before the first
   screen is useful, every revalidation downloads full payloads even when
   nothing changed, and the only way to know a race moved is to refetch it.

Both have the same cure: **each fact has exactly one owner**, and each owner is
cached aggressively because nobody else is allowed to fetch it.

**Decision:** one verb and one object per screen (§1). One owner and one cache
policy per data domain (§5). The two lists are the same list.

---

## 1. Principle: one verb, one object, one home

| Rule | Meaning |
|---|---|
| One verb | A screen is for one thing a person does: *act now, do the move, find a race, be with people, see me.* |
| One object | It works on one kind of thing: one race, proof, all my races, people and groups, me. |
| One home | Every fact lives on exactly one screen. Everywhere else it is at most **one line plus a link** to its home. |
| No second hero | At most one primary action per screen (already a rule in `NUVO_PRODUCT_MODEL.md`). |

---

## 2. Screen roles

### 2.1 Arena — "What needs me right now?"
- **Verb / object:** act now / one race.
- **Use cases**
  - You open the app at lunch: *"Noah just passed you in Pushup Battle, 41 to 39"* with **Take it back**.
  - Nothing urgent: *"You're caught up. 60 Second Squat Battle starts in 17 minutes."*
  - Brand new: the first-race pitch with example finish lines (exists today).
- **Owns:** the single next-move hero and its one action. The action opens Verify with that race preselected.
- **Must not show:** race lists, history, stats, friends.
- **UX effect:** brings people back at the moments that matter (overtaken, about to start). A new user has exactly one thing to do.
- **Change from today:** already close. Remove any list-like content; make the hero action deep-link into Verify.

### 2.2 Verify — "Do the move, live."
- **Verb / object:** do / the moment of effort.
- **Core idea:** verification happens **as you do the action**, not after. The
  camera counts reps while you do them, or you type the number the second you
  finish. It is not an approval queue, not a dashboard.
- **Three moments, none of them a list**

| Moment | What the person sees | Budget |
|---|---|---|
| **Ready** | A race already chosen (the one Arena pointed at, else the closest to its finish line). The move, a framing guide ("prop your phone about 6 feet away, full body in the box"), one big **Start**. Other active races are small chips. No scrolling. | one tap to start |
| **Live** | A very large count, haptic/sound ticks, one thin context strip ("9 to go · Noah is 2 ahead"). Screen stays awake. Large stop/cancel targets, usable from across the room. If the pose is lost: an in-session hint ("arms out of frame"). | zero chrome |
| **Result** | The count and a confidence cue, then the board moves in front of you: "+9 reps, you're now 2nd". If it didn't count: why, right now, and **Retry** in one tap. | board moves < 1s after submit |

- **Non-camera races** (reading, grades, golf): the same three moments with a
  number field / photo / daily check-in instead of the camera. Finish a round,
  open Verify, type 78, snap the card, the board moves.
- **Interrupted** (a call mid-set): keep the count; resume or submit what was done.
- **No active race:** one line and one button to Compete ("Start a race first"). Never an empty dashboard.
- **Owns:** the live session and its immediate result.
- **Must not show:** a Completed tab (history belongs to Compete), a Recent proof timeline with statuses, leaderboards, race creation.
- **Moves out:** per-race proof history and review/veto/dispute status → Race Detail; "your proof was reviewed" → Notifications. Async review is real, but it is a *follow-up* to the action, so it does not live on the action surface.
- **UX effect:** time from opening the app to the first counted rep is the product's key number. Two existing bugs hit exactly this moment — the "session didn't work" proof error and the screen turning off mid-set — so §6 treats them as core.
- **Change from today:** today's Verify opens on Ready / Completed / Recent tabs with "Up next" and "Ready next" rows and reaches the camera through separate routes (`/race/:id/proof`, `/race/:id/proof/ai-motion`). The tap count was not measured on a device.

### 2.3 Compete — "Start a race, join a race, find any race of mine."
- **Verb / object:** enter and find / all my races, grouped by state.
- **Use cases**
  - Start: pick Pushups from the quick starts, set 25 reps.
  - Join: type a friend's code or scan their QR.
  - Find: last week's finished plank race, or the one that starts tomorrow.
- **Owns:** Start, Join, Your races (active, scheduled, finished with history), quick starts. **The one home for race history.**
- **Must not show:** the "Continue competing" hero (Arena's job), proof submission.
- **UX effect:** one obvious place to look for any old race.
- **Change from today:** remove the featured "Continue competing" card; keep the list and the finished summary. Crew-linked races carry a crew label here instead of a second list in Crew.

### 2.4 Crew — "Who am I racing, and what are we doing together?"
- **Verb / object:** be with / people and groups.
- **People tab** (built): the Crews entry ("Race together on one leaderboard"), your friends and the add tile, requests, and the races running with your crew right now.
- **Activity tab** (built): what the crew did — read-only, with reactions.
- **Races tab** (target): becomes the **crew standings** — each crew's points leaderboard across its races. It stops listing races (that is Compete's job).
- **Must not show:** a personal race list, proof actions.
- **UX effect:** the social reason to come back; the crew leaderboard turns a group of races into a season.
- **Change from today:** Races tab content becomes standings (needs §7 item R4). Until then it can stay as is; it is the only intentional overlap with Compete.
- **Decision (open):** `NUVO_PRODUCT_MODEL.md` says Crew must not show races; the guide kept "racing with your crew". This plan keeps the live-races group on People and moves history/standings as above.

### 2.5 Profile — "Who am I, and what have I earned?"
- **Verb / object:** see me / me over time.
- **Built:** identity, level plate (tap for what levels mean), one Achievements row, the record (racing, wins, win rate) + heat map, Your Nuvo (My code, Notifications, Appearance, Settings).
- **Sub-screens:** Achievements (next goal, next level unlock, then everything), Settings (edit profile, privacy & data, sign out, delete account, legal).
- **Must not show:** races, proof, friends.
- **UX effect:** quiet progress, so racing has a payoff beyond one leaderboard.
- **Data note:** the record strip currently reads the **races list** to compute active count, wins and win rate. §5 moves that into the progression payload so Profile never loads races.

### 2.6 Supporting screens
| Screen | One job | Not its job |
|---|---|---|
| Race Detail | the room for **one** race: standings, that race's proofs and their review status, invite, rules | a second leaderboard anywhere else |
| Notifications | a to-do inbox for things that need a response: invites, requests, "you were passed", proof reviewed | a feed of everything |
| My code / QR | the one home for showing your code (reached from Profile → My code) | duplicate QR/member-code entries in Crew |
| Crews | start/join a crew, crew page with leaderboard | per-race detail |

---

## 3. Ownership matrix

| The thing | Its one home | Elsewhere: at most |
|---|---|---|
| The race I should act on now | Arena | a nav badge |
| Doing the move / submitting proof | Verify | a button from Arena or Race Detail that opens it |
| All my races and history | Compete | one line in a crew view |
| Standings for one race | Race Detail | a rank number |
| Crew standings and members | Crew | none |
| What friends did | Crew → Activity | a notification only when it needs a response |
| Proof history and review status of a race | Race Detail | a notification when it changes |
| My identity, level, achievements, record | Profile | my initials in headers |
| Account, privacy, legal | Settings | none |

---

## 4. Current state (audit evidence)

### 4.1 Requests
- **Cold start**, before the first useful screen: `GET /config` (unawaited), `GET /auth/me` (+ `POST /auth/refresh` on 401), then `GET /races`, `GET /arena`, `GET /crew`, `GET /crew/requests`, `GET /notifications`, `GET /progression`; `GET /races/activities` (ETag-conditional) from `MainShell`. About **seven** authenticated requests.
- **Tab taps** (`main_shell.dart`, each skipped if data is under 45 s old): Arena → arena + motion catalog; Compete/Verify → races + catalog; Crew → crew, requests, notifications; **Profile → nothing** (it loads its own progression and heat map on open).
- **Polling:** one real timer — `race_detail_screen.dart:61` calls `GET /races/:id` every **5 s** while a race page is mounted. It is not gated on app lifecycle or on being the visible route, and it bypasses the 45 s window and the controller's in-flight guard. `GET /races/:id/live[?version=]` also exists *(trigger unverified)*.

### 4.2 Client caches (doc 18 in practice)
- One notifier per domain; 5-minute cache, 45-second `revalidate()` window, single-flight loads, generation guards. A failed background refresh keeps cached data.
- **Nothing is persisted to disk.** Every cold start shows skeletons and refetches six domains. The `loading` / `refreshing` split already exists to support a stale-first render.
- Gaps found:
  - Pull-to-refresh and several screens force-load past the window (`pass_screen`, `crew_groups_screen`, `settings` pages, `profile_screen`) — against doc 18's own rule.
  - Every race write fans out: `arena.markStale()` **fetches immediately even with no screen watching**, `progression.load()` runs unguarded, `CrewController.onMutated` force-loads races. Nothing batches or debounces.
  - Progression lacks the TTL, in-flight de-dup and generation guard the others have; a fetch started before sign-out could land in the next session.
  - The member pass is fetched by the Crew screen straight into local state on every open.
  - The activity feed is only loaded from the Crew screen; progression is not primed.
  - No conditional fetch anywhere on authenticated routes.

### 4.3 Worker cost (ranked)
1. `GET /races` — every race with participants, up to 20 moves each, invites, standings; lazy finalize/start **writes on the read path**.
2. `GET /races/:id` — about 8–10 queries, plus a release spec.
3. `GET /progression` — runs `reconcileProgression` (a write path) on **every read**.
4. `GET /squads/:id` — **N+1**: one score query per crew race, awaited sequentially. (Introduced in the crew feature; cheap at small scale, fixed in R9.)
5. `GET /crew/feed` — correlated subqueries per row (reactions).
Close behind: `GET /arena` (~3 batched queries, small payload).

Only `GET /races/activities` (ETag + 304) and the motion release/asset routes
set cache validators. `races.version` and `races.updated_at` exist and are
bumped on score/member writes (migration 0030) — an almost-free ETag source.

### 4.4 The proof chain (AI Motion Proof)
1. `GET /races/:id` — blocking; the camera shows "processing" until it returns.
2. `POST /races/:id/verification-sessions` — **error swallowed**; the id stays null and is re-minted at submit time.
3. `POST /verification-sessions/:id/start` — fire-and-forget; unnecessary, because `complete` accepts a `created` session.
4. `POST /motion/analyze` — fire-and-forget; result is local-authoritative.
5. `POST /verification-sessions/:id/complete` — **not awaited, failure swallowed**, no retry at that point.
6. `POST /motion-sessions` — fire-and-forget upload; retried on a later app run.
7. Submit gate `_verificationSessionReadyForProof` — re-mints/re-completes once; if still failing: "Verification is still syncing…".
8. `POST /races/:id/proof` — blocking; 20 s timeout; the response carries the whole race.
9. No refetch of the list; the returned race is folded in; `arena.markStale()` and `progression.load()` follow; the celebration route reads the rank from the proof response.

**Why users see "this session didn't work" (best explanation from code):**
- *"Verification session does not match this proof"* — step 5 failed silently, step 7 passed on a stale flag, and the server sees the session not `completed` (or `result_value` lower than the claim).
- *"Verification session was already used"* — step 8 **committed on the server**, but the response timed out (20 s). The retry reuses the same session id and hits the 409, even though the proof was saved. `clientSubmissionId` is reused, but the reuse check is on the session id and returns an error instead of replaying the result.

---

## 5. Target data architecture

### 5.1 Principles
1. **Render from disk first, then revalidate.** Open the app and see last-known data immediately; refresh in the background.
2. **One owner per domain; screens only read.** Screens never call an `*Api` and never force-load (doc 18, enforced).
3. **Ask "has it changed?" before downloading it.** ETag / `If-None-Match` on the heavy GETs; a 304 costs almost nothing.
4. **Patch from responses; don't refetch.** A write returns the new truth (the proof response already carries the race). Apply it to the cache, mark dependents stale **lazily**.
5. **Never poll blindly.** Polling is gated on app foreground + visible screen + an active race, with backoff.
6. **Show freshness honestly.** Cached data is labelled by age where it matters (leaderboards): "updated 12s ago".

### 5.2 Domains, owners and policies

| Domain | Owner | In-memory window | On disk | Validator (cheapest ETag source) | Invalidated by |
|---|---|---|---|---|---|
| Session / flags (`/config`) | `NuvoFlags` | per launch | yes | static; `public, max-age=300` | app start |
| Races list | `RaceController` | 45 s | **yes** | `MAX(version)` + count + `MAX(updated_at)` over viewer's races | own writes (patch), push |
| Race detail | `RaceController` (upsert) | 15 s while open | no (list snapshot is enough) | `W/"id:version:updated_at"` (already loaded) | own writes, push, gated poll |
| Arena | `ArenaController` | derived from races | yes | same as races | races change (lazy) |
| Crew members + requests | `CrewController` | 45 s | **yes** | `MAX(crew_connections.updated_at)` | crew mutations, push |
| Crew activity feed | `crewActivityProvider` | 3 min | yes (last page only) | `MAX(race_events.created_at)` (+ reactions) or short TTL | reactions, push |
| Notifications | `NotificationController` | 45 s | yes (first page) | `MAX(created_at)`, `MAX(read_at)`, unread count | push, bell open |
| Progression (+ record) | `ProgressionController` | 5 min | **yes** | `user_progression.total_xp + level + last_seen_level` (one PK row) | race writes that earn XP |
| Profile heat map | `activity_controller` | 5 min | yes | `private, max-age=60` is enough | proof submit |
| Crews (squads) list/detail | new notifier (today: screen-local) | 45 s | yes | `MAX(races.version)` over the crew's races + member count | crew mutations, race link |
| Member pass | `AuthController` / user model | per session | yes (with user) | n/a | profile edit |
| Motion catalog | `RaceController` | existing ETag | yes (exists) | existing | app start |

**Decision:** the proof-chain domains (races, race detail) are the most
aggressively cached **and** the most carefully invalidated; everything else is
cached for convenience. A screen may show stale data; it may never show another
account's data (§5.3).

### 5.3 Disk cache design (no new dependencies)
- Storage: `getApplicationSupportDirectory()` + one JSON file per domain,
  `cache/<accountId>/<domain>.json`. `path_provider` is already installed;
  there is no shared_preferences/hive/sqflite, and none is needed.
- Write pattern: copy `verifier_release_cache_io.dart` — write `*.tmp` with
  `flush: true`, then rename, so a crash never leaves a half file; a corrupt
  read returns "no cache" and is deleted.
- Envelope: `{ schema: n, savedAt, etag, data }`. A bumped `schema` discards
  old files. Per-domain `maxAge` (default 7 days) after which the snapshot is
  not rendered.
- Safety: keyed by account id; **wiped on sign-out, account switch and account
  deletion**; never stores tokens (those stay in `SecureTokenStore`); the cache
  contains other people's names and avatars, so it is private app storage only.
- Testing: a `.memory()` constructor like `FirstUseStore.memory()`, exposed by a
  Riverpod provider, so tests never touch disk.
- Hydration: each notifier loads its snapshot in `build()`, emits it as data
  with `refreshing: true`, then runs its normal `revalidate()`.

### 5.4 Conditional HTTP (server, additive)
- Add `ETag` (weak) and `Cache-Control: private, no-cache` to the authenticated
  GETs in §5.2; honour `If-None-Match` with `304`. `GET /config` gets
  `public, max-age=300`; `GET /races/activities` already has the ETag and only
  needs a `max-age`.
- **Backward compatible:** older app builds don't send `If-None-Match`, so
  they keep getting full `200`s. Nothing in a response body changes.
- Caveat: several GET handlers perform lazy lifecycle writes (finalize,
  mark started). The validator must be computed **after** that step (or the cron
  sweep relied on), or a 304 would hide a transition.
- Largest saving per effort: `GET /races/:id` (a 304 skips ~8 queries), then
  `/races` and `/arena` via `MAX(version)`.

### 5.5 Refresh policy
- **Cold start:** paint from disk immediately; revalidate **only what is
  stale**; prime the activity feed and progression with the rest. Target: the
  first screen shows content before any network call returns.
- **Tab focus:** revalidate only if older than the domain's window; a revalidate
  that returns 304 is silent. **Profile tab gets a revalidate** (it has none).
- **Pull-to-refresh** is the *only* force, and it goes through the controller's
  `refresh()` — single-flight, not a screen-level `load(force: true)`.
- **Lazy staleness:** `markStale()` stops fetching immediately; it marks the
  domain and the next reader (or the next focus) triggers the revalidate.
- **Race detail polling:** replace the unconditional 5 s timer with: only while
  the app is resumed, the page is the visible route, and the race is active;
  use `GET /races/:id/live?version=` or a conditional detail GET; back off from
  5 s → 15 s after three unchanged responses; stop when paused; a push
  notification marks the race stale immediately.
- **Push as a signal:** a received push (`push_service`) marks the affected
  domain stale — the cheapest "something changed" signal the app has.

### 5.6 The Verify / proof pipeline
Goal: **a user never sees a session error for something that actually worked**,
and the board moves instantly.

| # | Change | Why |
|---|---|---|
| P1 | Server **completes the session inside `POST /races/:id/proof`** (same D1 batch) when a `verificationSessionId` is supplied; the separate `complete` call stays supported | removes the "does not match" failure class; one fewer round trip |
| P2 | **Idempotent replay:** if a `move_logs` row already exists for the same session id *and* `clientSubmissionId`, return `200` with the current race instead of `409` | fixes "was already used" after a timeout |
| P3 | Client **retries `/proof` automatically** on timeout/network error with the same `clientSubmissionId` (safe after P2), then shows an error | no false failures |
| P4 | Client retries `complete` in the background with backoff (3 tries) instead of swallowing it | belt and braces for older servers |
| P5 | Drop `POST …/start` (unneeded) | one fewer request |
| P6 | Mint the session in parallel with the race detail load (or embed it in the race detail response for AI-motion races) | removes a swallow point and a round trip |
| P7 | **Optimistic board:** apply the local value/rank to the cached race before the response; reconcile with the returned race; open the celebration immediately | the board moves in front of the user |
| P8 | Defer `/motion/analyze` and the artifact upload until after the proof response | they compete for bandwidth with the critical path |
| P9 | Keep the screen awake during Ready/Live/Result (`wakelock_plus`, via a wrapper widget at the route) | the screen no longer sleeps mid-set |

**Approvals required:** P1–P3 touch `server/worker/src/routes/races.ts`; P3, P4,
P6, P8 touch `ai_motion_proof_screen_io.dart`; P9 touches `pubspec.yaml`. All
three are no-touch areas in `AGENTS.md` and need explicit, scoped sign-off.

### 5.7 Per-screen data contract (target)

| Screen | Reads | Loads itself | Notes |
|---|---|---|---|
| Arena | arena snapshot (from races) | nothing; shell revalidates | never calls an API |
| Verify | races (active, proof capability) | nothing; the session pipeline only | no Completed/Recent data |
| Compete | races | nothing | pull-to-refresh → `races.refresh()` |
| Crew | crew, requests, activity, crews, notification count | nothing | member pass moves out of local state |
| Profile | progression (+ **record**: active count, wins, win rate), heat map | nothing | stops reading the races list |
| Race Detail | one race | gated poll (§5.5) | owns that race's proof history |
| Notifications | notification list | `loadMore` only | first page hydrated from disk |

Profile's record strip needs a server-computed `record` block in
`GET /progression` (R10) so Profile no longer depends on the full races list.

---

## 6. Why this fixes the two user-visible problems
- **"This session didn't work":** P1–P4 remove the failure paths in §4.4; P9
  removes the screen-sleep failure. These are the same work as the Verify
  redefinition in §2.2 — one build, not two.
- **"Slow, spinner-heavy app":** §5.3 removes skeletons on every open; §5.4
  and §5.5 remove most traffic.

---

## 7. Request and endpoint change list

Size: S ≈ hours, M ≈ a day, L ≈ multiple days. **NT** = touches a no-touch area
(needs approval).

| ID | Change | Where | Size | NT | Backward compat |
|---|---|---|---|---|---|
| C1 | `CacheStore` (atomic JSON, per account, schema-versioned, `.memory()`) | new `lib/core/cache/` | M | no | n/a |
| C2 | Hydrate races/arena/crew/notifications/progression/activity from disk | the six controllers | M | `race_controller.dart` is "casual no-touch" | invisible to server |
| C3 | Remove screen-level force-loads; add controller `refresh()` | `pass_screen`, `crew_groups_screen`, `profile_screen`, settings | S | no | invisible |
| C4 | `markStale()` becomes lazy; batch `onMutated` fan-out | arena, crew, progression, race controllers | S | `race_controller.dart` | invisible |
| C5 | Add TTL, single-flight and generation guard to `ProgressionController`; revalidate on Profile tab tap | progression controller, `main_shell.dart` | S | no | invisible |
| C6 | Member pass into the user/auth state; stop refetching per open | `pass_screen`, auth state | S | **auth files** | invisible |
| C7 | Gate the 5 s race poll on lifecycle + visibility + active + backoff | `race_detail_screen.dart` | S | no | invisible |
| C8 | Push receipt marks domain stale | `push_service`, controllers | S | no | invisible |
| R1 | ETag + `If-None-Match` for `/races`, `/races/:id`, `/arena` | worker | M | `server/worker/` | additive |
| R2 | ETag for `/crew`, `/crew/feed`, `/notifications`, `/progression` | worker | M | `server/worker/` | additive |
| R3 | `/config` `max-age`; `/races/activities` `max-age` | worker | S | `server/worker/` | additive |
| R4 | Crew standings endpoint (per crew, across races) for Crew → Races | worker + Crew screen | M | `server/worker/` | additive |
| R5 | Server completes the session inside `/proof` (P1) | `races.ts` | M | **yes** | accepts old and new |
| R6 | Idempotent replay on duplicate session + `clientSubmissionId` (P2) | `races.ts` | S | **yes** | additive |
| R7 | Make `reconcileProgression` event-driven, not per-read | `progression.ts` | M | `server/worker/` | invisible |
| R8 | Verify rebuilt as Ready/Live/Result; drop Completed/Recent | `move_screen.dart` | L | no | invisible |
| R9 | Batch the `/squads/:id` per-race score loop into one `IN (...)` query | `squads.ts` | S | `server/worker/` | invisible |
| R10 | Add `record` (active count, wins, win rate) to `/progression` | worker + Profile | M | `server/worker/` | additive field |
| P3–P4, P6–P8 | client retry / optimistic board / mint-in-parallel / defer analyze | `ai_motion_proof_screen_io.dart`, `race_controller.dart` | M–L | **yes** | invisible |
| P9 | `wakelock_plus` wrapper at the AI-proof and teach routes | `pubspec.yaml`, `router.dart`, new widget | S | **yes** (deps) | invisible |

---

## 8. Phasing and parallel work

Each task is small and owns its files, so agents can work at once without
colliding. Every phase ends with `flutter analyze` (no new findings) and the
tests for the touched screens.

**Phase 0 — contracts (this document).** Update doc 18 to mention disk
hydration, conditional fetch and lazy staleness; add this plan to the README
index.

**Phase 1 — client only, no backend, no approvals** *(safe to ship alone)*
- A: C1 `CacheStore` + tests.
- B: C3 remove screen force-loads.
- C: C5 progression guards + Profile tab revalidate.
- D: C7 gated race poll.
- E: C8 push → stale.
- Then F: C2 + C4 hydrate and lazy staleness (depends on A).
- Exit: cold start paints from disk; tab switches inside the window make zero requests.

**Phase 2 — backend, additive** (needs `server/worker/` approval)
- G: R1 ETags for races/detail/arena. H: R2 remaining ETags. I: R3 headers. J: R9 squads batch.
- Then K: client conditional requests (`If-None-Match`) once G/H are deployed.
- Exit: unchanged revalidations return 304; older builds unaffected.

**Phase 3 — proof pipeline** (needs approval for `races.ts`, camera screen, `pubspec.yaml`)
- L: R5 + R6 server. Then M: P3/P4/P6/P8 client. N: P7 optimistic board. O: P9 wakelock.
- Exit: no session error on a proof that was saved; board moves before the response.

**Phase 4 — screen roles**
- P: R8 Verify Ready/Live/Result. Q: Compete trims (remove the featured card). R: R4 + Crew → Races standings. S: R10 + Profile record from progression.
- Exit: each tab does one thing; the matrix in §3 is true.

Each phase can be released independently; Phase 1 does not require a backend
deploy, and none of the backend changes break older beta builds.

---

## 9. Acceptance metrics

| Metric | Today (audit) | Target |
|---|---|---|
| Authenticated requests before first useful screen | ~7 | ≤ 2 and content paints before any returns |
| Time to content on a warm launch | skeleton until network | cached content on first frame |
| Requests on a tab switch inside the window | 0–3 | 0 |
| Revalidation payload when nothing changed | full body | 304 (empty) |
| Race page polling | 5 s, always | gated; ≥ 15 s when quiet; 0 in background |
| Proof submit: false "session" failures | observed in beta | 0 for saved proofs |
| Opening Verify → first counted rep | multi-screen | one tap from Ready |
| Board visibly updated after proof | after response | immediately (optimistic), reconciled |

Add counters (debug build): requests per cold start, requests per tab switch,
304 ratio, disk-cache hit rate, proof submit retries.

---

## 10. Risks and guardrails
- **Stale or wrong data on a leaderboard.** Label by age; foreground
  revalidation always runs; push marks stale. A 304 must be computed after lazy
  lifecycle writes (§5.4).
- **Cross-account leakage.** Cache keyed by account, wiped on sign-out/switch/delete; covered by a test.
- **Cache poisoning by schema drift.** `schema` in every file; unknown → discard.
- **Optimistic board lying.** Reconcile with the response; if the server rejects, roll back and say why.
- **No-touch areas.** Auth, the camera/AI files, `race_controller.dart`,
  `pubspec.yaml`, `server/worker/` — every item marked NT needs named approval
  per `AGENTS.md` before it starts.
- **Scale of the hackathon vs production.** The crew N+1 and per-read
  progression reconcile are fine at demo size and must be fixed before a real
  launch (R7, R9).

---

## 11. Open decisions
1. **Verify name:** "Verify" suggests checking, not doing. Keep, or rename to match the action?
2. **Free practice count:** a no-race counting mode for new users. Needs a new session type. Worth it?
3. **One set, several races:** should one set of 20 pushups count in two pushup races? Safer default: one race at a time.
4. **Crew → Races:** standings only (this plan) or keep a race list too?
5. **Bootstrap endpoint:** one `GET /bootstrap` returning the data needed for first paint would cut cold start to a single request. Larger backend change; decide after Phase 1/2 numbers.
6. **Cache maxAge:** 7 days proposed. Shorter for leaderboards, longer for profile data?
