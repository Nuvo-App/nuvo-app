# 21 — Race System V2: Competition, Gameplay & Live Races (Agent 3)

**Status:** design complete, no code written. This is the reconnaissance +
domain design required by the Race System V2 PRD before implementation.

**Owner:** Agent 3 — why races themselves are fun.
**Feeds:** Agent 1 (Crew consumes §18 contract), Agent 2 (notifications
consume §19 event contract).

---

## Part 1 — Repository reconnaissance

### CURRENT RACE MODEL

`races` row (D1, post-0015 migrations):

| Field group | Columns |
|---|---|
| Identity | `id`, `title`, `description`, `creator_id`, `visibility`, `deleted_at` |
| Legacy shape | `race_type` (first_to_goal / most_in_window / best_attempt / timed_attempt / habit_check / daily_streak), `movement_type`, `verification_type` (movecheck / manual / note / link / photo / photo_video), `target_value`, `target_unit` |
| V2 shape | `activity_id`, `metric` (reps / seconds / minutes / miles / km / meters), `format` (first_to_goal / most_in_window / best_attempt / timed_attempt), `scoring_rule` (cumulative_sum / maximum_attempt), `attempt_duration_seconds`, `attempt_limit`, `verification_method`, `timezone`, `recurrence` (none / daily / weekly) |
| Time | `start_at`, `end_at`, `created_at`, `updated_at`, `completed_at` |
| Lifecycle | `status` (stored: draft / scheduled / active / completed / cancelled / archived), `winner_user_id` |
| Verifier binding | `verifier_type` (preset_pose / custom_pose_sequence / manual_log), `verifier_version`, `verifier_spec_json`, `custom_activity_name`, `verifier_release_id` |
| Live/demo | `live_mode`, `public_join_enabled`, `demo_world_seed` |

Related tables: `race_members` (role, status, cached name/avatar),
`race_progress` (progress_value, progress_percent, rank_cache, completed_at,
first_proof_at, last_proof_at), `move_logs` (proof ledger incl.
`previous_score`, `new_score`, `previous_rank`, `new_rank`,
`race_completed`, `client_submission_id`), `race_invites`,
`race_final_standings` (winner snapshot), `verification_sessions`,
`custom_verifiers`, `user_devices`.

**Key finding: the composable domain model the PRD asks for (§4) already
exists.** A race IS `activity × metric × format × scoring_rule ×
{start_at, end_at, recurrence} × {attempt params} × verifier`. The schema,
validation, and scoring already treat these as orthogonal fields. V2 does
not need a new model — it needs the missing machinery around this one.

### CURRENT LIFECYCLE

- `POST /races` always inserts `status='active'` — even with a future
  `start_at`. "Scheduled" is never stored; it is derived.
- `effectiveRaceStatus(status, start_at, end_at)` in
  `domain/raceLifecycle.ts` is the single derivation:
  stored terminal states pass through; `start_at > now` → `scheduled`;
  `end_at <= now` → `completed`; else `active`.
- Join (`POST /:id/join`, `/participants`, `/members`) checks the **stored**
  status (`=== 'active'`), so a scheduled race is joinable before its
  start line — correct behavior, arrived at accidentally.
- Proof (`POST /:id/proof`) checks `effectiveRaceStatus === 'active'` —
  correctly gates pre-start and post-deadline submissions.
- `POST /:id/move-log` checks only the **stored** status — it accepts
  logs on scheduled and window-expired races. Inconsistency, see §23.
- Completion (first_to_goal only): single conditional
  `UPDATE … SET status='completed', winner_user_id=? WHERE status='active'`
  → atomic winner. `race_final_standings` snapshot written in the same
  request.
- `PATCH /:id` lets the creator change `title`, `description`,
  `start_at`, `end_at`, `target_value`, `race_type`, `movement_type`,
  `verification_type`, `status`, `visibility` — **at any time, including
  mid-race**. Rules are not immutable today (PRD §40 violation).
- Cancel/archive/delete/leave/member-remove/invite-code all exist.
- **There is no scheduler for races.** The worker `scheduled()` cron only
  purges motion data. Nothing finalizes windowed races, emits
  `race_starting`, or advances lifecycle state. A `most_in_window` race
  whose `end_at` passes reads as `completed` via `effectiveRaceStatus` but
  has no winner, no `race_final_standings`, no `completed_at`, and no
  completion event.

### CURRENT WIN CONDITION

`domain/raceScoring.ts` — `applyVerifiedSubmission` is the canonical,
format-aware scoring function used by **both** write paths
(`POST /:id/proof` and `POST /:id/move-log` both call it via
`applyMoveProgress`):

