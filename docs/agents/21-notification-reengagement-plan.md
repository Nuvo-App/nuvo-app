# Nuvo Notification & Re-engagement System — Design Plan

Status: **PLAN — pre-implementation.** Extends
[19-social-platform-contract.md](19-social-platform-contract.md) phases E–F.
Where this doc adds policy/scheduling machinery, it wraps — never replaces —
the `emitNotification` pipeline doc 19 established. Builds on
[18-data-freshness-contract.md](18-data-freshness-contract.md) (inbox),
[15-crew-system-plan.md](15-crew-system-plan.md) (crew events),
[16-notification-system-plan.md](16-notification-system-plan.md) (rationale).

> Product rule that governs everything below: a notification exists because a
> real person did a real thing that changed something for me. Inactivity,
> engagement targets, and calendar time alone never generate one.

---

## 1. Existing system (recon inventory)

### Backend (`server/worker`)

| Piece | Where | State |
|---|---|---|
| `emitNotification(db, opts)` | `domain/notifications.ts` | **Live.** Checks recipient's per-category `in_app` pref, `INSERT OR IGNORE` on `(user_id, dedupe_key)` unique index. |
| `safeEmit(c, opts)` | `domain/notifications.ts` | **Live.** emit + best-effort `sendPush` via `executionCtx.waitUntil`. Never throws. |
| `deliverNotificationPushes(c, ids)` | `domain/notifications.ts` | **Live.** Push delivery for rows written inside D1 batches (crew lifecycle). |
| `sendPush(env, userId, payload)` | `domain/push.ts` | **Dormant.** FCM HTTP v1, OAuth2 service-account. Returns 0 without `FCM_SERVICE_ACCOUNT` + `FCM_PROJECT_ID`. Disables dead tokens. |
| `transitionCrew` notifications | `domain/crewLifecycle.ts` | **Live.** Writes `crew_request` / `crew_request_accepted` / `crew_connected` rows inside the connection batch; resolves stale `crew_request` rows on accept/decline/remove; private-profile-aware naming. |
| Schema | `migrations/0014` | `notifications` (+dedupe +unread indexes), `notification_preferences`, `device_tokens`. |
| Routes | `routes/notifications.ts` | `GET /` (cursor + unreadCount), `/:id/read`, `/read-all`, `GET/PATCH /preferences`. |
| Devices | `routes/devices.ts` | `POST /devices`, `DELETE /devices/:token`. |
| Cron | `index.ts` `scheduled:` + `wrangler.toml` `crons = ["0 3 * * *"]` | Motion-data purge only. No notification scheduling exists. |
| Race lifecycle | `domain/raceLifecycle.ts`, `applyMoveProgress` | `effectiveRaceStatus(status, start_at, end_at)` is **lazy** — deadline-expired races are never finalized (no standings snapshot, no emits). `applyMoveProgress` already returns `previousRank`, `newRank`, `peoplePassed`, `raceCompleted`, `winnerUserId` — currently used only in the submission response. |

### Emit sites today (the whole inventory)

| Event | Category | Route | Recipient | Push default |
|---|---|---|---|---|
| Member added | `race_invite` | `POST /races/:id/participants`, `/members` | added user | on |
| Member joins | `race_joined` | `notifyRaceJoined`, invite accept | creator only | on |
| Proof reviewed | `proof_accepted` / `proof_rejected` | `PATCH /races/:id/moves/:moveId` | submitter | on |
| Crew request | `crew_request` | `/crew/add`, `/invites` accept | target | on |
| Request accepted | `crew_request_accepted` | `transitionCrew` | requester | off |
| Crew connected | `crew_connected` | `transitionCrew` | both | off |

**Declared but never emitted:** `passed_on_leaderboard`, `race_starting`,
`race_completed` — prefs defaults and client display labels already exist.

### Flutter

