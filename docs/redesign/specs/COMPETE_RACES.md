# COMPETE_RACES.md — v13 spec mapping

Phase A documentation for the Compete tab, New race composer, Race detail, and
the Submit proof bottom sheet. Maps every v13 element to the current code and
the deployed Worker contract. Read-only; nothing here changes code.

**v13 source:** `docs/redesign/PROTOTYPE_V13_SPEC.md` sections "Compete tab"
(L45-52), "New race (composer, 4 steps)" (L54-59), "Race detail" (L61-64),
"Arena tab" item 8 "Submit proof bottom sheet" (L37-43).

**Current surfaces:**

| v13 surface | Current code |
|---|---|
| Compete tab | `lib/features/compete/presentation/compete_screen_fixed.dart` (route `/compete`, `router.dart:91`) |
| New race composer | `lib/features/races/presentation/race_composer_screen.dart` (route `/races/new`, `router.dart:304-314`) |
| Join a race (code) | `lib/features/races/presentation/join_race_screen.dart` (route `/races/join`, `router.dart:315-318`) |
| Invite friends (post-create) | `lib/features/races/presentation/invite_crew_screen.dart` (route `/race/:id/invite`, `router.dart:362-368`) |
| Race detail | `lib/features/race_detail/presentation/race_detail_screen.dart` (route `/race/:id`, `router.dart:342-348`) |
| Submit proof | `lib/features/races/presentation/submit_proof_screen.dart` (route `/race/:id/proof`, `router.dart:370-374`) — full screen today, not a sheet |
| AI Motion Proof | `lib/features/races/presentation/ai_motion_proof_screen.dart` (route `/race/:id/proof/ai-motion`, `router.dart:377-381`) — **no-touch** |
| Post-proof payoff | `lib/features/races/presentation/board_moved_screen.dart` (route `/race/:id/board-moved`, `router.dart:384-398`) |
| Race settings | `lib/features/races/presentation/race_settings_screen.dart` (route `/race/:id/settings`, `router.dart:349-355`) |
| Proof review | `lib/features/races/presentation/proof_review_screen.dart` (route `/race/:id/proofs/:proofId`, `router.dart:399-408`) |
| Teach movement | `lib/features/races/presentation/custom_pose/teach_movement_screen.dart` (route `/races/teach`, `router.dart:321-335`) |

Data layer: `race_api.dart` (HTTP), `race_models.dart` (DTOs),
`race_repository.dart` (token injection — **do not casually touch**),
`race_controller.dart` (`raceControllerProvider`, shared state — **do not
casually touch**). Domain: `race_draft.dart`, `race_mode_semantics.dart`,
`race_name_interpreter.dart`, `race_display.dart`,
`motion_activity_catalog.dart`, `teachable_movements.dart`.

---

## 0. Backend capability matrix (verified in `server/worker/src`)

### Race modes — all four v13 modes exist today

| v13 mode | Dart enum (`motion_activity.dart:253-257`) | Backend `format` | Scoring (`domain/raceScoring.ts`, mirrored `race_mode_semantics.dart:34-37`) |
|---|---|---|---|
| first to | `RaceFormat.firstToGoal` | `first_to_goal` | `cumulative_sum`, target decides winner |
| most total | `RaceFormat.mostInWindow` | `most_in_window` | `cumulative_sum`, deadline decides |
| best single | `RaceFormat.bestAttempt` | `best_attempt` | `maximum_attempt` (or `minimum_attempt` when `scoreDirection='lower'`) |
| (extra) timed battle | `RaceFormat.timedAttempt` | `timed_attempt` | max/min within `attemptDurationSeconds`; requires `POST /races/:id/attempts` |

### Durations

- Composer deadline chips today: **1 hour, 24 hours, 3 days, 1 week**
  (`race_composer_screen.dart:3311-3316` `_deadlineOptions`). v13 wants
  **today, 3 days, 1 week, 2 weeks** → client-only chip change; `finishLineAt`
  ISO is already the wire field (`races.ts:1418,1428-1429`,
  `validateRaceWindow` enforces finish > start for deadline formats).
- Attempt-length chips: 30s / 60s / 2 min / 5 min
  (`race_composer_screen.dart:3318-3323`) — no v13 equivalent; keep only if
  `timedAttempt` survives.
