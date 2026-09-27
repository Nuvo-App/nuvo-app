# FlexiRace Contracts v1 — "Compete on Anything" Implementation Gate

Status: **contract gate** — review before Checkpoint A.
Owner split: **Agent 3 owns race semantics. Agent 4 owns verifier capability.**
Extends `docs/agents/21-race-system-v2-design.md` (race modes, lifecycle,
live architecture) — that doc stays authoritative for UX/lifecycle phases;
this file is the *representation* contract: what a race IS, what it asks of
a verifier, and how free text becomes a draft.

The acceptance test: a competition we never anticipated is representable
**without adding a race-type class** — by combining the primitives below.

---

## 1. Canonical `RaceDefinition`

A race is a product of six slots. Every slot is a finite enum or a scalar —
no per-activity subclasses, no `PushupRace`/`GradeRace`/`PlankRace` types.

```ts
RaceDefinition {
  // ── subject: WHAT is being measured ──────────────────────────────
  subject: {
    activityId: string            // catalog id ('pushups'), custom movement
                                  // id, or free-text label for honor goals
    activitySource: 'catalog' | 'custom' | 'manual'
    metric: RaceMetric            // §2 — the measured quantity
    unit: string                  // display unit ('pages','reps','miles')
  }

  // ── scoring: HOW submissions fold into a score ───────────────────
  scoring: {
    rule: ScoringRule             // §2 — cumulative_sum | maximum_attempt
                                  //       | minimum_attempt
    direction: 'higher' | 'lower' // rank ordering (wire: scoreDirection)
    target: int | null            // finish-line value (wire: targetValue)
  }

  // ── format: WHEN the race completes ──────────────────────────────
  format: RaceFormat              // first_to_goal | most_in_window
                                  // | best_attempt | timed_attempt

  // ── time: WHEN action is legal (three orthogonal clocks, §3) ─────
  timePolicy: {
    startsAt: ISO | null          // start line; null = on create/join
    endsAt: ISO | null            // deadline; null = open-ended
    liveWindowSeconds: int | null // synchronized-session cap (Phase F)
  }

  // ── attempts: HOW MANY times a racer may produce a result (§4) ───
  attemptPolicy: {
    durationSeconds: int | null   // per-attempt countdown (timed_attempt)
    limit: int | null             // null = unlimited
  } | null                        // null for cumulative formats

  // ── proof: WHAT evidence a submission needs (§5) ─────────────────
  proofNeed: ProofNeed            // capability REQUEST — never internals
}
```

### Derived, never stored

| Field | Rule |
|---|---|
| `scoring.rule` | `cumulative_sum` for `first_to_goal`/`most_in_window`; `maximum_attempt` for `best_attempt`/`timed_attempt` unless `direction='lower'` → `minimum_attempt`. Users never set it. |
| `finishRule` | `first_to_goal` → `onTarget`; `most_in_window` → `atDeadline` (`endsAt` required); attempt formats → `atDeadline` if `endsAt`, else `allAttemptsUsed`/`manual` close. |
| `participantPolicy` | `{min: 2, max: null}` default; `max: 2` selects head-to-head *presentation*. Teams/relay deferred (Phase J). |

### Wire mapping (backward compatible)

`subject.activityId` → `activity_id` · `metric` → `metric` · `unit` →
`target_unit` · `scoring.rule` → `scoring_rule` · `direction` →
`score_direction` · `target` → `target_value` · `format` → `format` ·
`startsAt`/`endsAt` → `start_at`/`end_at` (aliases `startsAt`/`endsAt`,
`startLineAt`/`finishLineAt` already accepted) · `attemptPolicy` →
`attempt_duration_seconds` + `attempt_limit` · `proofNeed` →
`verifier_type` + `proof_requirement` + `verifier_release_id` (§5).

**No schema break:** every field already exists on the wire except
`minimum_attempt` (new `scoring_rule` value) and `live_window_seconds`
(Phase F). Old payloads decode with today's defaults.

---

## 2. Scoring strategies — the finite primitive set

**Aggregation** (how a verified submission changes the score):

| `scoring_rule` | Fold | Race examples |
|---|---|---|
| `cumulative_sum` | `score += value` | first to 100, most pages by Friday |
| `maximum_attempt` | `score = max(score, value)` | longest plank, highest bench, most jacks in 60s |
| `minimum_attempt` | `score = min(score, value)` *(new)* | fastest mile, lowest golf score |

**Direction** (`score_direction`, existing): `higher` | `lower` — ranking
order and "who's ahead" semantics. `minimum_attempt` implies `lower`;
they are stored separately because direction also sorts cumulative races.

**Deliberately absent** (considered, rejected):

- `latest_attempt` — "most recent result wins" has no product case; the
  attempt table keeps every result, so it can be added later without
  migration.