- `cumulative_sum`: `newScore = prev + value`
- `maximum_attempt`: `newScore = max(prev, value)`
- `completed` is set only for `first_to_goal` when `newScore >= target`.

So: **first_to_goal has a real winner path; the other three formats score
but never complete.** Windowed and attempt formats have no winner
determination at all.

### CURRENT LEADERBOARD LOGIC

`domain/raceRanking.ts` — `computeCompetitionRanks` gives proper
competition ranking (1, 2, 2, 4 — shared ranks on ties). `recomputeRanks`
persists `rank_cache` on `race_progress` after every accepted submission.
`GET /races/:id` returns participants sorted by rank_cache with profile
joins. Arena snapshot builds mini-leaderboards (top 5 + viewer context)
from the same `rank_cache` ordering in one batched query.

Ranking already supports ties natively. There is no per-format
presentation differentiation client-side.

### CURRENT TIME MODEL

- `start_at`, `end_at`, `timezone` columns exist and are honored by
  `effectiveRaceStatus` and proof gating.
- Server timestamps are authoritative for accepted progress
  (`CURRENT_TIMESTAMP` on move_logs).
- `timezone` is stored but **never interpreted** — no per-zone day
  boundaries, no recurrence windows.
- `recurrence` (none/daily/weekly) is stored but **never interpreted**.
- No countdown, no "starts in", no start moment anywhere.
- PATCH allows editing `start_at`/`end_at` mid-race.

### CURRENT PROGRESS MODEL

- `race_progress`: cumulative `progress_value`, `progress_percent` (vs
  target), `rank_cache`, `completed_at`, `first_proof_at`,
  `last_proof_at`.
- `move_logs` is the proof ledger: source (movecheck/manual), value, unit,
  status (verified/removed), validator_version, duration_ms, metadata,
  `previous_score`/`new_score`/`previous_rank`/`new_rank`/`peoplePassed`
  derivable, `race_completed`, `client_submission_id` (idempotency —
  replay-safe retries).
- `submissionResult` in the proof response carries
  `{verifiedValue, previousScore, newScore, previousRank, newRank,
  peoplePassed, raceCompleted, winnerUserId}` — the client already gets
  its competitive delta in the submit response.

### CURRENT VERIFICATION MODEL

Three verifier classes, resolved at creation:

1. **Preset pose** — 22 activities in `domain/raceActivities.ts`, each
   with `supportedFormats`, `supportedMetrics`, `sessionBehavior`,
   camera orientation/framing, timeUnit. This IS the capability model
   (PRD §20) — already enforced: `configFromBody` rejects
   activity × format combinations not in `supportedFormats`.
2. **Custom pose sequence** (Teach Nuvo) — `custom_verifiers` +
   `verifier_spec_json` on the race; reps only; format locked to
   `first_to_goal` today.
3. **Manual log** — `verifier_type='manual_log'`, free-text unit,
   honor-based; supports all four formats in validation.

`verification_sessions` implements the release handshake (client asks
which verifier release to run; server pins `verifier_release_id` at race
creation via `stableReleaseForActivity`). Motion QA / control plane
exists (`docs/agents/*motion*`, `test/motion_qa/`).

### CURRENT CREATION FLOW

Flutter `RaceComposerScreen` steps: **name → activity → train (Teach Nuvo)
→ goal → racers → review**. `RaceDraft` carries
format/supportedFormats/attempt params and validates
activity×format client-side via the catalog — **but the UI never offers a
format choice**: `draftForActivity` / `parseRaceIdea` default to
`first_to_goal`. No scheduling UI, no end-date, no attempt params, no
"how do you want to race" step. `POST /races` already accepts the full
structured config (`activityId`, `metric`, `format`,
`attemptDurationSeconds`, `attemptLimit`, `startsAt`, `endsAt`,
`recurrence`, `timezone`) — the API is ahead of the UI.

### CURRENT LIMITATIONS (vs PRD)