- Name interpreter already parses deadline phrases ("by Friday", "in 2
  weeks", "tonight") into `FlexiRaceInterpretation.deadline`
  (`race_name_interpreter.dart:95-100`), resolved by
  `deadlineUtcFromPhrase` (`race_draft.dart:423-424`).

### Movements list + custom movements

- Bundled preset catalog: 23 `MotionActivityDefinition` entries
  (`motion_activity_catalog.dart:6-664`): pushUps, jumpingJacks, squats,
  lunges, plankHold, highKnees, armRaises, sumoSquats, sideLunges, deepSquats,
  squatJacks, jumpSquats, lungeJumps, runningInPlace, treadmillRunning,
  walkingInPlace, marchingInPlace, buttKicks, mountainClimbers, burpees,
  stepUps, calfRaises, lateralSteps, basketballShot.
- Server catalog: `GET /races/activities` (`index.ts:236-315`, public, ETag'd)
  returns `{supported, activities:[{id, displayName, suggestedTargets,
  supportedFormats, featured, sortPriority, currentReleaseId,
  previewSequence, instructions, cameraOrientation, aliases}]}`. Consumed by
  `motionCatalogProvider`; merged in `availableMotionActivities`
  (`submit_proof_screen.dart:58-62`).
- Custom movements: Teach Nuvo (`/races/teach`) records 3 demos →
  `CustomPoseVerifierSpec` / `TaughtMotionV2Spec` → `POST /races` with
  `verifierType`/`verifierSpec` (`race_api.dart:640-692` `createCustomRace`).
  Gated by `GET /config` `custom_motion` flag (`index.ts:85-129`,
  `NuvoFlags.customMotionOn`). Teachable-name list:
  `teachable_movements.dart:37-94` (~55 rep/hold names).
- v13 grid (Pushups, Squats, Jumping jacks, Plank + custom) is a subset —
  KEEP the catalog pipeline, restyle presentation.

### Endpoint inventory used by these surfaces

| Endpoint | File:line | Used for |
|---|---|---|
| GET `/races` | `races.ts:1217-1294` | Compete list (creator or member only — `WHERE r.creator_id = ? OR rm.user_id IS NOT NULL` at :1222) |
| POST `/races` | `races.ts:1326-1590` | Composer create. Accepted fields: `title`, `description`, `goalType`, `category`, `customActivityName`, `proofRequirement`, `activityId`/`aiActivityType`, `metric`, `targetValue`, `unit`, `targetUnit`, `format`, `recurrence`, `startLineAt`, `finishLineAt`, `attemptDurationSeconds`, `attemptLimit`, `scoreDirection`, `proofReviewMode`, `proofMode`, `verifierType`, `verifierVersion`, `verifierSpec`. **No `participantIds`, no `color`, no `rules` in the INSERT (:1467-1502)** |
| GET `/races/:id` | `races.ts:1593-1640` | Race detail; emits `viewerContext` (rank, previousRank, leaderScore, viewerScore, gaps, timeRemainingSeconds — `race_models.dart:450-519`) on single-race reads |
| PATCH `/races/:id` | `races.ts:1642-1772` | Race settings (creator). `visibility` deliberately not writable (:1759) |
| POST `/races/:id/archive` `/cancel` | `races.ts:1790-1791` | Lifecycle actions |
| DELETE `/races/:id` | `races.ts:1794` | Delete (creator) |
| POST `/races/:id/leave` | `races.ts:1804` | Leave race |
| POST `/races/:id/join` | `races.ts:1819` | Join (crew-scope/invite access via `resolveRaceAccess`) |
| POST `/races/:id/participants` | `races.ts:1838` | Add one user `{userId}` — the per-friend invite write |
| POST `/races/:id/members`, DELETE `/races/:id/members/:userId` | `races.ts:1884,1930` | Member add/remove |
| POST `/races/:id/invite-code`, POST `/races/join-code` | `races.ts:1947,1183` | Typable invite codes |
| POST `/races/:id/proof` | `races.ts:2028-2440` | ALL proof (manual + AI Motion). Response `{ok, race, submissionResult}` (:2111,:2205,:2440) |
| POST `/races/:id/proof-media/upload-url`, PUT `.../proof-media/upload` | `races.ts:2445,88` | Photo evidence upload (R2 signed URL) |
| GET `/races/:id/proofs`, PATCH `/races/:id/proofs/:proofId` | `races.ts:2506,2574` | Proof list + creator review (`accepted`/`rejected`/`ai_verified`) |
| POST `/races/:id/proofs/:proofId/veto` | `races.ts:2672` | Community veto |
| POST `/races/:id/attempts` | `races.ts:2770` | Open server-timestamped attempt (best/timed races) |
| GET `/races/:id/events`, GET `/races/:id/live` | `races.ts:2832,2873` | Event feed + version-gated live poll (`?version=`) |
| POST `/races/:id/rematch` | `races.ts:2958` | One-tap rematch |
| GET `/crew` | `crew.ts:67` | Friend list → composer invite step + InviteCrewScreen |
| GET `/users/search?q=` | `users.ts:20` | Username search in invite screen |
| GET `/arena` | `arena.ts:127-163` | Arena snapshot (mode/headerPulse/focusBoard/liveBoards/activity/results) — Arena's data, not Compete's |
| GET `/races/activities` | `index.ts:236` | Movement catalog (unauthenticated) |

---

## 1. Compete tab (v13 L45-52)

> **Product-model conflict up front:** `NUVO_PRODUCT_MODEL.md:80,239-243` —
> "Compete: start a race or join a race", "Compete must not show active race
> lists" and not "leaderboard views". The v13 spec puts Live races cards, a
> Leaderboard, trending moves and a trophy shelf on Compete, and the current
> screen *already* lists active races (`compete_screen_fixed.dart:121-133`).
> **Proposed resolution:** the v13 spec is the target design; treat its
> "Live races" as swipe cards (not a full list) and keep the rule's intent —
> no management actions, no filters, everything funnels to Start/Join or
> Race detail. Flag to the user: this is a genuine spec-vs-rules conflict,
> not an oversight.

### 1.1 Header "Compete" + blue "New race" button

- **Current:** `_CompactHeader` — title "Compete", summary line
  "N active · M finished", `Start` (primary) + `Join` (outline) buttons
  (`compete_screen_fixed.dart:285-383`; pushes `/races/new` :97,
  `/races/join` :99).
- **Verdict:** REPLACE styling. Rename `Start` → "New race" (blue), demote
  `Join` to the section below (v13 has "Join a race" cards, no header Join).
- **Data:** none beyond `raceControllerProvider` counts.
- **States:** default; first-race guide coach overlay
  (`FirstRaceGuideStep.competeStart`, :222-235) — keep hook.

### 1.2 "Live races" swipe cards (250 px)

v13 card: race color strip, name, time left, your rank and trend, progress
bar, faces of racers in rank order. Tap → Race detail.

- **Current:** vertical `_CappedRaceList` of `NuvoRaceRow`s inside a white
  field card, capped at 3 + "See all" (`compete_screen_fixed.dart:388-596`).
  Rows already carry: title, movement label, progress label/percent,
  rank, avatars, "X left", status pill, track markers, gap/context line
  (:548-576, helpers `race_display.dart`).
- **Verdict:** REPLACE layout → horizontal snap swiper (same physics as the
  Arena race swiper in the spec — reuse one card component if a shared one
  lands in the Arena spec; otherwise new `LiveRaceCard` widget).
- **Data per card:**
  - name/progress/faces/rank — `GET /races` `participants[]`
    (`rank_cache`, `progress_value`, `profile_photo_url`) — HAVE.
  - time left — `race.finishLineAt` + `viewerContext.timeRemainingSeconds`
    (detail reads only) or `ChaseContext.timeLeft`
    (`race_detail_screen.dart:614`) — HAVE for deadline races.
  - **race color** — MISSING. No `color` column in `races` table, no field
    in `buildRaceResponse`, nothing in `race_models.dart`. **Proposed
    (no backend change):** deterministic client palette —
    `hash(race.id) % 5` over the v13 race palette (coral/sun/lilac/mint/sky,
    spec L8). Additive alternative if persistence is wanted later: nullable
    `races.color` TEXT column + `color` in `POST /races`/`PATCH`/`buildRaceResponse`.
  - **trend** (rank movement arrow) — MISSING on list payloads.
    `RaceViewerContext.previousRank` exists (`race_models.dart:455,499`)
    but `viewerContext` is emitted only on `GET /races/:id` detail reads,
    not in `GET /races` rows. **Proposed additive API:** include a light
    `viewerRank`/`previousRank` pair per race in `GET /races`
    (server already stores `previous_rank` on `move_logs` — see
    `races.ts:2102-2105`). Cheap alternative: derive trend from the latest
    `move_logs` row's `previous_rank`/`new_rank` — still needs the field
    exposed in the list payload, so same additive ask.
- **States:** loading skeleton (`_CompeteSkeleton` :759); empty → keep
  `_EmptyState` (:801) restyled; error → `NuvoErrorState` (:109); 1-2 races
  (swiper with partial fill); >cap races (spec shows swipe, no "See all"
  needed if all cards are in the swiper — flag decision).

### 1.3 "Join a race" cards — open races from friends

v13: cards showing races your friends created that you haven't joined, with
faces, "Maya, Theo and Noah", a Join button → "Joined" + confetti + toast.

- **Current:** none. Join exists only via invite code
  (`join_race_screen.dart` → `POST /races/join-code`), invite link
  (`POST /invites/:token/accept`), or direct add by a participant
  (`POST /races/:id/participants`).
- **Verdict:** NEW (backend + UI).
- **Data:** MISSING — `GET /races` filters to creator/member
  (`races.ts:1222`). Crew-scope visibility *does* make friends' races
  readable (`resolveRaceAccess` returns level `crew`,
  `raceAccess.ts:19,32-36`), so access rules already permit this.
  **Proposed additive API:** `GET /races/open` (or `GET /crew/races`) —
  races `WHERE r.deleted_at IS NULL AND r.status='active' AND r.creator_id
  IN (SELECT crew_user_id FROM crew_connections WHERE user_id=? AND
  status='active') AND NOT EXISTS (member row for me)`, each row carrying
  id, title, format, metric, target_value, end_at, participant faces +
  count, creator name. Then `POST /races/:id/join` (exists, `races.ts:1819`)
  performs the join.
- **States:** loading; empty (hide section entirely — dead-UI rule);
  joining (button spinner); joined (swap to "Joined" pill, confetti,
  toast) — confetti is hand-rolled `_Burst` CustomPainter
  (`board_moved_screen.dart:351-401`), no `confetti` package in pubspec;
  join-error (toast + revert).

### 1.4 Leaderboard — global/friends

v13: open rows — rank, photo, name, points; your row tinted; no split
header; tap → profile.

- **Current:** none anywhere in the app.
- **Verdict:** NEW (backend + UI).
- **Data:** MISSING. No global-leaderboard endpoint exists. Closest server
  assets: `progression` (Nuvo Levels/XP, `routes/progression.ts`,
  `GET /progression`), `squadStandings.ts` (crew-scoped standings only),
  `win` data implicit in `race_final_standings`.
  **Proposed additive API:** `GET /leaderboard?scope=friends` —
  aggregate `race_final_standings` (wins weighted by rank) or XP from
  progression for `me + crew_connections`, returning
  `{rank, userId, displayName, profilePhotoUrl, points}` sorted, with my
  absolute rank even when outside top-N. A `scope=global` variant is a
  product decision — flag (privacy: everyone is visible per product model,
  so global is legal by policy but needs UX sign-off).
- **States:** loading; empty (fewer than ~3 ranked users → hide or
  collapsed message); self-highlighted; tap row → `/u/:id`
  (`router.dart:146-151` exists).

### 1.5 Trending moves

v13: small cards — movement icon tile, "[N] racing", "Start" → New race
prefilled.

- **Current:** none. (`recentMovementIdsProvider` shows the user's own
  recent movements inside the composer, `race_composer_screen.dart:563-568`
  records on create — different concept.)
- **Verdict:** NEW.
- **Data:** PARTIALLY MISSING. Catalog gives candidates
  (`featured`, `sortPriority` flags already in `GET /races/activities`,
  `index.ts:264-265`) but "[N] racing" needs a cross-user count — nothing
  aggregates it. **Proposed additive API:** add `activeRaceCount` (or
  `racerCount7d`) per activity to `GET /races/activities` response —
  `SELECT activity_id, COUNT(*) FROM races WHERE status='active' AND
  deleted_at IS NULL GROUP BY activity_id`. Prefill uses
  `RaceCreatePrefill` statics (`race_models.dart:829-844`: pushups 100,
  squats 15, jumpingJacks 500, lunges 40, plank 300) or
  `prefillFromRace`/`draftForActivity` — `POST /races/new` extra already
  supported (`router.dart:305-312`).
- **States:** loading; no trending (hide section); tap → composer with
  movement+goal prefilled and name skipped or pre-filled.

### 1.6 Trophy shelf

v13: horizontal medals row — gold/silver/bronze circles with the place +
past race names.

- **Current:** finished races only appear inside the collapsible
  `NuvoFinishedSummary` (`compete_screen_fixed.dart:156-174`) and Profile's
  race history. `NuvoFinishedRaceRow` already shows rank per finished race
  (:746-753).
- **Verdict:** NEW (UI only).
- **Data:** HAVE — `GET /races` returns completed races with
  `finalStandings` (`RaceFinalStanding{rank, scoreValue}` ,
  `race_models.dart:414-445`); `rankForUser` (:164-172) resolves my place.
  Medal = rank 1/2/3 → gold/silver/bronze; 4+ → numeric chip or omit.
- **States:** no finished races → hide; tap medal → `/race/:id`
  (completed view exists — `_RaceSummaryCard`, `race_detail_screen.dart:583-605`).

### 1.7 "More below" chevron

- **Current:** nothing equivalent. REPLACE/NEW — scroll-position-driven
  widget, fades after 40 px scroll.

---

## 2. New race composer — 4 steps (v13 L54-59)

### Step mapping (6 current → 4 v13)

Current `_Step` enum (`race_composer_screen.dart:148`):
`name, activity, train, goal, racers, review`.

| v13 step | Current step(s) | Merge plan |
|---|---|---|
| 1. Name + autofill | `name` | KEEP `_NamePage` (:1097-1240); add live-as-you-type autofill + "auto" marks |
| 2. Movement grid + goal stepper + mode chips | `activity` (+ `train`) + `goal` | MERGE into one page: `_MovementGrid` (:2650+) + `_GoalPage` (:3090-3610) + `_TeachNuvoCard` (:2243) |
| 3. Invite friends | `racers` | REPLACE `_RacersPage` (:3867-3972) — currently a 2-option toggle — with a checkbox list of friends |
| 4. Review + Start race | `review` | KEEP `_ReviewPage` (:4062-4263) |

### 2.1 Step 1 — name + autofill

- **Current:** `_NamePage._commit` (`race_composer_screen.dart:1185-1214`)
  runs `interpretRaceName(text, catalog:)` → `mergeRaceNameInterpretation`
  ONCE, when the user taps "Choose activity" — not as-you-type. The
  interpreter (`race_name_interpreter.dart:136`) already infers:
  activity/preset or manual goal, `RaceFormat` (first_to_goal /
  most_in_window / best_attempt / timed_attempt), `targetValue`, `metric`,
  `deadline` phrase, `attemptDurationSeconds`, `scoreDirection`,
  `manualGoalName`/`manualUnit`, plus `question` clarification and
  `assumptions`. Safety gate `evaluateRaceSafety` (:1191) KEEP —
  server re-checks (`races.ts:1342-1347`).
- **v13 delta:** "as you type" autofill + fields marked "auto".
  - Autofill-as-you-type: debounce the same `interpretRaceName` call; do
    NOT commit until the user advances (current once-on-commit is the
    safety boundary — keep evaluation cheap, it's pure-Dart).
  - "auto" marks: `RaceDraft.userEditedFields` (`race_draft.dart:24-36,
    127-128`) already tracks what the user touched — an "auto" chip =
    field NOT in `userEditedFields`. NEW badge UI only.
- **Data:** no backend. Interpretation confidence
  (`InterpretationConfidence`) exists in the model — use to decide when to
  show "auto" vs ask.
- **States:** empty (CTA disabled — current `ctaEnabled` :1223); typing
  (autofill preview); safety-rejected (snackbar, existing); low-confidence
  (clarification question — `draft.clarification` already flows to the
  goal page support line, `race_composer_screen.dart:3421`).

### 2.2 Step 2 — movement grid + goal stepper + mode chips

- **Current pieces:**
  - Grid: `_MovementGrid`/`_MovementTile` (:2650-2880) with category tabs,
    search, recents, Teach-Nuvo card.
  - Stepper: `_GoalDisplay` (:3612+) + `_StepButton` — tap-to-edit,
    press-and-hold repeat, floor "nudge" (:3217-3226).
  - Mode chips: `_availableFormats` (:3259-3268) — preset activities expose
    `supportedFormats` from catalog; manual goals get all 4; custom is
    pinned first-to-goal.
  - Score direction (higher/lower wins) (:3357-3560); attempt length
    (:3346-3385); deadline chips (:3311-3333); win statement (:3252).
- **v13 delta:** chips are "first to / most total / best single" (3 of the
  existing 4 modes) + finish "today / 3 days / 1 week / 2 weeks" (chip-set
  swap). Modes without a numeric target hide the stepper (existing rule
  :3462).
- **Verdict:** KEEP logic, REPLACE layout (one merged page). Custom
  movements stay behind `_TeachNuvoCard` → `/races/teach` (no-touch camera
  flow).
- **Data:** same `RaceDraft` fields; `toCreatePayload()`
  (`race_draft.dart:316-344`) already emits correct wire shape.
- **States:** nothing selected (CTA disabled); preset selected; custom
  without verifier spec (must bounce to train — guard exists :500-521);
  manual goal (name+unit required); attempt race (stepper hidden, duration
  chips shown).

### 2.3 Step 3 — invite friends

v13: rows with photo, name, "Raced you 9 times", checkbox.

- **Current:** `_RacersPage` (:3867-3972) is a 2-card choice — "Invite your
  friends" (defers to post-create invite screen) vs "Start solo". Real
  per-person adds happen later on `InviteCrewScreen` via
  `POST /races/:id/participants` per `userId`
  (`invite_crew_screen.dart:142-166`).
- **Verdict:** REPLACE the toggle with the friend checkbox list.
- **Data:**
  - Friend list — HAVE: `GET /crew` → `List<PublicUser>` (photos, names,
    usernames; `race_api.dart:581-584`).
  - "Raced you N times" — MISSING. **Proposed additive API:** extend
    `GET /crew` rows (or a new `GET /crew/invite-suggestions?raceId=` —
    raceId not yet known pre-create, so `GET /crew` is the right place)
    with `racesTogether` — `SELECT COUNT(DISTINCT rm2.race_id) FROM
    race_members rm2 JOIN race_members mine ON mine.race_id = rm2.race_id
    AND mine.user_id = ?` per friend; or one grouped query joined in the
    `/crew` handler.
  - Selected invitees → write path: after `POST /races` succeeds, loop
    `POST /races/:id/participants {userId}` per checked friend (existing,
    `races.ts:1838`; client already does this for the single
    `prefill.withUser` case, `race_composer_screen.dart:596-612`).
    **Proposed additive API (optional):** accept `participantIds: []` on
    `POST /races` so invites are atomic with creation — nicer for the
    "N invites sent" toast math; the loop works without it.
- **States:** crew empty (hide list, show copy + keep invite-code path);
  loading crew; some checked; none checked = solo (current behavior);
  partial invite failure post-create (toast counts *actual* adds — flag:
  spec copy "[name] is live. N invites sent." must use successes, not
  checkboxes).
- Post-create navigation: v13 says "go to Compete and show a toast".
  Current goes `/race/:id` or `/race/:id/invite` (:614-620). CHANGE target
  to `/compete` + toast; keep `_showRaceLiveMoment` first-race payoff
  (:648-671) — it's the same beat.

### 2.4 Step 4 — review + Start race

- **Current:** `_ReviewPage` (:4062-4263) — title (tap → name step),
  win statement, `_RaceSummaryCard` hero, `_ReviewDetails` rows (activity /
  finish line / race mode — each tapping back to its step :4207-4211),
  error box, diagnostics button, `Start race` primary CTA → `_startRace`
  (:495-644).
- **Verdict:** KEEP — matches v13 almost exactly. Add an "invited friends"
  row once step 3 collects people (row → back to step 3).
- **Create call:** `createRaceForComposerDraft` (:97-141) →
  `raceController.createRace`/`createCustomRace` → `POST /races`.
- **States:** review rows; creating (button loading); create error
  (inline box, existing); success → route to Compete + toast (see 2.3).

### 2.5 Chrome shared by all steps

- Back button + step indicator — KEEP `_ComposerTopBar` + `_ProgressLine`
  (:927-1005); `_retreat` (:437-459) already walks visible steps and only
  pops the route from step 1. `train` stays hidden unless custom.

---

## 3. Race detail (v13 L61-64)

v13: back button, race name, rule line ("First to 100 reps"), time left,
podium top-3 (1st raised + gold), rest as open rows, your progress, gap
line, blue Submit proof button.

- **Current** (`race_detail_screen.dart`):
  - Back + owner 3-dot → `/race/:id/settings` (:888-897) — KEEP.
  - Name — `race.displayTitle` (:907-915). KEEP.
  - Rule line — `_LiveRaceHeader.modeSubtitle` (:855-876): "First to
    {target}", "Most {unit} before the finish line", "Best single attempt
    wins", "Timed battle — most in {dur}" + "· N racers". KEEP.
  - Time left — `_DeadlinePill` (:934-968) for deadline races. KEEP.
  - Podium — `NuvoPodium` top 3 + `_LeaderboardGroup` rest (:658-680),
    ordered by `serverRankedParticipants` (`race_display.dart:131-151` —
    direction-aware, deterministic tiebreak). KEEP. Data: `GET /races/:id`
    participants `rank`/`progressValue`/`level`/`finishedAt`.
  - Your progress — `_YourProgressCard` (:972-1095): score/target, rank
    label, progress bar, remaining, gap line ("X behind the leader" /
    "Leading by X" — computed :1003-1007 from `ChaseContext`,
    `chase_context.dart` via `ChaseContext.compute` :522). KEEP.
  - Primary CTA — `_VerifyBar` (:1099+) pinned bottom bar; label resolves
    via `raceProofCta(race)` (`race_display.dart:310-324`): "Start AI
    Motion Proof" / "Log progress" / "Add result" / "Submit proof" /
    "Start attempt" / "Join race" / "Race again". KEEP → restyle blue.
    `_verify` (:281-322) optionally opens an attempt first
    (`POST /races/:id/attempts`) then calls `openAiMotionProof`.
  - Sections v13 does NOT show but code has (see §5): Move log, Rules,
    Manage (Invite friends/Edit race), Leave race, Report race,
    `_UnsupportedVerificationNotice`, `_CheckpointPath` (no-target goals),
    `_FinalStandingsGroup` + `_CompleteCallout` (completed), rematch.
- **Data:** `GET /races/:id` initial + cached-first `_load` (:151-196);
  live updates via `RacePollBackoff` + `GET /races/:id/live?version=`
  (polling, `_pollTick` :112-126). `viewerContext` supplies rank/gaps/
  previousRank/time remaining.
- **States:** loading (`NuvoLoadingIndicator`); error + retry; cached-
  then-refresh; active member / active spectator (canJoin) / owner /
  completed / cancelled-archived (result path); unsupported verification
  (notice); attempt race (CTA "Start attempt"); 1 participant (empty
  board state :646-656); proof pending (`needs_review` rows in move log).
- **Podium data check:** `NuvoPodiumEntry` gets name, stat label
  (`raceProgressLabel`), photo, level, isCurrentUser, onTap → `/u/:id`.
  Medals: 1st gold per spec; verify `NuvoPodium` visuals vs "big photos and
  medals, 1st raised and gold" during build (component:
  `lib/core/widgets/nuvo_podium.dart` — not read here, unverified styling).

---

## 4. Submit proof bottom sheet (v13 Arena item 8, L37-43)

v13: bottom sheet — Camera/Manual segmented control; camera mode = AI
Motion flow ("Put your phone down…", live count, "Nice set. AI Motion
verified it."); manual = minus/plus stepper; preview line "This moves you
to 1st."; main button logs it; on success sheet closes, score animates,
"+N" floats, rank pops, toast, confetti if you took the lead.
"The AI Motion Proof camera screen and its validators stay unchanged."

### 4.1 How the current flow reaches `ai_motion_proof_screen.dart` (no-touch)

1. Any CTA calls `openAiMotionProof(context, ref, race, {routeAction,
   fromPreview})` — `ai_motion_proof_entry.dart:25-70`.
2. `resolveCameraVerification(race, remoteDefinitions:)`
   (`domain/camera_verification_resolver.dart`) decides camera-verifiable.
   Debug-logged via `debugLogCameraVerificationDecision`.
3. Camera-verifiable & not `fromPreview` → push `/race/:id/proof`
   (`SubmitProofScreen`) which renders `_preVerifyContent`
   (`submit_proof_screen.dart:559-621`): movement name, "First to {goal}",
   `_PreVerifySetupCard` (Rive preview or static cue :741-833), framing
   label, "Begin" CTA (:410-417) → `openAiMotionProof(fromPreview: true)`
   → push `/race/:id/proof/ai-motion` → `AiMotionProofScreen`
   (**no-touch**).
4. First-ever camera launch shows `CameraPrimerSheet` modal
   (:55-66, install-scoped `FirstUseStore.isCameraPrimerSeen`).
5. Not camera-verifiable → `/race/:id/proof` shows `_ManualLogCard`
   (:953-1050): value input, optional note, **required photo** tile,
   "Log progress" → `_submitManual` (:71-160): upload evidence via
   `POST /races/:id/proof-media/upload-url` → PUT bytes → `POST
   /races/:id/proof {proofType:'manual', value, note, mediaObjectKey}` →
   `pushReplacement /race/:id/board-moved` with `BoardMovedArgs`
   (:129-144).
6. Attempt races open `POST /races/:id/attempts` first
   (`race_detail_screen.dart:288-311`, `race_controller.dart:879-888`).
7. Arena's submit-proof CTAs funnel identically —
   `arena_screen_fixed.dart:576` calls `openAiMotionProof`.

**v13 shape:** the *chooser* becomes a bottom sheet (Camera/Manual
segmented + stepper + preview), but Camera mode still routes to the same
pre-verify → `AiMotionProofScreen` pipeline — i.e., the sheet's "Camera"
tab is a styled re-entry into `openAiMotionProof`, not an embedded camera.
Manual mode becomes stepper + preview + log, all inside the sheet.

### 4.2 Manual entry endpoint

- `POST /races/:id/proof` `{proofType:'manual', value:int>0, note?,
  mediaObjectKey}` → `{ok, race, submissionResult}`
  (`races.ts:2028`; client `race_api.dart:751-764`,
  `race_controller.dart:857-905` — auto-binds open attempts for attempt
  races, `clientSubmissionId` idempotency at `races.ts:2089-2113`).
- **CONTRACT CONFLICT — photo evidence is REQUIRED for manual proof:**
  `races.ts:2085-2087` — `!isAiMotion && !mediaObjectKey` → 400 "Photo
  evidence is required for this race". The client enforces the same rule
  (`submit_proof_screen.dart:79-84`). v13's plain stepper has no photo
  step. **Options:** (a) keep photo upload inside the sheet's Manual tab
  (one compact tile, existing `_EvidenceTile` logic — least contract
  churn, recommended), (b) additive backend change making photo optional
  per-race (`proofRequirement` already exists — `photo_video` vs others —
  but the enforcement is unconditional, so this *is* a contract change),
  or (c) stepper only for camera-verifiable races' non-camera path — still
  hits the same 400. Flag to user; default to (a).
- Cap: `maxSubmissionValue(metric, isManualRace)` — one proof can't carry
  an absurd value (`races.ts:2128-2132`).

### 4.3 "This moves you to 1st." — client-side preview computation

All inputs exist locally — no new API:

- `VerifierRaceContext.forRace(race, uid)` (`race_mode_semantics.dart:198-236`)
  gives `format`, `scoreDirection`, `raceScoreBefore`, `goalTarget`,
  `leaderScore` (direction-aware), `personalBest`, `timeRemainingSeconds`.
- `ctx.raceScoreAfter(sessionScore)` (:134-145) applies the real scoring
  rule (`cumulative_sum` / `maximum_attempt` / `minimum_attempt`).
- `ctx.beatsLeader(sessionScore)` (:164-168) and
  `ctx.completesGoal(sessionScore)` (:148-151) answer "to 1st" / "finish".
- For exact rank projection incl. mid-table moves: replicate
  `applyOptimisticProof` (`race_controller.dart:694-774`) — patch my score
  per format, re-run `serverRankedParticipants`, diff index → projected
  rank and `peoplePassed`. `applyOptimisticProof` even returns
  `OptimisticProofPatch{rankBefore, rankAfter, peoplePassed}` — call it
  (or its pure computation) live as the stepper changes. Caution: it
  mutates controller state today — extract the pure compute or add a
  read-only variant; do NOT fire the mutating version for previews.
- Copy rules: "This moves you to 1st" (beatsLeader && !already leading),
  "This crosses the finish line" (completesGoal), "You'd pass {name}"
  (rank improves < 1st), "Keeps you at #N" (no change). Lower-wins races
  invert language (scoreDirection-aware).

### 4.4 Response data for the score/rank animation

`POST /races/:id/proof` returns `{ok, race, submissionResult}` where
`submissionResult` (`races.ts:2097-2111`; DTO
`race_models.dart:620-651`) = `{verifiedValue, previousScore, newScore,
previousRank, newRank, peoplePassed, raceCompleted, winnerUserId}`.
Also `race.recentProofs[0]` carries `rankBefore`, `rankAfter`,
`peoplePassed`, `verificationStatus` (used today at
`submit_proof_screen.dart:129-144` to build `BoardMovedArgs`).

- "+N" float → `verifiedValue` (or `newScore - previousScore` delta).
- Score animation → `previousScore` → `newScore`.
- Rank pop → `previousRank` → `newRank` (only when non-null and changed).
- Confetti on taking the lead → `newRank == 1 && previousRank != 1` (or
  `peoplePassed > 0` reaching rank 1).
- "Crossed the finish line" → `raceCompleted`/`winnerUserId`.
- Verification status gating the celebration tone →
  `recentProofs[0].verificationStatus` (`accepted`/`ai_verified` celebrate;
  `needs_review`/`rejected` → calm pending/not-verified copy — mirror
  `_PendingView`/`_NotVerifiedView` tones, `board_moved_screen.dart:403-556`).
- **Disposition:** v13 folds the payoff into the sheet + toast instead of
  the full `BoardMovedScreen`. Keep the data path; `board_moved_screen.dart`
  becomes optional/unused for sheet-submitted proofs — keep the route alive
  for AI Motion completions (the camera flow pushes it today — verify
  before deleting; `ai_motion_proof_screen.dart` is no-touch so its
  navigation target must remain reachable).

### 4.5 States required for the sheet

race still loading; camera-verifiable vs manual-only; attempt race
(attempt auto-opened on submit — `race_controller.dart:879-888`);
manual with no photo yet (blocked CTA or photo row); stepper bounds
(1..`maxSubmissionValue`); submitting; success animations; API error
(`RaceApiException` code/field surfaced — `race_api.dart:141-156`); proof
rejected/pending verdicts; already-joined-check (member-only 403,
`races.ts:2041-2044` — sheet entry points only show for members anyway).

---

## 5. Real features in current code that v13 doesn't show — and how to adapt

| Feature | Where | Adaptation for v13 |
|---|---|---|
| Race settings (edit title/desc/category/target/unit/start/finish/rules, proof review mode `auto_accept`/`peer_review`, archive/cancel/delete) | `race_settings_screen.dart:290-352` (fields), :58,106,158 (`_proofReviewMode`), :390-448 (lifecycle) | KEEP behind Race detail 3-dot — v13's "back button, race name…" header doesn't forbid an owner menu. Note baseline "coming soon" strings at :321,333 (pre-approved cleanup). |
| Proof review (creator accept/reject/"ask for another", community veto) | `proof_review_screen.dart` (bottom sheets :143,:217); helpers `raceProofIsReviewable`/`raceProofIsVetoable` (`race_display.dart:337-353`); `PATCH /races/:id/proofs/:proofId`, `POST .../veto` | KEEP — move-log rows already deep-link (`race_detail_screen.dart:733-737`). If v13 drops the move log, surface pending reviews via notifications instead — but do NOT delete the screen/route (contract `peer_review` mode still exists server-side, `races.ts:1442-1444`). |
| Teach movement (Teach Nuvo, train step, custom verifiers) | `teach_movement_screen.dart`, `_TrainPage` (:2348+), `/config` `custom_motion` gate | KEEP as the "custom ones" entry inside the step-2 grid (`_TeachNuvoCard` :2243). Conditional `train` step already only appears for custom drafts (:241-251). |
| Manual goals (honor goals with photo proof) | `RaceGoalKind.manual` (`race_draft.dart:13-19`), `_manualCreatePayload` (:357-379) | KEEP inside step 2 ("custom ones" / text goals). v13 shows only movement races; manual keeps the photo-proof contract end-to-end. |
| Invite code + share sheet | `POST /races/:id/invite-code`, `POST /races/join-code`, `invite_crew_screen.dart:292-331`, `race_share_sheet.dart` | KEEP — invite code remains the fallback in step 3's empty state and Race detail manage. |
| Attempt races (`timed_attempt`) + `POST /races/:id/attempts` | `RaceFormat.timedAttempt`, `race_controller.dart:879-888` | KEEP in mode chips only if v13 "best single" is meant to cover it; spec lists 3 modes — propose mapping "best single" → `best_attempt` and keeping `timed_attempt` available on manual goals + catalog activities that declare it, not in the primary chip row. Flag decision. |
| Rematch | `POST /races/:id/rematch`, `_rematch` (`race_detail_screen.dart:325-352`) | KEEP on completed-race detail ("Race again" CTA). V13 doesn't mention it; trophy shelf could deep-link too. |
| Waiting-for-crew + finished summaries on Compete | `NuvoWaitingCrewSummary`, `NuvoFinishedSummary` (:135-175) | FOLD — waiting races become Live-race cards with a "waiting" state; finished feed the trophy shelf. |
| Race events feed + live polling | `GET /races/:id/events`, `GET /races/:id/live`, `RacePollBackoff` | KEEP polling (leaderboard liveness is the product's core); events feed only needed if move log stays. |
| Move log on Race detail | `_MoveLogGroup` (:719-737,1624+) | v13 shows only podium + progress. Propose keeping move log collapsed below — it's proof transparency and feeds proof review. Flag decision. |
| Report race | `_reportRace` (:354-424), `POST /reports/races/:id` | KEEP — required for safety; move to the 3-dot menu. |
| Leave race | `_leaveRace` (:229-258), `POST /races/:id/leave` | KEEP — same menu. |
| `_UnsupportedVerificationNotice` | :617-627,:1898+ | KEEP — needed when a remote verifier isn't runnable on this build. |
| `RaceCreatePrefill` entry points (quick starts, "Race {name}", crew-scoped create) | `race_models.dart:797-875`; crew prefill `prefill.crewId` → `squadControllerProvider.addRace` (:581-594) | KEEP — v13 "Trending moves Start", profile "Race [Name]" (renamed from "Challenge"), and crew "Start a crew race" all reuse this. |
| First-race guide coach marks | `first_use_guide.dart`, `FirstRaceGuideKeys` throughout composer/detail/proof | KEEP — retarget to new widgets; guide steps `composerName→composerReview` map onto the 4 steps. |
| Rules text on Race detail | `race.rules` / `_rulesCopy` (:741-753) | v13 doesn't show rules; keep one line under the rule line or in the menu — flag (note: `POST /races` INSERT doesn't persist `rules` today — PATCH-only field; verify before relying on it, unverified). |
| Recurrence | `draft.recurrence`, `RaceRecurrence` (`motion_activity.dart:283`) | v13 shows recurring races only on the Crew page ("Every Monday"). KEEP payload field; no composer UI for it in v13 — leave default `none`. |

---

## 6. Conflicts: v13 spec vs AGENTS.md / product model

1. **"Challenge [Name]" button** (spec L94) — banned word; product model
   mandates "race". Resolution: label it **"Race [Name]"** everywhere.
2. **"private profile" toggle** (spec L109) — product model: "Private
   profiles do not exist. Everyone is visible." But `GET /profile/me`
   returns `privateProfile` and `POST /profile` accepts it (API_CONTRACT
   L131-153) — the *field* exists, the *product concept* was removed.
   Resolution: do not surface the toggle in v13; leave the column dormant.
   (Out of this doc's scope — belongs to the Settings spec.)
3. **Compete shows live races + leaderboard** — product model forbids
   active-race lists and leaderboard views on Compete (see §1 preamble).
   Resolution proposed: allow swipe cards + mini leaderboard as v13
   dictates (it's the approved target design), keep zero management
   affordances on Compete. Needs explicit user sign-off.
4. **Manual proof without photo** — server requires `mediaObjectKey` on
   every non-AI submission (`races.ts:2085`). Resolution: keep a photo row
   in the sheet's Manual tab (recommended) or explicitly approve a
   backend contract change.
5. **"Join a race" cards imply public-ish races** — backend visibility is
   pinned `crew_only` for all new races (`raceAccess.ts:30`,
   `races.ts:1416`), with `resolveRaceAccess` granting crew-level read.
   Resolution: scope "open races" to friends' races only — matches both
   the spec's wording ("open races from friends") and the deployed access
   model; no `public` visibility needed.
6. **"podium ... revealed by scrolling"** — product model (L99) says Arena
   owns the podium surface; v13 Race detail also has a podium. These
   coexist (detail is per-race standings, Arena is cross-race next-move);
   no change needed, just don't move move-log/feed INTO Arena's podium.

---

## 7. Missing data summary (additive API asks — none require schema surgery)

| v13 need | Status | Proposed additive API |
|---|---|---|
| Race color | MISSING | Client-deterministic palette now (recommended); optional `races.color` TEXT + accept `color` on create/patch + emit in `buildRaceResponse` later |
| Open races from friends | MISSING | `GET /races/open` — active races created by `crew_connections` members, not yet joined, excluding blocked; join via existing `POST /races/:id/join` |
| "Raced you N times" | MISSING | `racesTogether` count on `GET /crew` rows (or `GET /crew/invite-suggestions`) |
| Global/friends leaderboard | MISSING | `GET /leaderboard?scope=friends|global` aggregated from `race_final_standings` + progression XP; include viewer absolute rank |
| Trending "[N] racing" | MISSING | Add `activeRaceCount`/`recentRacerCount` per activity in `GET /races/activities` |
| Rank trend on list rows | MISSING | Emit `viewerRank`+`previousRank` (from latest `move_logs.previous_rank`) per race in `GET /races` |
| Atomic invites on create | NICE-TO-HAVE | Accept `participantIds[]` on `POST /races`; else loop `POST /races/:id/participants` |
| Trophy shelf | HAVE | `GET /races` completed races + `finalStandings` — client-only |
| "This moves you to 1st" | HAVE | `VerifierRaceContext` + `serverRankedParticipants` — client-only |
| Score/rank animation payload | HAVE | `submissionResult` on `POST /races/:id/proof` |

---

## 8. Guardrails for the build phase

- **No-touch files (never plan edits):** `auth_api.dart`,
  `auth_repository.dart`, `auth_controller.dart`, `auth_gate.dart`,
  `secure_token_store.dart`, `ai_motion_proof_screen.dart`,
  `motion_validators.dart`, `pose_detector_service.dart`,
  `camera_image_converter.dart`, all iOS native files. Treat as read-only
  imports only.
- **Do-not-casually-touch:** `race_api.dart`, `race_repository.dart`,
  `race_controller.dart` — changes here need the AGENTS task declaration.
  Any new endpoint goes through `RaceApi` + `RaceRepository` like existing
  methods (`_get`/`_post`/`_guard` pattern, `race_api.dart:496-544`).
- **pubspec:** needed pieces already exist — `flutter_riverpod`,
  `go_router`, `google_fonts` (Manrope), `animations`, `flutter_animate`,
  `shimmer`, `rive`, `qr_flutter`, `camera`,
  `google_mlkit_pose_detection`, `google_mlkit_barcode_scanning`,
  `cached_network_image`, `image_picker`. **No `confetti` package** —
  reuse the hand-rolled `_Burst` painter pattern
  (`board_moved_screen.dart:351-401`) or write a small painter; do not add
  a dependency. **No `mobile_scanner`** (deliberately incompatible —
  pubspec :57-60 comment); barcode scanning already uses
  `google_mlkit_barcode_scanning`.
- **Verification is real:** confidence/verdicts must come from
  `motion_validators.dart` + the proof response — never fake the preview
  or the result.
- **Backend contract:** additive-only proposals in §7; nothing here
  renames or removes fields the deployed Worker reads/writes.