- `sum_within_window` — windowing is `timePolicy`, not scoring. "Most
  steps this week" = `cumulative_sum` + `endsAt`, not a new rule.
- `elapsed_time` / `hold_duration` — these are **metrics** (a submission's
  value in seconds), not aggregations.

### Metrics (`RaceMetric`, wire `metric`)

Today the client enum is `reps | seconds`; the wire treats it as an opaque
token (manual races already send `reps` with a display `unit`). Contract:

```
metric: 'reps' | 'seconds' | 'milliseconds' | 'meters' | 'miles' | 'km'
      | 'score' | 'count'   // 'count' + free-text unit = anything else
```

`count` is the generic escape hatch (pages, problems, ounces, books) —
the server stores an opaque integer; `unit` carries the label. Extending
the metric list never requires a new race type, only a catalog/display
entry.

---

## 3. Time model — four distinct clocks, do not conflate

| Concept | Field | Meaning | Example |
|---|---|---|---|
| **Deadline** | `timePolicy.endsAt` | Race legally closes; finalizer crowns winner | "most steps by Friday" |
| **Start line** | `timePolicy.startsAt` | Proofs before this are rejected | "race starts Saturday" |
| **Attempt window** | `attemptPolicy.durationSeconds` | One submission's countdown | "most jacks in 10 sec" |
| **Duration metric** | `subject.metric = seconds/ms` | The *measured quantity* is time | "longest plank", "fastest mile" |

"Most jumping jacks in 10 seconds" = `timed_attempt` +
`attemptDurationSeconds: 10` — the clock bounds *each attempt*. It is NOT
`most_in_window` (which bounds the *race*). "Longest plank" = duration as
the *metric* (`seconds`, `maximum_attempt`). "Fastest mile" = duration as
the metric with `minimum_attempt`. All four compose independently.

Authority: `serverTime` — device clocks are display-only (V2 doc §9 stands).

---

## 4. Attempt model

```
attemptPolicy {
  limit: int | null        // 1 = single attempt; N = capped; null = unlimited
  durationSeconds: int | null  // per-attempt timer (timed_attempt only)
}
```

Submission binding is *derived from scoring rule*, never configured:

| Scoring | Submission semantics |
|---|---|
| `cumulative_sum` | every verified submission **adds** — attempts are just proofs |
| `maximum_attempt` / `minimum_attempt` | each submission is a discrete **attempt**; engine keeps the extreme (`race_attempts` lifecycle, existing) |

Mapping check: highest grade → `maximum_attempt`, limit 1 or unlimited;
longest plank → `maximum_attempt` on `seconds`; fastest mile →
`minimum_attempt` on `seconds`; first to 100 → `cumulative_sum`, no
`attemptPolicy`.

---

## 5. Proof capability contract — the Agent 3 ⇄ Agent 4 boundary

`RaceDefinition` describes the evidence it *needs*. It never names ONNX
paths, pose predicates, spec internals, or release IDs as configuration —
`verifierReleaseId` is an opaque pin resolved by Agent 4's registry.

```ts
// WHAT a race needs — authored by interpreter or composer UI.
ProofNeed {
  kind: 'motion_reps'      // camera-counted repetitions (catalog/custom)
      | 'motion_duration'  // camera-timed hold (plank, wall sit)
      | 'distance'         // measured distance (GPS/manual for now)
      | 'time_result'      // an elapsed-time result (fastest mile)
      | 'numeric'          // honor-logged number (grades, books, pages)
      | 'photo' | 'video' | 'link' | 'note'   // evidence uploads
      | 'manual'           // bare check-in
      | 'custom_verifier'  // Teach Nuvo movement (reps or duration)
  activityId: string | null        // motion kinds only
  metric: RaceMetric
}

// Agent 4's answer — resolved at create time, pinned onto the race.
ProofCapabilityResolution {
  status: 'ready' | 'degraded' | 'unsupported'
  verifierType: 'preset_pose' | 'custom_pose' | 'remote_release'
              | 'manual_log' | 'external'      // what the race stores
  verifierReleaseId: string | null            // opaque; Agent 4 owns meaning
  sessionBehavior: 'count_reps' | 'hold_timer' | 'timer'
                 | 'distance_tracker' | 'none'
  reason: string | null        // 'unsupported'/'degraded' → why + fallback
}
```

Resolution rules (create-time, server-side):

1. `motion_*` with a supported catalog `activityId` → `preset_pose`, ready.
2. `custom_verifier` → `custom_pose` spec pinned from Teach Nuvo, ready.
3. `motion_*` with an unknown catalog id → registry lookup; a released
   remote verifier resolves `remote_release` + `verifierReleaseId`,
   else `degraded` → offered fallback is `manual_log` (the race still
   creates — AI check becomes honor + evidence).