| PRD concept | Reality |
|---|---|
| Most-by-deadline | Accepted, scored, **never finalized** — no cron closes the window, sets winner/standings, or emits events |
| Goal-by-deadline | Not expressible as distinct semantics (`first_to_goal` + `end_at` is closest; no "all finishers" completion handling) |
| Best attempt / timed battle | Stored format + `maximum_attempt` scoring exist; **no attempts lifecycle** — `attempt_duration_seconds`/`attempt_limit` are write-only columns, never enforced; no START ATTEMPT UX |
| Live race | Nothing: no session, lobby, ready state, countdown, synchronized start, or realtime channel |
| Head-to-head | Generic leaderboard for 2 people; no versus presentation |
| Daily / streak | `recurrence` column is dead; no day-boundary ledger |
| Teams / relay | Nothing (correctly deferred) |
| Domain events | `emitNotification` + categories exist; `race_starting`, `passed_on_leaderboard`, `race_completed` are **declared but never emitted**; no event log |
| Competitive context | Client-side `ChaseContext.compute` exists; no canonical server derivation |
| Live updates | REST only; pull-to-refresh + submit response. No WS/SSE/polling loop |
| Personal bests | Nothing |
| Rematch | Nothing (finish CTA is just "Start another race" → `/races/new` with no prefill) |
| Spectating | `GET /races/:id` performs **no membership check** — any authed user can read any race; informal spectating exists, no contract, and it's arguably a privacy gap |
| Rule immutability | PATCH can rewrite rules mid-race |
| Race analytics | Motion telemetry exists; no race funnel events |
| Cards by mechanic | All race cards/boards render identically regardless of format |

### REUSABLE INFRASTRUCTURE

- **Composable race schema + validation** (`raceValidation.ts`,
  `raceActivities.ts`) — the PRD's §4/§57 model, already deployed.
- **Canonical scoring** (`applyVerifiedSubmission`) + competition ranks
  with ties + rank deltas on the ledger.
- **Idempotent submissions** (`client_submission_id`) — offline-replay safe.
- **`effectiveRaceStatus`** — derived lifecycle, minimal persisted state.
- **Atomic first_to_goal completion** + `race_final_standings` snapshot.
- **Verification session handshake** + release pinning.
- **Notification substrate** (`emitNotification`, categories, dedupeKey,
  `NuvoDestination` routing) — Agent 2's sink; Agent 3 just has to emit.
- **Deep links / universal links / invite codes / QR** (migration 0014) —
  the SCAN TO JOIN flow needs only presentation work.
- **Arena snapshot endpoint** — already batched (2 queries), already
  returns viewer-relative boards; extend it, don't add N+1 endpoints.
- **`ChaseContext`** (client) — competitive-context concept, needs
  server-sourced numbers.
- **`submissionResult`** — rank reveal already flows to
  `BoardMovedScreen`.
- **Demo world** (`generateDemoSnapshot`) — can demo new modes without
  backend data.
- **TrackView** (`lib/features/arena/track_view/`) — fixture-driven racing
  visualization prototype; candidate live-race surface.
- **Manual races** — non-physical goals already raceable; V2 modes
  apply to them for free.

---

## Part 2 — Required design output

### 1. CURRENT STATE

See Part 1. Summary: the race system is a **capable async cumulative-score
engine** with a composable schema it doesn't fully use. Exactly one win
condition works end-to-end (first_to_goal). Everything the PRD calls
"new" is either half-built (windowed/attempt formats in schema+validation)
or absent at the UX layer (composer never exposes format, detail screen
has one leaderboard presentation).

### 2. PRODUCT PROBLEMS

1. **"Race" is a label, not a feeling.** Every race is the same
   cumulative-tally screen. First-to-100 and most-this-week are
   indistinguishable until you read the subtitle.
2. **Dead creation power.** API accepts four formats; UI offers one.
3. **Dead formats.** Three formats are accepted and scored but can never
   produce a winner.
4. **No time.** No start lines that mean anything, no countdowns, no
   deadlines that close, no shared moments.
5. **No finish.** Completion flips a status flag; there is no result
   ceremony, no rematch, no personal-best recognition.
6. **No events.** `Riley took the lead` exists in the data (rank deltas on
   move_logs) but is never emitted — Agents 1 and 2 have nothing to
   socialize.
7. **Silent fairness gaps.** Mid-race rule edits, no late-submission
   policy, no documented tie semantics.

### 3. EXISTING INFRASTRUCTURE TO REUSE

See Part 1 table. The single most important reuse decision: **keep
`applyVerifiedSubmission` + `effectiveRaceStatus` +
`computeCompetitionRanks` as the scoring/lifecycle core** and build
finalization, attempts, sessions, and events around them — do not
introduce a second engine.

### 4. PROPOSED RACE DOMAIN MODEL

Keep the existing composable row; formalize it as `RaceDefinition`:

```
RaceDefinition {
  activityId            // capability source (raceActivities / custom / manual)
  metric                // reps | seconds | minutes | miles | km | meters
  format                // first_to_goal | most_in_window | best_attempt | timed_attempt
  scoringRule           // cumulative_sum | maximum_attempt  (derived from format — never user-set)
  targetValue           // goal (first_to_goal, goal_by_deadline) or null
  timePolicy {          // NEW interpretation layer, existing columns
    startsAt            // start line (null = now)
    endsAt              // deadline (null = open-ended)
    liveWindowSeconds   // NEW: presence window for live races (nullable)
    recurrence          // none | daily | weekly (Phase I only)
  }
  attemptPolicy {       // attempt formats only
    durationSeconds     // attempt_duration_seconds — enforced in Phase D
    limit               // attempt_limit — enforced in Phase D
  }
  verificationPolicy    // verifier_type/version/spec — unchanged
  participantPolicy     // NEW: min/max (drives h2h presentation; future teams)
}
```

New persisted entities (additive, no schema break):

- `race_attempts` — id, race_id, user_id, attempt_index, client_attempt_id
  (idempotency), status (open/submitted/voided/expired), started_at,
  submitted_at, score, move_log_id. **Phase D.**
- `race_events` — append-only domain log: id, race_id, event_type,
  actor_user_id, subject_user_id, payload_json, created_at. **Phase A.**
- `race_member_state` — race_id, user_id, ready_at, finished_at,
  finish_rank. Lobby/ready + ordered finishes for live + multi-finisher
  races. **Phase F** (finished_at may land earlier in Phase B).
- `personal_bests` — user_id, activity_id, metric, best_value,
  race_id, set_at. **Phase H.**
- `races.is_live_session` (0/1) — marks a synchronized-presence race.
  **Phase F.**

### 5. PROPOSED RACE MODES

Modes are **human-language bundles over RaceDefinition**, not new formats:

| Mode (UI name) | Definition | Status |
|---|---|---|
| **First to goal** | first_to_goal + cumulative_sum + target | Works today |
| **Goal by deadline** | first_to_goal + cumulative_sum + target + endsAt; all finishers ranked by finish time, non-finishers by % | Phase B (near-free) |
| **Most by deadline** | most_in_window + cumulative_sum + endsAt | Phase C (needs finalizer) |
| **Best attempt** | best_attempt + maximum_attempt + optional attemptLimit | Phase D |
| **Timed battle** | timed_attempt + maximum_attempt + attemptDurationSeconds | Phase D |
| **Live race** | any verifiable format + startsAt + is_live_session + liveWindowSeconds | Phase F–G |
| **Head-to-head** | presentation variant: any mode with exactly 2 racers | Phase E |
| **Daily target** | daily recurrence + per-day ledger | Phase I (deferred) |
| **Teams / relay** | participantPolicy extension | Phase J (deferred) |

### 6. COMPATIBILITY MATRIX (activity × mechanic)

Derived from `activity.supportedFormats`/`supportedMetrics`/`sessionBehavior`
— already enforced server-side. Extend the catalog with
`supportsLiveSession` and `supportsAttempts`:

| Activity class | First to goal | Most/deadline | Goal/deadline | Best attempt | Timed battle | Live |
|---|---|---|---|---|---|---|
| Rep activities (pushups, squats, jacks, Teach Nuvo…) | ✓ | ✓ | ✓ | ✓ (max set) | ✓ | ✓ |
| Duration activities (plank, wall sit) | — | ✓ | — | ✓ (longest hold) | — | ✓ (hold-off, later) |
| Distance (running, treadmill) | ✓ | ✓ | ✓ | ✓ (fastest) | — | ✓ |
| Manual/honor goals | ✓ | ✓ | ✓ | — | — | — |
| Basketball shots (hidden) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

Composer derives this from catalog capabilities — no `if (activity == …)`
in UI code (PRD §20 already satisfied structurally).

### 7. LIFECYCLE / STATE MACHINE

Persisted status stays minimal (`active | completed | cancelled |
archived`; `scheduled` remains **derived** from `start_at`). Presentation
states derive from domain data — do not store them:

```
                 ┌──────────────────────────────────────────────┐
 created ──► scheduled* ──(start_at passes)──► active ──┬─► finishing** ──► completed
 (status='active',       (lobby/ready for     │         │  (windowed: cron    (winner +
  start_at future)        live races only)    │         │   finalizer)         standings,
                                             │         └─► completed          events)
                                             │              (first_to_goal
                                             ▼               atomic win)
                                          cancelled/archived
 * derived, not stored    ** derived for live (finishers done, window open)
```

Race member lifecycle (new, Phase F): `joined → ready → racing → finished`.
Only `ready_at`/`finished_at`/`finish_rank` persist.

### 8. SCORING RULES

Canonical engine = `applyVerifiedSubmission` (unchanged core) +
`computeCompetitionRanks`. All write paths already funnel through it.
Additions:

- **Finalizer (Phase A/C):** cron sweeps `status='active' AND
  effectiveStatus='completed' AND end_at IS NOT NULL` → for windowed
  formats, freeze standings via `computeCompetitionRanks`, write
  `race_final_standings`, set `winner_user_id` = top rank (null if all
  tied at 0), `status='completed'`, `completed_at`, emit events. Idempotent:
  skip if `completed_at` set.
- **Attempt scoring (Phase D):** submission carries `attempt_id`; engine
  applies `maximum_attempt`; `attempts_used` enforced server-side against
  `attempt_limit`.
- **Goal-by-deadline:** `completed` means individual finished
  (`score >= target`) OR window closed. `finished_at` per member orders
  finishers; unfinished ranked by score. Standings: finishers by
  finished_at, then non-finishers by score.
- **Rank direction:** `lowest_wins` needed for fastest-time metrics
  (fastest mile) — add `score_direction` to catalog metric metadata
  (time metrics sort ascending) in Phase D; `computeCompetitionRanks`
  takes a comparator.

### 9. TIME / DEADLINE RULES

- Server clock is the only authority. Clients render `serverTime` deltas;
  countdowns are presentation-only.
- Proof eligibility: `received_at <= end_at` OR (`capturedAt <= end_at`
  AND `received_at <= end_at + 24h grace`). `capturedAt` is
  client-reported — sanity-check `|received - captured| <= 24h` to bound
  clock manipulation. Document as accepted risk; revisit if abuse appears.
- Submissions during `scheduled` are rejected (already enforced on
  `/proof`; fix `/move-log` to use `effectiveRaceStatus` — Phase A bugfix).
- `start_at`/`end_at` become immutable once the race is active (§10).
- DST/timezone: only matters for recurrence (Phase I); defer zone-day
  boundaries until then. All stored timestamps remain UTC ISO.

### 10. TIE / FAIRNESS RULES

- **First to goal:** earliest verified completion wins (atomic UPDATE —
  already correct). Simultaneous finish: first committed write wins;
  runner-up keeps `finished_at` for standings.
- **Most/best-attempt by deadline:** shared rank = shared placement
  (competition ranking already does this). Tied #1 → display "TIED FOR
  1ST", `winner_user_id` stays NULL, standings mark all leaders. **No
  hidden tiebreaker.**
- **Goal by deadline:** all finishers share "finished" status; rank by
  `finished_at`, ties share rank.
- **Live:** `finish_rank` assigned at `finished_at` commit order.
- **Immutable rules (PRD §40):** once `first_proof_at` exists (or
  `start_at` passes for scheduled races), PATCH rejects changes to
  `format`, `metric`, `target_value`, `scoring_rule`, attempt params,
  `start_at`, `end_at`. Title/description/visibility always editable.
  Cancel always allowed.
- **Late joins:** allowed while `effectiveStatus='active'` (current
  behavior); for `is_live_session` races, joins close at `start_at`.
- **Leaves/removals:** existing member status changes; finished members
  keep standings rows.

### 11. VERIFICATION INTEGRATION

- Preset/custom/manual verifier paths unchanged.
- `verification_sessions` handshake extends: for `timed_attempt` and
  live races the session response carries `attemptPolicy` (duration,
  count rules) so the camera runs the right referee mode — session is
  already the natural "start attempt" handshake point.
- Custom (Teach Nuvo) verifiers graduate: today locked to
  `first_to_goal`; spec provides rep events → supports most_in_window,
  best_attempt, timed_attempt once attempts exist. Capability flag on
  the custom spec: `supportsAttempts: true`.
- Competition camera overlay (Phase G): own count, rank vs chaser,
  time/distance remaining — minimal competitive HUD, not the full board.

### 12. LIVE ARCHITECTURE

Semantics (PRD §9) — three distinct products, named precisely:

1. **Synchronized live** — lobby → ready → 3-2-1-GO → race together.
   `is_live_session=1`, `startsAt` = go time, `liveWindowSeconds` = max
   session length. Phase F–G.
2. **Live window** — race open 7–8 PM, start anytime inside. This is just
   `startsAt`+`endsAt` + tighter window; no new machinery. Phase C free.
3. **Head-to-head session** — synchronized live with `maxParticipants=2`.
   Same machinery, versus presentation (Phase E).

Realtime decision: **start with 2–3s client polling, not sockets.**
Physical races tolerate multi-second board lag; the user's own count is
on-device and instant regardless. Contract:

```
GET /races/:id/live → {
  serverTime, status, startsAt, endsAt,
  version,                      // etag-ish counter for cheap 304-style skips
  participants: [{userId, name, avatar, score, rank, progress, finishedAt}],
  viewer: {rank, gapToLeader, gapToNext, goalRemaining, isLeading, isFinished}
}
```