- `NotificationController` (doc-18): inbox source of truth, cursor pagination,
  optimistic read, `markStale` on push, generation guard on account switch,
  presentation-demo fixtures. **The inbox doubles as the Crew activity feed**
  (`pass_screen.dart` takes `notificationControllerProvider.items.take(8)`).
- `NotificationBell` + `unreadCountProvider` badge; `/notifications` inbox;
  `/settings/notifications` per-category App/Push toggles (Races/Proof/Crew).
- `PushService`: dormant; `requestPermissionInContext` is called only from
  `invite_screen`; token sync on sign-in, unregister on sign-out.
- `NuvoDestination` sealed model; `DeepLinkController` + `PendingDestinationStore`
  give pending-through-auth routing.

### Known gaps / one real bug

- **BUG:** `PushService._routeFromMessage` calls `_router.go(dest.location)`
  directly — bypasses `handleDestination`, so a push tap while logged out
  ignores `requiresAuth` and the pending store (account-isolation hole).
- No policy layer: every event → 1 row → 1 push. No priority, rate limits,
  aggregation, cooldowns, quiet hours, or budget.
- No scheduling: one purge cron only; `race_starting`, finish reminders, and
  deadline finalization have no producer.
- No user timezone (races carry `timezone`; `profiles`/`users` don't).
- No reactions feature, no streak infra (`streakDays` is a client stub;
  `daily_streak` recurrence exists server-side), no analytics layer, no
  app-icon badge, no notification retention/purge, no invite→signup
  attribution (`invite_uses` records redemption, not registration source).

---

## 2. Architecture — the policy pipeline

Doc 19's model is right: domain objects, structured dest, inline emission.
What's missing is the layer *between* event and emit. Introduce one:

```
domain event (route or cron job)
  └─> buildNotificationIntents(event)        pure: event → Intent[]
  └─> eligibility(intent)                    member? blocked? still relevant?
  └─> priority                               CRITICAL|HIGH|MEDIUM|LOW|FEED_ONLY
  └─> policy gates                           pref → cooldown → budget → aggregate?
  └─> emitNotification (existing)            dedupe-idempotent durable row
  └─> push decision                          pref + push-eligible + budget
  └─> sendPush (existing)                    + notificationId + badge in payload
```

New file `domain/notificationPolicy.ts` — pure functions, unit-testable, no
I/O except the gates it explicitly performs. Routes stop calling `safeEmit`
with raw copy; they call `notify(c, domainEvent)` which produces intents and
runs the pipeline. `emitNotification`/`sendPush`/schema/dedupe are untouched
in shape — extended, not replaced.

**Priority → default delivery** (user prefs can only tighten, not loosen):

| Priority | Inbox | Push default | Examples |
|---|---|---|---|
| CRITICAL_FUNCTIONAL | yes | always | proof rejected, security |
| HIGH | yes | on | overtake near podium, race invite, crew request, race finished, proof verified |
| MEDIUM | yes | on (opt-out) | joined your race, request accepted, starting soon, invite converted |
| LOW | yes | off | crew member joined a shared race |
| FEED_ONLY | yes* | never | proof submitted, minor rank moves |
| SUPPRESS | — | — | never materializes |

*FEED_ONLY rows are the Crew-activity feed — they get `priority='feed'` and
aggregate aggressively.

---

## 3. Proposed event catalog

Copy rules: actor-first, specific numbers, no filler. `{A}`=actor `{R}`=race.

### Tier A — ship first

| Event | Trigger | Recipient | Priority | Push | Inbox | Feed | Dedupe key | Dest | Example copy |
|---|---|---|---|---|---|---|---|---|---|
| `race_invite` | member add / invite accept pending | invitee | HIGH | yes | yes | no | `race_invite:{raceId}:{userId}` | `race/{id}` | "{A} added you to {R} · Starts tomorrow." |
| `crew_request` | `transitionCrew` pending | target | HIGH | yes | yes | no | `crew:{conn}:pending` | `profile/{actor}` | "{A} wants to join your crew" |
| `crew_request_accepted` | accept | requester | MEDIUM | **on** (was off — it's a direct reply to your action) | yes | yes | `crew:{conn}:active` | `profile/{actor}` | "You're in {A}'s crew now · Race together →" |
| `crew_connected` | QR/connect | both | MEDIUM | on | yes | yes | `crew:{conn}:active` | `profile/{other}` | "{A} joined your crew" |
| `passed_on_leaderboard` | `applyMoveProgress` rank diff | overtaken members | HIGH | yes | yes | yes | `overtake:{raceId}:{actor}:{target}:{2h-bucket}` | `race/{id}?ctx=leaderboard` | "{A} just passed you 🔥 · You're #2 in {R}." |
| `race_completed` | target hit **or** deadline finalize | all members | HIGH | yes | yes | yes | `race_completed:{raceId}:{userId}` | `race/{id}?ctx=results` | Winner: "You won {R} 🏆 · {score}. First place." Others: "{A} won {R} · You finished #2." |
| `race_starting` | `start_at` reached | all members | HIGH | yes | yes | yes | `race_starting:{raceId}` | `race/{id}` | "{R} starts now · {n} people are in." |
| `finish_line_close` | `end_at − 2h` | unfinished members in contention | HIGH | yes | yes | no | `finish:{raceId}:{userId}` (once, ever) | `race/{id}` | "2 hours left ⏱ · You're {gap} behind {leader}." |
| `proof_accepted` / `proof_rejected` | review outcome | submitter | HIGH (rejected is actionable) | yes | yes | no | `proof_review:{moveId}:{status}` | `race/{id}` | "Proof verified ✓ · +25 pushups in {R}." / "We couldn't verify that proof · Review it and try again." |
| `proof_needs_review` | move lands `pending`/`needs_review` | race creator/reviewers | MEDIUM | yes | yes | no | `proof_review_needed:{moveId}` | `race/{id}?ctx=review` | "{A}'s proof needs review · {R}." |
| `invite_signup` | invite redeemed by **new** account | inviter | HIGH | yes | yes | yes | `invite_signup:{inviteId}:{userId}` | `profile/{newUser}` | "{A} joined Nuvo from your invite 🎉" |
| `race_joined` | member joins | creator | MEDIUM | yes | yes | yes | `race_joined:{raceId}:{userId}` + aggregate `{raceId}:{day}` | `race/{id}` | "{A} joined {R} · 4 people are racing now." |

### Tier B — after Tier A is stable

| Event | Trigger | Recipient | Priority | Push | Inbox | Feed | Dedupe / aggregation | Dest | Copy |
|---|---|---|---|---|---|---|---|---|---|
| `crew_member_joined_race` | crew member joins a race you're in | other members | LOW | no | yes | yes | `crew_race:{race}:{day}` aggregate | `race/{id}` | "{A} joined {R} · 5 people are racing now." |
| `race_invite_reminder` | pending invite, race starts ≤ 24h | invitee | MEDIUM | yes, once | yes | no | `invite_reminder:{inviteId}` | `race/{id}` | "{R} starts tonight · {A} and 4 others are in." |
| `proof_submitted` (feed) | verified move | crew + race members | FEED_ONLY | never | yes | yes | `proofs:{race}:{6h-window}` aggregate | `race/{id}` | "{A} finished 3.2 mi 🏃" → rolled up "{A} and 2 others submitted proof in {R}." |
| `lead_battle` | same pair trades #1 ≥3× in window | both racers | MEDIUM | yes | yes | yes | `battle:{race}:{pair}:{day}` | `race/{id}?ctx=leaderboard` | "You and {A} have traded the lead 3 times 🔥 · You're #1." |
| `crew_day` | ≥3 crew members hit goals same day | crew | FEED_ONLY | aggregate, ≤1/day | yes | yes | `crew_day:{user}:{date}` | `crew` | "Your crew is moving 🔥 · {A}, {B} and {C} finished goals today." |
| `invite_nudge` | inviter's invite unredeemed 48h | inviter | LOW | no | yes | no | `invite_nudge:{inviteId}` | `invite/{token}` | "{R} starts tomorrow — your invite is still open." |

### Tier C — blocked on missing infra

| Event | Blocker |
|---|---|
| `streak_at_risk`, `streak_milestone`, `crew_streak` | No streak computation exists (`streakDays` is a client stub). Build streaks first; rules: at-risk only if real deadline + incomplete, milestones only, never shame. |
| `reaction_*` | No reactions feature. If shipped: aggregate per proof/30min, push only first reaction, copy "{A} sent 🔥 on your run." |
| `reengagement_digest` | Needs last-active tracking. Rule: **only** emits when a real pending item exists (expiring invite, race ending soon, unread crew request). If nothing real → send nothing. ≤1 per 5 days. |

**Explicit non-events** (feed-or-nothing, never push): minor rank moves
(17→16), own-submission confirmations (user is staring at the result),
"n proofs this week" summaries, anything invented.

---

## 4. Overtake detection — the crown jewel

`applyMoveProgress` currently throws away most of what it computes.

```
before UPDATE race_progress:
  prevRanks = SELECT user_id, rank_cache FROM race_progress WHERE race_id=?
apply scored submission, recomputeRanks()
after:
  newRanks  = SELECT user_id, rank_cache FROM race_progress WHERE race_id=?
diff: for each member where newRank > prevRank AND actor's newRank < member's newRank
  → intent passed_on_leaderboard(actor → that member)
```

Eligibility gate (keeps a 200-person race survivable):

- recipient's `prevRank ≤ 3` **or** `newRank ≤ 3` **or** actor ∈ recipient's
  active crew → notify.
- else → nothing (a drop from #47→#48 is feed-at-most and usually nothing).
- leader-change special case: when actor takes #1, the displaced #1 always
  qualifies.
- cooldown: same directed pair per race, 30 min — enforced via dedupe key
  `overtake:{race}:{actor}:{target}:{floor(now/30min)}`.
- the submitter's own "you moved up" is inbox-only, LOW — they just watched
  the result.
- ≥3 lead trades between one pair in a day upgrades to one `lead_battle`
  aggregate instead of a 4th overtake push.

Race-condition note: two concurrent submissions can each see a stale
pre-snapshot. The dedupe window + cooldown bounds the damage to at most one
extra push per pair per 30 min; acceptable for v1 (a per-race mutex is over-
engineering at Nuvo's scale).

---

## 5. Scheduling system

New table `notification_jobs` — deterministic, inspectable, cancellable:

```sql
CREATE TABLE notification_jobs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,            -- race_starting | race_starting_soon |
                                 -- finish_reminder | race_deadline_finalize |
                                 -- invite_reminder | reengagement_check
  entity_type TEXT, entity_id TEXT,   -- race / invite
  user_id TEXT,                     -- null = fan-out at claim time
  dedupe_key TEXT NOT NULL UNIQUE,
  run_at TEXT NOT NULL,
  payload_json TEXT,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | sent | cancelled
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

- **Produced at write time**, not scanned: `POST /races` with `start_at` →
  `race_starting` job; with `end_at` → `finish_reminder` (end−2h) +
  `race_deadline_finalize` (end+1min). Update/delete cancels pending jobs for
  the entity. Claim-time revalidation: job re-checks `effectiveRaceStatus`
  and recipient membership before emitting — a stale job no-ops.
- **Consumer:** second cron `* * * * *` claims due jobs (`UPDATE … SET
  status='sent' WHERE id IN (due)` inside a batch), then runs each through
  the same policy pipeline. Retry-safe: `dedupe_key` + job status make a
  double-claim a no-op.
- `race_deadline_finalize` does what nothing does today: past-`end_at` race →
  `snapshotFinalStandings`, set `status='completed'` + `winner_user_id`
  (leader at deadline), emit `race_completed` to members.
- `finish_line_close` eligibility at claim time: recipient unfinished AND
  (rank ≤ 3 OR gap to leader ≤ 15% of target). Outside that → job marks sent,
  no notification. **Once per race per user, ever** (dedupe key).

Timezone: add `profiles.utc_offset_minutes` (+`tz_name` best-effort). Client
sends `DateTime.now().timeZoneOffset` on sign-in/resume — no new dependency.
Scheduled *reminder* jobs (invite nudge, digest, streak-at-risk later) shift
`run_at` into the recipient's 09:00–21:00 local window at claim time.
Immediate social pushes are exempt — a real-time overtake is real-time.

---

## 6. Aggregation & budget

**Aggregation** (row update, not stacking): extend `emitNotification` with
`aggregateKey` + `onConflict:'update'`. `INSERT … ON CONFLICT(user_id,
dedupe_key) DO UPDATE SET title, body, aggregate_count=aggregate_count+1,
read_at=NULL`. First insert pushes; updates bump the row silently (inbox
re-reads it as new). Dedupe keys carry the window (`{day}`/`{6h}`/`{30min}`).

**Push budget** (per user, evaluated in the policy gate via indexed lookback
on `notifications.created_at` — no extra table):

| Scope | Cap |
|---|---|
| Engagement pushes (non-functional) | ≤ 1 / hour, ≤ 4 / day |
| Competitive per race | ≤ 2 / hour |
| Same directed overtake pair | ≤ 1 / 30 min |
| Aggregates (`race_joined`, `proofs`, `crew_day`) | ≤ 1 per window per entity |
| CRITICAL_FUNCTIONAL + direct requests | uncapped |

Suppressed intents still create their inbox row (when in-app eligible) — the
budget gates *interruption*, never *record*. Suppression is observable via a
cheap `notification_suppressed` log line (structured console + later an
events table) rather than silently dropped.

---

## 7. Preferences

Keep `notification_preferences(user_id, category, in_app, push)` — new
categories join `NOTIFICATION_CATEGORIES` and flow through the existing
`GET/PATCH /preferences` + prefs screen automatically (add labels/groups to
`notification_prefs.dart` display map).

| New/changed category | Group | Push default |
|---|---|---|
| `passed_on_leaderboard` | Races | on |
| `race_completed`, `race_starting` | Races | on |
| `finish_line_close`, `race_starting_soon` | Races | on |
| `race_invite_reminder` | Races | on |
| `proof_needs_review` | Proof | on |
| `invite_signup` | Crew | on |
| `crew_request_accepted`, `crew_connected` | Crew | on (was off) |
| `crew_member_joined_race`, `crew_day`, `proof_submitted`, `lead_battle` | Crew/Races | off |
| `reengagement_digest` | Reminders | off |

Quiet hours + a "pause push" master switch: `profiles` gains
`quiet_start`, `quiet_end`, `utc_offset_minutes` — phase 3, evaluated at
push-decision time only (inbox unaffected).

---

## 8. Deep-link map (all `NuvoDestination`-compliant)

| Category | dest_type | dest | Route |
|---|---|---|---|
| race_invite / reminder | `race` | `{raceId}` | `/race/:id` |
| passed_on_leaderboard / lead_battle | `race` | `{raceId}` ctx `leaderboard` | `/race/:id` (leaderboard is the room) |
| race_starting / completed / finish / joined | `race` | `{raceId}` ctx `results`→default | `/race/:id` |
| proof_* | `race` | `{raceId}` ctx `review` for review | `/race/:id/settings` exists; add `ctx:'submit'`→ race detail CTA |
| crew_* | `profile` | `{userId}` | `/u/:id` |
| crew_day | `crew` | — | `/pass` |
| invite_signup | `profile` | `{newUserId}` | `/u/:id` |
| reengagement_digest | `notifications` | — | `/notifications` |

`RaceDestination.context` gains `'leaderboard'` (→ `/race/:id` today; wire to
a leaderboard anchor later) and `'results'` (→ `/race/:id`, completed state).

---

## 9. Backend changes

1. **Migration 0030**: `notifications.priority TEXT DEFAULT 'medium'`,
   `notifications.aggregate_count INT DEFAULT 1`; `notification_jobs` table;
   `profiles.utc_offset_minutes INT, tz_name TEXT, quiet_start INT,
   quiet_end INT`; `users.referred_via_invite_id TEXT` (invite→signup
   attribution); index `notifications(user_id, created_at)` already exists
   for budget lookbacks.
2. **`domain/notificationPolicy.ts`** (new): `notify(c, domainEvent)` —
   intents → eligibility (membership, `isBlocked`, crew visibility via
   `canSeeIdentity`) → priority → pref → cooldown/budget lookbacks →
   aggregate-or-emit → push decision.
3. **`domain/notificationJobs.ts`** (new): `scheduleJob`, `cancelJobsFor`,
   `claimDueJobs`, job handlers (start/finish/finalize/reminders).
4. **`routes/races.ts`**: `applyMoveProgress` → rank-diff intents +
   `race_completed` fan-out; `POST /races` + update → write/cancel jobs;
   move landing `pending` → `proof_needs_review`; deadline-finalize handler.
5. **`routes/invites.ts`**: `invite_signup` (when redeemer's `created_at`
   within grace window), `race_joined` aggregation, `invite_reminder` jobs.
6. **`domain/notifications.ts`**: `aggregateKey`/`onConflict:'update'` mode;
   `priority` on the row.
7. **`domain/push.ts`**: payload adds `notificationId`; `aps.badge` =
   recipient's current unread count (one indexed COUNT at send).
8. **`index.ts`**: `crons` gains `"* * * * *"`; `scheduled:` claims due jobs
   alongside the existing purge.
9. **`routes/notifications.ts`**: `POST /push-open` beacon (notificationId +
   category) for the downstream-action metric later.

## 10. Flutter changes

1. **Fix the auth bypass**: `PushService._routeFromMessage` →
   `deepLinkController.handleDestination(dest, authed: …)` — restores
   `requiresAuth` + `PendingDestinationStore` for push taps.
2. **Contextual permission**: move the prompt out of `invite_screen` into a
   pre-permission explainer card shown after first race join / first crew
   connect ("Don't miss the race — we'll tell you when someone passes you,
   your proof is verified, or it finishes.") → OS prompt only on confirm.
3. **Timezone sync**: send `utc_offset_minutes` (+`tz_name` when obtainable)
   on sign-in/app-resume to `PATCH /me` or a preferences endpoint.
4. **Prefs screen**: labels/groups for new categories (display map only).
5. **Badge**: server-driven `aps.badge`; on app-open + `markAllRead`, client
   resets via `FirebaseMessaging.instance.setApplicationIconBadgeNumber` —
   *requires deciding whether to add `flutter_app_badger` or accept
   server-side badge only.* Flag for approval (pubspec is no-touch).
6. **Push-open beacon**: `_routeFromMessage` posts `notificationId` to
   `/notifications/push-open`.

## 11. Safety / performance risks

- **Rank-diff double-fire** on concurrent submissions — bounded by 30-min
  pair cooldown; v1 accepts it.
- **Job fan-out N+1**: claim-time fan-out uses one `INSERT … SELECT` for the
  member set (same pattern as `crewNotificationStatement`), not per-member
  queries.
- **Privacy**: all social intents pass through `isBlocked` +
  `canSeeIdentity`/co-racer visibility *before* emit — a lock screen never
  leaks a name the inbox wouldn't show. Private-profile naming already
  handled by `crewNotificationStatement`; reuse that resolution in policy.
- **Account isolation**: unregister on sign-out + generation guard exist;
  fix the `_routeFromMessage` auth bypass (§10.1) and verify `POST /devices`
  rebinds a token's `user_id` on re-register (device reused across accounts).
- **Stale destination**: race deleted → `/race/:id` → existing 404 state
  ("Race not found."). Verified in `race_detail_screen.dart`.
- **OS-disabled push**: `sendPush` already no-ops gracefully; inbox
  unaffected; `in_app` prefs are independent of push prefs.
- **Cron cost**: due-job claim is one indexed UPDATE; minute cron at Nuvo's
  scale is trivial; job table is self-cleaning (delete `sent` > 30d in the
  existing purge pass).

---

## 12. Scenario simulation (policy applied before build)

**A. 3-person crew, moderate day.** crew_connect (2 inbox, 1 push each side),
1 race_invite push, ~2 overtake pushes, 1 proof_accepted push,
race_completed push at finish. **≈4–6 pushes/day.** Feels alive, not loud.

**B. 30-person crew, very active.** Naive = 29 join pushes + ~40 overtake
pushes. With policy: joins aggregate to ≤2/day ("Riley, Maya +3 joined…"),
overtakes limited to podium/crew-eligible + 2/hr/race + pair cooldown →
~6/day, proofs roll up to feed, `crew_day` ×1. **≈6–8 pushes/day, all
meaningful.** ✓

**C. Lead traders.** Trade 1,2 → overtake pushes. Trade 3+ → `lead_battle`
aggregate replaces further pair pushes for the day. **3 pushes, not 8.** ✓

**D. Inactive 5 days.** Only real pending items qualify: expiring invite or
race ending soon → exactly one `reengagement`/`finish` push. No real items →
**zero pushes.** Correct answer is zero. ✓

**E. 15 active races.** Per-race caps (2/hr competitive) + global ≤4/day
engagement ceiling → the 15th race's finish reminder may be the only one that
lands; all 15 still produce inbox rows. **≈4 pushes/day.** ✓

**F. OS-notifications off.** `sendPush` no-ops; `in_app` prefs still deliver
inbox + Crew feed. Nothing errors, nothing fake. ✓

**G. Sign-out → different account.** Token unregistered on sign-out; inbox
cleared via generation guard; with §10.1 fixed, a stale push tap stashes
through pending-destination or no-ops logged-out. No cross-account leak. ✓

**H. 200-person race.** A 40-position climb: only overtaken members who were
top-3/now-top-3/crew get pushed (≤ a handful); everyone else sees inbox/feed.
Fan-out is `INSERT…SELECT`, not 200 queries. **≈3–5 pushes total.** ✓

---

## 13. The product test

Every push in the catalog answers *what happened / why it matters / what can
I do*. "Riley just passed you 🔥 — You're 6 reps behind with 2 hours left" is
the canonical shape: real person, real event, real consequence, real action.
Anything that fails that test is `FEED_ONLY` by default.

## 14. Implementation phases

| Phase | Contents | Depends on |
|---|---|---|
| 0 — Wake push | `GoogleService-Info.plist`, `google-services.json`, APNs `.p8` in Firebase, `wrangler secret put FCM_SERVICE_ACCOUNT` + `FCM_PROJECT_ID` | External: Firebase project + Apple cert. Everything works in-app until then. |
| 1 — Policy + competitive core | `notificationPolicy.ts`, migration 0030 (priority/aggregate), overtake diff + `race_completed` on target-hit, `race_joined` aggregation, budget gates, `_routeFromMessage` auth fix | none |
| 2 — Scheduling | `notification_jobs`, minute cron, `race_starting`, `finish_line_close`, `race_deadline_finalize`, `invite_reminder`, `proof_needs_review` | phase 1 |
| 3 — Social depth | `invite_signup`, `crew_member_joined_race`, `lead_battle`, `crew_day`, `proof_submitted` feed rows, quiet hours + tz sync, badge, push-open beacon, prefs labels | phase 1–2 |
| 4 — Deferred | streaks (needs streak infra), reactions (needs feature), re-engagement digest (needs last-active), rich push media, experiments | product decisions |