4. `numeric`/evidence kinds → `manual_log` + matching `proofRequirement`
   (`note`, `link`, `photo`, `photo_video` — existing set).
5. `distance`/`time_result` → `manual_log` today (no GPS verifier);
   `sessionBehavior: 'timer'` may assist capture but never verifies.

Fail-closed: an unresolvable `motion_*` need is `unsupported` unless the
user accepts the degraded manual fallback — never silently downgraded.

---

## 6. Interpreter output — `FlexiRaceDraft`

`parseRaceIdea` exists but is optimistic. The new interpreter produces a
**draft + provenance**, never a committed race:

```ts
FlexiRaceDraft {
  input: string                        // verbatim
  definition: Partial<RaceDefinition>  // filled slots; nulls are unknowns
  confidence: 'high' | 'medium' | 'low'
  assumptions: [{                      // defaults the AI chose — editable
    field: string, value: unknown, reason: string
  }]
  questions: [{                        // blockers — max ONE shown at a time
    field: string, prompt: string, options: string[] | null
  }]
  unsupported: [{                      // what Nuvo can't do yet
    field: string, wanted: string, reason: string
  }]
  editable: string[]                   // every proposed field is editable
}
```

Rules: AI proposes, user confirms on a review card. `questions.length > 0`
blocks create; `assumptions` render as tinted, tappable rows ("assumed:
ends Sunday — tap to change"); `unsupported` renders as a warning with the
`degraded` fallback pre-selected. Never silently create an ambiguous race.

---

## 7. Ambiguity rules — the five probes

| Input | Behavior |
|---|---|
| "running challenge" | `subject.activity=running`, `metric=miles` (catalog default), `format=first_to_goal`. **Question (1):** "First to a distance, most miles, or fastest?" — the format is genuinely unknowable. |
| "highest score" | `scoring=best`, `metric=score`, `proof=numeric`. **Assumption:** target none, open-ended until user adds `endsAt`; unit assumed `points`. Editable, no question. |
| "first to 20" | `format=first_to_goal`, `target=20`, `metric=count`. **Question (1):** "20 what?" — only if no activity token parsed at all. |
| "best pushups" | Activity known, format ambiguous. **Assumption:** `best_attempt` + `reps` (a max set), `limit` unlimited — shown as editable; no question needed since interpretation is coherent. |
| "who studies the most" | `metric=minutes`, `count`+`unit:'min'`, `cumulative`, `proof=numeric`. **Assumption:** `endsAt` = Sunday (this week); editable. No question — a missing window has a sane default. |

Escalation ladder: **confident fill → catalog/default fill → editable
assumption → one question → unsupported.** A draft asks at most one
question and never more than one round-trip.

---

## 8. Backward compatibility

| Existing race | Maps to |
|---|---|
| first-to-reps (pushups etc.) | `catalog` + `reps` + `first_to_goal` + `cumulative_sum` + `motion_reps`/`preset_pose` |
| plank / wall sit | `catalog` + `seconds` + `best_attempt`/`timed_attempt` + `maximum_attempt` + `motion_duration` |
| timed battle | `timed_attempt` + `attemptPolicy.durationSeconds` + `maximum_attempt` |
| most-in-window | `most_in_window` + `cumulative_sum` + `endsAt` |
| Teach Nuvo custom movement | `custom` + `custom_verifier`/`custom_pose`; graduates to attempt formats per V2 §11 |
| treadmill/distance | `catalog` + `reps`(metres) + `cumulative`; `distance` proof need → `manual_log` today |
| manual/honor goal | `manual` + `numeric`/evidence proof + `manual_log` |

**Verdict: no migration, no API version bump.** `Race.fromJson` already
defaults every legacy row. Dual decoding is limited to: (a) accepting the
new `minimum_attempt` scoring value, (b) reading `proofNeed` back out of
`verifier_type`+`proof_requirement` (a pure function, no stored copy).

---

## 9. Worked examples — 20 races through the contract

| # | Input | format / scoring / metric / attempt / proof | Agent-4 today |
|---|---|---|---|
| 1 | First to 100 pushups | first_to_goal · cumulative · reps · — · motion_reps(preset) | ✅ count_reps |
| 2 | Most pushups in 30 sec | timed_attempt · maximum · reps · 30s · motion_reps(preset) | ✅ timed session |
| 3 | Longest plank | best_attempt · maximum · seconds · — · motion_duration | ✅ hold_v1 |
| 4 | Fastest mile | best_attempt · **minimum** · seconds · — · time_result | ⚠️ manual_log (no GPS) |
| 5 | Most miles this week | most_in_window · cumulative · miles · endsAt=Sun · distance | ⚠️ manual_log |
| 6 | Highest math test grade | best_attempt · maximum · score · limit 1 · numeric | ✅ manual_log |
| 7 | Lowest mile time | best_attempt · minimum · seconds · — · time_result | ⚠️ manual_log |
| 8 | First to read 5 books | first_to_goal · cumulative · count('books') · — · numeric | ✅ manual_log |
| 9 | Most pages by Friday | most_in_window · cumulative · count('pages') · endsAt · numeric | ✅ manual_log |
| 10 | Best vertical jump | best_attempt · maximum · count('in') · — · numeric | ⚠️ manual (no jump verifier yet) |
| 11 | Most water today | most_in_window · cumulative · count('oz') · endsAt=today · numeric | ✅ manual_log |
| 12 | Highest Duolingo score | best_attempt · maximum · score · — · numeric | ✅ manual_log |
| 13 | Most coding problems this week | most_in_window · cumulative · count('problems') · endsAt=Sun · numeric | ✅ manual_log |
| 14 | First to 10 workouts | first_to_goal · cumulative · count('workouts') · — · photo | ✅ manual_log |
| 15 | Highest bench press | best_attempt · maximum · count('lb') · — · photo/numeric | ✅ manual_log |
| 16 | Longest wall sit | best_attempt · maximum · seconds · — · motion_duration | ✅ hold-style spec |
| 17 | Most shots in 60 sec | timed_attempt · maximum · reps · 60s · motion_reps | ✅ (basketball catalog entry exists) |
| 18 | Fastest 100m | best_attempt · minimum · seconds · — · time_result | ⚠️ manual_log |
| 19 | Most steps today | most_in_window · cumulative · count('steps') · endsAt=today · numeric | ✅ manual_log |
| 20 | Teach Nuvo movement | first_to_goal (or any attempt format) · reps · custom_verifier | ✅ custom_pose spec |

Patterns visible: **9/20 need zero AI** (manual_log carries Compete on
Anything), 4 need the new `minimum_attempt` primitive (#4,7,18 + any
"lowest"), and nothing needs a new race class.

---

## 10. Implementation checkpoints — each leaves `main` buildable

| CP | Scope | Done when |
|---|---|---|
| **A — domain model + compat** | `RaceDefinition` Dart type + `fromRace()` projection of existing `Race`; `ProofNeed`/`ProofKind`; `minimum_attempt` enum value accepted on decode | existing races decode; `dart analyze` clean; no behavioral change |
| **B — scoring engine** | Worker `applyVerifiedSubmission` gains `minimum_attempt` + direction-aware fold; `most_in_window`/`best_attempt` finalizer crowns winners (V2 §8) | Worker tests cover min-attempt, deadline finalize, ties |
| **C — API persistence** | store `scoring_rule='minimum_attempt'`, `score_direction`, `proof_need` derivation; create-path accepts `format`+attempt fields for manual too (validation already exists) | contract tests on create/read round-trip |
| **D — interpreter** | `FlexiRaceDraft` producer: catalog-aware parser (`parseRaceIdea` upgrade or LLM-assisted), emits assumptions/questions/unsupported | unit tests on §7 probes + §9 inputs |
| **E — confirmation UI** | review card: proposed definition, assumption rows, one question slot, unsupported warnings, edit affordances | widget tests: ambiguous input can't create until confirmed |
| **F — lifecycle support** | deadline finalizer cron, attempt-limit enforcement surfaced in UI ("2 attempts left"), per-format detail composition (V2 §14) | end-to-end: windowed race completes with winner |
| **G — Agent-4 integration** | `ProofCapabilityResolution` endpoint/logic; remote-release pinning on create; degraded→manual fallback path | custom/remote races create with pinned capability |
| **H — fixtures + tests** | `PresentationDemoData` gains 3–4 FlexiRace fixtures (deadline, best-attempt, fastest-mile); golden flows | demo mode renders every format correctly |

Dependencies: A→B/C parallel → D→E → F; G parallel to D onward; H last.

---

## Gate

Contracts are deliberately conservative: they canonize fields the Worker
already stores, add **one** scoring primitive (`minimum_attempt`), and put
a typed capability boundary between race semantics and verifier internals.

Open questions before Checkpoint A:

1. `minimum_attempt` as a third `scoring_rule` vs. reusing
   `maximum_attempt` + `direction='lower'` — I chose the explicit third
   rule (self-describing wire, no ambiguous "maximum means minimum").
   Alternative is one field fewer.
2. Free-text `activityId` on manual races — do we persist it as a
   searchable label or keep it inside `unit`/title? I lean: persist
   (`activity_id` column already exists; `activitySource='manual'`).
3. Interpreter backend: on-device `parseRaceIdea` rules first (no latency,
   no cost) vs Worker LLM call — contract supports either; recommend
   rules-first, LLM as fallback escalation.