`version` bumps on any move_logs/members write for the race — polls with
unchanged version return `{version}` only. If polling proves insufficient
for synchronized starts, a per-race Durable Object is the upgrade path —
decision point at Phase G, not before.

### 13. CREATION UX

Add one step between **activity** and **goal**: *"How do you want to
race?"* — human-language cards filtered by `activity.supportedFormats`
(+ capabilities):

- 🏁 **First to a goal** — "First to 100 pushups" → then goal step
- ⏱ **Most before time's up** — "Most by Friday" → then deadline step
- 🎯 **Best attempt** — "Best 60-second score" → duration/limit step
- ⚡ **Live** — "Do it together" → pick a start time (Phase F)

Keep goal/racers/review steps; review shows the mode in plain language
("First to 100 · starts when you create"). Existing prefill/idea-parse
paths map onto modes unchanged. Quick-race path (PRD §55): `+ Race` on a
person/crew preselects participants — Phase E companion.

### 14. ACTIVE RACE UX

Race detail composes mode-specific sections over shared primitives:

- **First to goal:** today's layout is already close — progress bars + "N
  to go" chase copy. Keep; add finished-order markers for finishers.
- **Most by deadline:** header carries "ENDS IN 2D 4H"; rows show score +
  "1.5 mi to take 1st" gap copy from viewerContext.
- **Goal by deadline:** finisher checkmarks + your progress bar +
  deadline.
- **Best/timed attempt:** rows show best score; CTA is "START ATTEMPT"
  not "Verify now"; attempts-remaining chip ("2 attempts left").
- **Head-to-head:** versus layout — YOU 74 VS RILEY 81, gap line
  ("7 reps behind"), shared progress bar pair. Derived purely from
  member count == 2; zero domain change.
- Chase copy moves to server-derived `viewerContext` numbers; copy stays
  client-side (Nuvo language lives in the app).

### 15. LIVE RACE UX

- **Pre-race (scheduled, is_live_session):** lobby — participant avatars,
  ready states ("Riley is ready ✓"), countdown to `startsAt`, rules card.
  "I'm ready" writes `race_member_state.ready_at`.
- **Start:** at `startsAt` all ready clients get countdown (polled/live
  payload `status:'starting'`); 3-2-1-GO transition with haptic into the
  verifier. Non-ready members race as normal joiners (no DQ — Nuvo is
  friendly, not esports).
- **During:** live payload polling; HUD = own count + chasing gap +
  finishers list ("Riley finished 6:42"). Leaderboard = race-position
  bars.
