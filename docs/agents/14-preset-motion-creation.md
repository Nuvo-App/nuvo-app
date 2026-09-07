# Nuvo Preset Motion Creation Contract

The source of truth for adding a new preset motion (e.g. "create a preset for
jumping rope"). Follow this end to end — a preset is **not done when its
validator test passes**, it is done when a race can be created, loaded, and
verified through the whole route **on deployed production**.

## Ownership rule — source-code complete ≠ task complete

You own the whole stack: Flutter app, Cloudflare Worker, backend/domain
validation, schemas, serialization, tests, scripts, docs, **and deployment
configuration**. Do not restrict yourself to the file where the bug first
appears; if the correct fix crosses three systems, change three systems — no
client workaround because "the real fix is in the Worker".

If a preset (or any change) touches deployable server code, the sequence is:

```text
implement client  →  implement verifier  →  register backend
  →  test client   →  test Worker (npm test)
    →  deploy the Worker yourself (npm run deploy)
      →  verify the DEPLOYED version serves the change
        →  DONE
```

**Deploy the Worker yourself.** `cd server/worker && npm test && npm run deploy`,
then confirm `Current Version ID` and hit the deployed URL. Never finish with
"one action on you: deploy the Worker". The only exception is a genuine
credential/permission barrier — then attempt it, capture the actual failure,
and report the concrete blocker.

The historical failure this rule exists for: the 10 preset-motion-expansion
activities shipped in the Flutter client and the Worker *source*, all tests
passed — but the Worker was never redeployed, so production kept rejecting
`POST /races` with `"Choose a supported activity."` for weeks. Source-complete,
task-incomplete.

### Verifying a deployed catalog change without an auth token

`POST /races` needs a production JWT. To confirm the deployed Worker's activity
allowlist is current without one, hit the public endpoint:

```bash
curl -s https://nuvo-api.getnuvoapp.workers.dev/races/activities | jq '.supported'
```

It returns the exact set `POST /races` will accept (same `RACE_ACTIVITY_CATALOG`,
same bundle). If a new preset's id is in that list on production, `configFromBody`
accepts it. `GET /health` confirms the Worker is serving.

---

## A. What a preset motion is

- A **deterministic production verifier** — hand-written biomechanics + a
  frame-count state machine. No ML inference on the hot path.
- **Separate from Teach Nuvo / Motion V2** (`lib/features/races/ai/motion_v2/`,
  `custom_pose/`). Never wire a preset through those, and never touch them for
  a preset change.
- **Explicitly selected** by the user in the race composer picker.
- May use **motion-specific biomechanics** — do not force every motion into one
  abstraction (see §C).
- Must be **fast, reliable, mobile-friendly**: works at ~10–20 effective pose
  FPS, counts back-to-back reps, never double-counts (§D, §E).

### Protected known-good presets — do not modify their core logic casually

- **Pushups** (`PushupsValidator`)
- **Jumping Jacks** (`ConfigurableRepValidator` + `jumpingJackRepDefinition`)
- **Plank** (`PlankHoldValidator`)

Do not change `_BaseValidator`, `RepCounterStateMachine`, or
`ConfigurableRepValidator` in a way that could alter these unless you can prove
the behaviour is unchanged (run their tests before and after).

---

## B. Mandatory registration checklist (with this repo's real files)

A preset that exists in only some of these layers is the exact bug this doc
exists to prevent. `test/preset_registration_contract_test.dart` iterates the
catalog and checks every row — run it after any change here.

| # | What | File / symbol |
|---|---|---|
| 1 | Domain identity enum | `lib/features/races/domain/motion_activity.dart` → `MotionActivityType` (value + `backendValue` + `fromBackendValue` aliases) |
| 2 | Runtime activity enum | `lib/features/races/data/ai_motion_models.dart` → `AiMotionActivity` (value + `backendValue` + `label` + **`fromBackendValue`** — this one has a `_ => pushUps` fallback, so a missing case fails silently; the contract test's "catalog and enum agree on counts" catches it) |
| 3 | Production catalog | `lib/features/races/domain/motion_activity_catalog.dart` → an entry in `motionActivityDefinitions` (title, icon, `metric`, `suggestedTargets`, `supportedFormats`, `aliases`, `instructions`, `category`, `preferredCameraView`, `framingLabel`, `sortPriority`, `featured`) |
| 4 | Free-text inference (optional but cheap) | same file → `inferSupportedMotionActivity` regex, and `MotionActivityType.fromBackendValue` aliases |
| 5 | Runtime movement enum | `lib/features/races/ai/motion_validators.dart` → `MovementType` value |
| 6 | Runtime movement definition | same file → an entry in `supportedMovementDefinitions` (`MovementDefinition`: `type`, `activity`, `title`, `unit`, `defaultTarget`, `isHold`) |
| 7 | Type → activity bridge | same file → `_aiMotionActivityForType` switch case |
| 8 | Validator factory | same file → `createMotionValidator` switch case → returns the concrete validator |
| 9 | Pre-verify demo (may be `null`) | `lib/features/races/presentation/widgets/preset_movement_demos.dart` → `movementDemoForType` case. `null` is allowed — the pre-verify screen already gates on `!= null`. |
| 10 | Camera-verification resolver | `lib/features/races/domain/camera_verification_resolver.dart` — **data-driven** off `supportedMotionActivityTypes`; nothing to add if #3 is done |
| 11 | Verifier runtime resolver | `lib/features/races/ai/verifier_runtime.dart` — **data-driven** via `movementDefinitionForType`; nothing to add |
| 12 | Race draft / create payload | `lib/features/races/domain/race_draft.dart` — **data-driven** via `activity.type.backendValue`; nothing to add |
| 13 | **Backend allowlist** | `server/worker/src/domain/raceActivities.ts` → `RaceActivityId` union **and** `RACE_ACTIVITY_CATALOG` entry **and** `normalizeActivityId` (the `[...].includes(normalized)` list + any alias `if`s) **and** `normalizeMetric` reps-inference list. The public `GET /races/activities` endpoint (`src/index.ts`) is derived from `RACE_ACTIVITY_CATALOG` — nothing to add. |
| 14 | **Deploy the Worker — you do this** | `cd server/worker && npm test && npm run deploy`, then `curl https://nuvo-api.getnuvoapp.workers.dev/races/activities` and confirm the new id is in `.supported`. A `raceActivities.ts` change does **nothing in production** until deployed. This is the single most common failure. Not the user's step — yours. |
| 15 | Diagnostics | validator's `debugValues` (§J) |
| 16 | Tests | §H, §I + add the movement to `test/preset_motion_expansion_test.dart` and (if a fixture list still exists anywhere) update it. The contract tests below auto-cover registration once #3 is done. |

### The invariant tests (keep these green)

- `test/preset_registration_contract_test.dart` — every catalog preset, every
  client layer, plus a printed `PRESET ROUTE AUDIT`.
- `test/preset_activity_round_trip_test.dart` — `_presetCases` is catalog-derived;
  every preset round-trips id → catalog → draft → `Race.fromJson` →
  `resolveCameraVerification` → `VerifierRuntimeResolver` → `createMotionValidator`.
- `server/worker/test/race_domain.test.mjs` — "every RACE_ACTIVITY_CATALOG entry
  passes the full creation route" (source-level; still needs a deploy).

---

## C. Verifier architecture choices — pick the pattern, don't force one

### Rep state machine — `RepCounterStateMachine` (reuse read-only) or a dedicated class

Use for: squats, pushups, calf raises, arm raises, deep/sumo squats.

```text
READY (start pose, N stable frames)
  → MOVEMENT (leave start)
    → REQUIRED RANGE / DEPTH (active pose, N stable frames — latches _hitActive)
      → RETURN to start (N stable frames) → +1
        → RESET: must re-reach a clear start pose before another rep arms
```

`ConfigurableRepValidator` + a `RepMovementDefinition` is the data-driven form
(squat family, lunges). A dedicated `_BaseValidator` subclass is the form when
you need per-frame instance state a pure condition can't hold (e.g.
`CalfRaisesValidator`'s rolling ankle-Y baseline).

### Alternating / cadence — `CadenceDetector` + `CadenceMovementDefinition`

Use for: running in place, treadmill running, walking in place, marching,
step-ups, butt kicks, mountain climbers.

```text
left confirmed (N stable frames, first side = baseline, no count)
  → right confirmed (differs from last side) → +1
    → left confirmed → +1
```

A count only fires when the newly-confirmed side **differs** from the last
confirmed side — repeated same-side motion never counts, with no separate
"return to neutral" needed. `stableFrames` (default 2) is the noise floor.

The **signal function** returns `CadenceSide?` (null = neutral/ambiguous). Base
it on **left-vs-right relative difference**, not either limb's absolute position
(see §F). Add a context gate where needed (mountain climbers gate on a plank
posture before reading the knee signal).

### Multi-phase sequence — `MultiPhaseSequenceValidator` + a `MultiPhaseSequenceDefinition`

Use for: burpees, jump squats, lunge jumps — anything with ≥3 distinct ordered
phases. Define `SequencePhaseDefinition`s with per-phase `stableFrames`, a
`resetCondition`, and `cooldownFrames` (keep `cooldownFrames` small — see §D).
See `preset_motion/burpee_definition.dart`, `preset_motion/multi_phase_definitions.dart`.

### Duration / hold — `PlankHoldValidator` + `HoldTimerStateMachine`

Use for: plank. `isHold: true` in the `MovementDefinition`; the count is
seconds, not reps. Only build a new one of these if a motion is genuinely a
timed hold.

---

## D. Fast-rep requirements

- **Recognition never waits for the UI.** The frame loop
  (`ai_motion_proof_screen_io.dart` `_handleCameraFrame`) calls
  `_runtime.update(frame)` unconditionally every processed frame — no
  `isAnimating` check, no awaited animation, no `Future.delayed`. Keep it that
  way. The burst UI (`RepBurstController`) only mirrors `output.count`.
- **No cooldown longer than phase confirmation.** Historical bug:
  `PushupsValidator._repCooldownFrames` was `3` while `_phaseStableFrames` was
  `2` — the post-rep cooldown outlasted the next rep's own active-confirmation
  window and swallowed legitimately fast back-to-back pushups (5 counted as 3).
  Rule: **any per-rep cooldown must be `< phaseStableFrames`**. Now
  `_repCooldownFrames = _phaseStableFrames - 1`.
- **Frame-count based, never wall-clock.** State machines here count frames, so
  they scale with whatever effective FPS the device delivers instead of
  penalising a fast cadence. `HoldTimerStateMachine` (plank) is the only
  time-based one, and that's a duration score by design.
- **Fast threshold crossings.** A fast rep can jump past a narrow intermediate
  pose between two processed frames. Prefer "crossed" logic
  (`prev > threshold && curr < threshold`) or a wide dead-zone with short
  `stableFrames` over requiring the body to land inside a tight band. The
  cadence signal (§F) is inherently crossing-tolerant — it reads a continuous
  left/right difference, not a landing pose.

---

## E. Double-count protection

Every rep/cadence verifier must satisfy:

- one real movement → **exactly 1** count, even with noisy boundary frames
- a held phase (bottom of a squat, top of a calf raise, knee held up) → **no
  repeated counts**
- a fast real second rep → counts **immediately** after the first (no artificial
  gap)
- starting mid-movement (already crouched) → 0 until a clean start pose is seen

Mechanisms: hysteresis (distinct enter/exit thresholds with a dead zone),
`stableFrames` persistence, a physical reset requirement (`RepCounterStateMachine`
needs `start → active → start`; `CadenceDetector` needs a genuine side switch),
and phase progression for multi-phase.

---

## F. Body-relative measurements — no raw pixel thresholds

Normalize against stable body geometry:

- **hip width** — `PoseFeatureExtractor.hipWidth` (horizontal, stable across a
  rep)
- **torso height** — `PoseFeatureExtractor.torsoHeight` (shoulder→hip span)
- shoulder width, joint angles (`kneeAngle`, `elbowAngle`)
- **left-vs-right relative differences** — the strongest signal for alternating
  motion

### Worked example — the cadence bug and its fix

Original `kneeAlternationSide` asked "is the knee near hip level?"
(`knee.y < hip.y + hipWidth * fraction`). On a real phone camera a normal
running/marching cadence **never brings a knee that high** — it was tuned to
synthetic poses that lifted one thigh halfway to the hip. Nothing counted
on-device.

Fix #1 (`kneeAlternationSide`) read the **difference in height between the two
knees** (`rightKnee.y - leftKnee.y` vs `hipWidth * liftFraction`). Still used
by Walking `0.30` / Marching `0.65` / Step-Ups `0.65` / Mountain Climbers
`0.55`.

Fix #2 (real session `ms_64c7b6ee…`, 2026-09-07): a 37 s continuous
treadmill-style run counted **2 of ~77**. Two failures compounded — the
athlete was small in frame so `hipWidth` collapsed to ~0.02 and the threshold
floored at an absolute `0.033`; and the run showed up almost entirely as a
**horizontal** knee swing (`Δx ≈ ±0.11`) with a near-zero vertical stagger
(`Δy` p10..p90 = −0.004..+0.038), so a purely vertical signal sat in its dead
zone. Running in Place + Treadmill Running now use the stateful
`AlternatingGaitSignal`:

- body scale = **torso height** (hip↔shoulder), clamped — stable when
  hip-width-in-x is not (add shoulders to `requiredLandmarks`);
- signal = `(Δx − centreΔx) + Δy` of the knee pair. The axes are positively
  correlated mid-stride, so summing reinforces the step; `Δx` is measured
  against a first-frame-seeded slow centre (absorbs a static stance / lean),
  `Δy` is raw (a level rest pose already sits at ~0 — subtracting a lagging
  centre is what makes a return-to-neutral misread as the opposite side);
- side emitted when the swing clears `torso * 0.18`; `CadenceDetector` still
  owns the stable-frame + alternation counting.

Lesson: a good signal describes **what changes during the movement relative to
the body**, not an idealised target pose — and *which axis* carries that
change depends on the camera, so don't bet the whole signal on one.
Regression fixture: `test/fixtures/treadmill_running_session_ms_64c7b6ee.json`
+ `test/treadmill_running_real_session_test.dart`.

---

## G. Landmark requirements

- `criticalPoints` (the validator's `List<String> get criticalPoints`) should
  list **only the landmarks the motion actually needs**. `_BaseValidator.update`
  skips a frame (reason `missing_landmarks`) if any are absent — don't require
  ankles for an arm motion.
- A gotcha: if `analyzeValidFrame` calls `features.torsoHeight` /
  `features.shoulderY` etc., shoulders **must** be in `criticalPoints` —
  `PoseFeatureExtractor._averageY` unwraps with `!` and will crash otherwise.
  (`CalfRaisesValidator` had exactly this bug — needs shoulders for the torso
  reference.)
- Do **not** change `_BaseValidator.fullBodyVisible` (avg landmark likelihood
  ≥ 0.70) for one preset — that's shared with the locked three. If a preset
  needs a looser gate, override `fullBodyVisible` (or the visibility logic)
  locally in that validator.

---

## H. Realistic test requirements

Add the motion to `test/preset_motion_expansion_test.dart`. Every scenario must
run through `createMotionValidator` (never a bespoke path) and layer realistic
pose noise — the harness's `_noisy()` applies per-joint jitter, ~6%/frame single
landmark dropout, slow scale + root-translation drift, and per-frame confidence
wobble. Use realistic amplitudes (a gait knee lift staggers the knees ~0.15 of
frame height — the knee does **not** reach the hip).

Per preset:

```text
idle → 0
one valid rep → 1
multiple valid reps → exact
partial rep → 0
held phase → no extra count
wrong movement → 0
slow / normal / fast (at the 2-frame stableFrames floor) → exact
jitter → still exact
brief 1–3 frame landmark dropout → recovers
small scale change → still works
small root translation → still works (for motions that don't depend on it)
one clean rep + noisy ending → exactly 1
```

For cadence motions additionally:

```text
left-only repeated → 0
right-only repeated → 0
valid left-right alternation → exact
rapid alternation at the floor → exact
same-side jitter (never 2 consecutive) → 0
```

Also extend `test/fast_rep_replay_test.dart` for a representative new preset (5
back-to-back at the frame floor → exactly 5; one frame short of the floor → 0).

---

## I. Cross-motion negatives

Test each new preset against the movements it's most likely to be confused with,
and **measure the overlap honestly** rather than claiming a clean separation
where pose-only data fundamentally overlaps:

```text
running vs walking          walking vs marching
running vs marching         marching vs high knees
step-ups vs high knees      step-ups vs marching
mountain climbers vs high knees (the plank-posture gate is the discriminator)
burpees vs squats           lateral steps vs a repositioning shuffle
calf raises vs idle jitter  butt kicks vs a high-knee raise
```

Known accepted limitation (documented in the tests, not hidden): from a front
camera, jog / march / step-up are nearly the same signal at nearly the same
amplitude — the real difference is tempo, which isn't measured.

---

## J. Diagnostics contract

Every validator's `debugValues` (surfaced in the assert-gated
`[NuvoVerify]` log and the `kDebugMode` overlay in `ai_motion_proof_screen_io.dart`)
must expose enough to explain a failure from one copied log:

```text
state / phase          count
relevant body metric   last transition
```

Cadence validators (`CadenceMotionValidator.debugValues`) expose:

```text
measuredSide   currentSide   kneeStagger (raw signal)   cycles   repIntervalFrames
```

A device log showing `kneeStagger` hovering near 0 means "not enough knee
lift", not "wrong movement". The screen also logs, via `PoseDetectorService`:
`framesReceived / framesProcessed / framesDropped / effectiveVerifierFPS` and a
`RepEventLog` ring buffer of the last rep timestamps + intervals.

### J2. Motion Session telemetry — every attempt is uploaded

`ai_motion_proof_screen_io.dart` records **every** preset/custom verification
attempt into a `MotionSessionArtifact`
(`lib/features/races/ai/motion_session/`) — the landmark stream the verifier
evaluated plus its decision trace (`rep_counted` / `validator_state` /
`readiness` / `rejection` events with `debugValues` metrics) plus the final
result, versions and device info. It is a schema-versioned, gzip'd document
(`kMotionSessionSchema`); the same object feeds the debug-only "Share session"
export and the automatic upload.

- `MotionSessionRecorder`: `start()` with the camera, `recordFrame(...)` per
  processed frame, `finish(...)` on result / `dispose` (abandoned →
  `incomplete`), `build()` → artifact.
- `MotionSessionUploadQueue` (`motionSessionUploadQueueProvider`): stages the
  blob + a metadata sidecar under app-documents, uploads best-effort, retries
  everything staged on the next launch / verification. Never awaited from the
  frame path.
- Wire: `POST /motion-sessions` (JWT) → R2 `motion-sessions/<user>/<id>.json.gz`
  + D1 `motion_sessions` index row (migration `0013`).
- Retrieval (support / coding agent), gated on `X-Internal-Key` ==
  `INTERNAL_API_KEY` wrangler secret:
  - `GET /internal/users/resolve?email=|username=|id=`
  - `GET /internal/users/:id/motion-sessions[?activityId=&outcome=]`
  - `GET /internal/users/:id/motion-sessions/latest[?activityId=]`
  - `GET /internal/motion-sessions/:sessionId`
  - `GET /internal/motion-sessions/failed`
  - `GET /internal/activities/:activityId/motion-sessions/latest`
  Each returns `{ session, metadata, artifact }` — the artifact is the
  decompressed JSON, so no phone log is needed to diagnose.

When adding a preset, nothing extra is required here — the recorder is
activity-agnostic. Just make sure your validator's `debugValues` are
meaningful (§J), because they land in the uploaded `events[].metrics`.

---

## K. Full-route acceptance — hard rule

A preset is **NOT done** when its validator test passes. It is done when:

```text
appears in the composer picker
  → race can be created (no "Choose a supported activity")
    → race loads back
      → proof screen opens
        → verifier factory picks the right validator
          → count works on a realistic pose stream
```

Run `test/preset_registration_contract_test.dart` and read its `PRESET ROUTE
AUDIT` — every row must be all-`yes`. Then **deploy the Worker** (§B #14) and
`curl` the production `/races/activities` to confirm the new id landed. A
green local test proves the *source* is right, not that production is
running it.

---

## L2. Measurement model — the catalog owns "unit", not the screens

`MotionActivityDefinition` carries the measurement model so the composer
prompt, race card, leaderboard and progress all read one source (this is how
plank ended up showing "reps" — every screen decided for itself):

- `measurementType` — `MotionMeasurementType.repetitions` | `.duration`. Null →
  derived from `metric` (so a `RaceMetric.seconds` activity like plank becomes
  `duration` automatically). `distance` / `steps` / `calories` / `completion`
  are documented future types with **no consumer and no Worker support** — do
  not add them speculatively.
- `goalPromptOverride` — the composer question. Null → `defaultGoalPrompt`:
  repetitions → `"How many <title>?"`, duration → `"How long?"`. Gait movements
  set `"How many steps?"`.
- `displayUnitOverride` — the noun ("steps", "kicks"). Null →
  `measurementType.defaultPluralUnit`. **Does not change serialization** — the
  wire `metric` is always `measurementType.raceMetric` (`reps`/`seconds`), so
  no Worker change is needed for a units tweak.

Format via the helpers in `motion_activity.dart` (`formatMotionTarget`,
`formatMotionProgress`, `formatMotionGoalOption`, `formatClock`,
`formatDurationShort/Long`) and the `Race`-level wrappers in `race_display.dart`
(`raceMeasurementType`, `raceDisplayUnit`, `raceProgressLabel`,
`raceTargetLabel`, `raceScoreLabel`). Never hand-format `"$value $unit"` in a
screen. `test/motion_measurement_test.dart` asserts every catalog entry has a
sane model.

## L. Count semantics — must be explicit, one convention per family

Documented in `test/preset_registration_contract_test.dart` `_countSemantics`
(the test asserts every catalog entry has an entry). The conventions:

| Family | 1 count = |
|---|---|
| Rep motions (pushup, squat, lunge, arm raise, calf raise, deep/sumo squat, squat jack, jump squat, lunge jump) | one full rep (start → range → start) |
| High Knees | one knee raise (either leg) |
| Cadence (running, treadmill, walking, marching, step-ups, butt kicks, mountain climbers, lateral steps) | **one confirmed alternation step** — a left+right cycle is 2 |
| Burpees | one full rep (stand → down → stand) |
| Plank | one second of valid hold |

Cadence uses the same convention as High Knees deliberately — related
activities must not have invisible per-movement differences.

---

## M. Definition of Done — report template

Every preset PR/task must report:

```text
Preset:
Identifier (backendValue):
Verifier type:                 (rep state machine / cadence / multi-phase / hold)
Count semantics:
Goal unit:
Registration points updated:   (list from §B)
Verifier logic:                (state machine, thresholds, signal, reset)
Fast-rep result:               (5 back-to-back at the frame floor)
Double-count result:           (one rep + noisy ending → 1; held phase → no spam)
Noise result:                  (jitter / dropout / scale / translation)
Wrong-motion negatives:        (measured, with any accepted overlap named)
Full-route create/load/proof:  (PRESET ROUTE AUDIT row)
Worker:                        (tests: N/N  ·  deployed version id: ...  ·  /races/activities confirms id: yes)
Known limitations:
Build:                         (flutter analyze lib/ + flutter build ios --release + server npm test)
Commit:
```

Do not write "structurally sound." Write e.g.:

> `Running in Place — before: knee threshold required the knee near hip level,
> so normal phone cadence never armed (0 counts on device). After:
> left-vs-right knee-height-difference signal (hipWidth·0.55), CadenceDetector
> stableFrames 2, alternation-required. 8–10/10 normal, ≥6/10 fast, idle 0,
> left-only 0, shallow-walk-on-marching 0.`