- **Your finish:** placement card ("YOU FINISHED #2 · 6:58 · +16s
  behind Riley"), then spectate remaining racers or exit.
- **Finish:** last finisher or `liveWindowSeconds` expiry → completed.

### 16. FINISH / RESULT UX

- `race_final_standings` snapshot already exists — render staged result:
  placement → score → full standings → gap line → actions
  (**Share result**, **Race again**, **View results**). Replaces today's
  flat "Final standings" section for completed races.
- **Rematch** (`POST /races/:id/rematch`, Phase H): creates a new race
  cloning `RaceDefinition` + member list (invite status), emits
  `rematch_requested`. Prefill-only; editable before create.
- **Share card:** design data contract now (placement, score, standings
  top-3, activity, race title) — image generation is a separate
  infrastructure decision; do not block on it.
- **Personal bests:** `personal_bests` written by the scoring engine when
  a maximum_attempt score improves the user's record for
  (activity, metric). Profile "Recent races" consumes standings +
  bests (PRD §32–34).

### 17. ARENA / COMPETE IMPACT

- **Arena** groups by attention, derived server-side into the snapshot
  (keep the client dumb):
  `LIVE NOW` (is_live_session, active window) → `YOUR RACES` (needs proof
  / starting soon within 24h) → `STARTING SOON` → `FINISHED` (recent
  results). Extends today's focusBoard/liveBoards/results — one added
  bucket field per board, not a rewrite.
- **Race cards** differentiate by mechanic through content, not badges:
  countdown chip for scheduled/live, "ENDS IN" for windowed,
  best-score rows + attempts chip for attempt modes, versus rows for h2h.
  `badgeLabel`/`proofLabel`/`progressLabel` fields already exist on
  ArenaBoard — the snapshot fills them mode-aware.
- **Compete** stays creation + join per product model; quick-race entry
  point lands there.

### 18. CREW INTEGRATION CONTRACT (→ Agent 1)

Race system exposes; Crew renders:

- `GET /crews/:id/activity` already exists; add race items:
  `{type:'race_live'|'race_result'|'lead_change'|'rematch', raceId,
  title, participants[{id,name,avatar}], summary, occurredAt}`.
- Lightweight spectator read: existing `GET /races/:id` (already
  unauthenticated-member-free) → formalize `viewer:{isSpectator:true}`
  in response; Crew deep-links to it. No streaming video — spectating =
  live scores.
- Crew surfaces get the same `CompetitiveContext` numbers via the
  events feed, not by recomputing.

### 19. NOTIFICATION EVENT CONTRACT (→ Agent 2)

`race_events` rows are the canonical source; `emitNotification` calls
become subscribers. Emit (dedupeKey'd):

`race_created` · `race_invited` ✓exists · `race_joined` ✓exists ·
`race_scheduled` · `race_starting` (T-15min + at-start, cron) ·
`race_attempt_started` · `race_progress_milestone` (25/50/75%) ·
`rank_changed` (viewer lost position) · `lead_changed` (new #1) ·
`participant_finished` · `race_finished` · `race_won` · `personal_best` ·
`rematch_requested`

Categories `race_starting` / `passed_on_leaderboard` / `race_completed`
already exist in `notifications.ts` — Agent 2 owns which interrupt;
Agent 3 only guarantees the events fire once, with entity refs +
payloads.

### 20. BACKEND CHANGES

Phase-grouped, all additive:

- **A:** `race_events` table + emit helper inside `applyMoveProgress`/
  lifecycle transitions; finalizer cron in `scheduled()`; `/move-log`
  effective-status fix; PATCH immutability guard; `viewerContext` in
  `buildRaceResponse`; `version` counter on races.
- **B:** `race_member_state.finished_at`; goal-by-deadline finalizer
  ordering; multi-finisher standings.
- **C:** (nothing new — A's finalizer + endsAt semantics).
- **D:** `race_attempts` + `POST /:id/attempts` +
  `POST /:id/attempts/:aid/submit`; enforce `attempt_limit`/
  `attempt_duration_seconds`; `score_direction` on metrics.
- **E:** nothing (presentation derives from member count).
- **F:** `is_live_session`, `liveWindowSeconds`, `ready_at`,
  `POST /:id/ready`, live payload endpoint + version counter, join-close
  at start.
- **G:** polling client contract only; DO escalation optional.
- **H:** `personal_bests`, `POST /:id/rematch`, result-share payload.
- **I:** recurrence day-ledger (`race_progress_periods`) — deferred
  design-in-place.

### 21. FLUTTER CHANGES

- **A:** consume `viewerContext` (replace `ChaseContext.compute` input);
  mode-aware card fields from snapshot.
- **B/C:** deadline headers, finisher markers, "N to take 1st" gaps,
  "ENDS IN" chips.
- **D:** attempts UI — START ATTEMPT → verifier with attemptPolicy →
  score reveal; attempts-remaining chip.
- **E:** versus layout component (member count == 2).
- **F:** lobby + ready + countdown + scheduled-race detail state.
- **G:** live HUD polling loop; post-finish spectate state; TrackView is
  the candidate surface for race-position visualization.
- **H:** staged result flow, rematch CTA + prefilled composer, share-card
  payload consumption, profile recent-races/personal-bests.
- **Composer:** mode-picker step (§13) + scheduling + deadline +
  attempt params — all gated by catalog capabilities.

### 22. MIGRATION PLAN

- Every existing race maps to `format` already (column co-stored); all
  legacy races = `first_to_goal`/cumulative — no data migration needed.
- `race_type` legacy values (habit_check, daily_streak) remain stored;
  `format` column is the read-side source of truth going forward.
- Old clients: new columns/fields are additive; `format` already
  serialized. Old clients see new-mode races as ordinary races with
  scores — degraded but functional. New-mode CTAs simply don't render
  on old clients.
- Deep links: `/race/:id` routes unchanged; `invite_code` flow unchanged.
- The PATCH immutability guard is the only behavior tightening — flag in
  release notes; low risk (rarely used legitimately mid-race).

### 23. PERFORMANCE RISKS

- **Finalizer cron volume:** bounded by `end_at` sweep; D1 batch per
  race. At 200-person races (Sim H) finalization is O(participants) —
  fine.
- **Live polling:** `version` counter makes unchanged polls cheap
  (single indexed read). Poll interval 3s, only while live screen
  visible.
- **Leaderboard recompute:** `recomputeRanks` is O(participants) per
  accepted submission — already the case; rank events add an INSERT.
- **N+1 avoidance:** keep extending `buildRaceResponse`/arena snapshot
  batched queries; do NOT let Crew/notifications fan out per-member
  reads — events carry denormalized display payloads.
- **move_logs growth:** unchanged; attempt races add rows per attempt
  (bounded by attempt_limit).

### 24. TEST MATRIX

- Domain: scoring per format, tie ranking, finalizer idempotency,
  attempt limit/duration enforcement, immutability guard, late-proof
  grace window, join-close for live, ready-state transitions,
  personal-best updates, rematch clone.
- API: each mode create → join → submit → finish → events → standings.
- Flutter: mode-aware cards, versus layout, lobby/countdown, attempt
  flow, result ceremony, rematch prefill.
- Regression: existing `custom_race_persistence_test`,
  `race_progress_route_test`, arena tests must stay green — extendBody
  nav work already proved the suite catches layout drift.

### 25. PHASED IMPLEMENTATION PLAN

| Phase | Scope | PRD modes unlocked |
|---|---|---|
| A | race_events + finalizer cron + immutability + move-log status fix + viewerContext | (foundation) |
| B | goal-by-deadline (finished_at, finisher ordering) | "100 pushups by Friday" |
| C | most-by-deadline UX + cards | "Most miles this week" |
| D | attempts lifecycle + timed battle + score_direction | "60-sec battle", "fastest mile" |
| E | head-to-head presentation + quick-race entry | "Me vs Riley" |
| F | scheduled lifecycle: lobby, ready, race_starting | "We're all on at 7" |
| G | live payload, polling, competition HUD, TrackView | Live races feel live |
| H | result ceremony, rematch, personal bests, share payload | Finish worth sharing |
| I | recurrence/daily ledger | "50 every day" |
| J | teams/relay | Only if A–I prove the loop |

---

## Part 3 — The ten simulations

**A — First to 100 pushups, 3 async racers:** today + Phase A events
(rank_changed/lead_changed emit from move_logs deltas) + Phase H finish.
Works with zero schema change.

**B — Most miles this week, 20 users, multi-TZ:** endsAt is absolute UTC —
TZ-independent. Finalizer cron closes window, competition ranks handle
ties, race_final_standings snapshot, race_finished/race_won emit. ✔ Phase C.

**C — Live 1-mile, 4 racers, one drops mid-race:** lobby+ready+countdown;
dropper keeps last verified score, race continues; liveWindowSeconds caps
the session; finishers get finish_rank; race completes on last-finish or
window. Reconnect = poll resume. ✔ Phase F–G.

**D — 60-sec pushup battle, 2 racers, Motion verification:** attempt
session carries attemptPolicy; on-device count is instant; submit locks
score via maximum_attempt; attempts-remaining enforced; versus layout;
lead_changed emits on max updates. ✔ Phase D–E.

**E — Fastest mile, multiple attempts:** best_attempt + score_direction
ascending (time metric) + attempt_limit; personal_bests records each
improvement; "16 sec to take 1st" from viewerContext. ✔ Phase D/H.

**F — Daily 50 pushups, one misses day 4:** requires day-boundary ledger —
explicitly Phase I; model reserved (`race_progress_periods`,
recurrence semantics defined) so it slots in without breaking A–H.

**G — Head-to-head with repeated overtakes:** versus presentation +
rank_changed events; each overtake is a socializable moment for Agents
1–2. ✔ Phase E.

**H — 200-person race:** scoring O(1) per submission + O(n) recompute
(already); finalizer O(n); events batched; live payload compact. Main
risk = notification fan-out — Agent 2's batching problem, events provide
the hook. ✔ architecture holds.

**I — Teach Nuvo first to 50:** already works (custom verifier,
first_to_goal). Unlocks most_in_window/timed_attempt once attempts ship
(spec gains `supportsAttempts`). ✔ Phase D.

**J — Race ends while proof pending:** proof accepted iff
`received ≤ end_at` OR (`capturedAt ≤ end_at` AND `received ≤ end_at+24h`).
Late-accepted proof still lands in standings recompute **before** the
finalizer runs (finalizer skips races < end_at+grace). After finalizer:
late proofs are recorded on the ledger but do not alter standings —
standings are immutable once snapshotted. ✔ deterministic.

---

## Decision log (what this design deliberately does NOT do)

- No second scoring engine, no rules DSL — composable columns + format
  bundle is the smallest sufficient architecture (PRD §57).
- No WebSockets/SSE yet — polling first; Durable Objects are the
  documented upgrade path if synchronized-start latency demands it.
- No spectator video, no tournaments, no teams/relay, no wagers (PRD §66).
- No stored 'scheduled'/'finishing'/'starting' statuses — derived only.
- No client-side race truth — timers, ranks, winners all server-derived.
