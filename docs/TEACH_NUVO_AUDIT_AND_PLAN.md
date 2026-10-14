# Teach Nuvo / custom movements — audit and fix plan

Audited from code and by running probes (2026-10-14). Items marked **(unverified)**
need device screenshots; I have not seen the screens that looked broken.

## 1. Findings

### A. A movement name becomes a text goal (verified)
`interpretRaceName` only knows the 24 catalog movements. Anything else is a
`manual` goal (honor-logged text), never a movement. Probe of `resolveRaceIntent`:

| typed | result |
|---|---|
| pull ups / most pull ups / first to 50 pull ups | manual goal "Pullups", reps |
| dips, sit ups, box jumps, pistol squats, kettlebell swings, wall sit | manual goal |
| bicep curls | manual goal, unit **lb** |
| jump rope in 60 seconds | manual goal named "Jump Rope In", unit "in" |
| push ups, mountain climbers | movement (catalog) — correct |

`RaceIntentPath` has only `movement | customGoal | ambiguous`: there is no path for
"a physical movement Nuvo doesn't have yet", so the composer can't offer Teach Nuvo
unless the user finds the card themselves.

### B. Composer → Teach flow
`name → activity → (teachMode: name + unit form) → train → /races/teach → goal → racers → review`.
- The name typed on step 1 is asked for again in the Teach form.
- Teach only starts after the user finds the "Teach Nuvo" card.
- `train` is a waiting page between two screens (dead end if the user backs out).
- Errors were raw strings (`Learning failed: Invalid argument(s)…`).
- `teach_movement_screen.dart` is 2,584 lines mixing capture, V1 build, V2 learn,
  live test and a debug panel. **(unverified)** which screens looked broken.

### C. Two matchers, only one is used for races (verified)
- **V1** (`custom_pose/`, hand-built pose features + similarity thresholds) builds the
  `CustomPoseVerifierSpec` that Teach returns to the composer. `_goToRaceCreation`
  hands back `_effectiveSpec` = V1. The proof screen / `verifier_runtime` run V1.
- **V2** (MotionBERT encoder + multi-reference matcher) is referenced only inside
  `teach_movement_screen.dart` (learn + live test + diagnostics). No race verification
  path uses V2. So improving V2 does not improve verified races today.
- The V2 failure (ONNX Runtime symbol stripped on iOS release) blocked the Teach
  screen even though V1 was fine. Fixed in `d32f7a8`/`c4a052b`; device check pending.

### D. What reaches Cloudflare today (verified)
| data | stored? |
|---|---|
| final V1 spec (`races.verifier_spec_json`) | yes, with the race |
| verification session frames + events (`motion_sessions`, kind custom) | yes, **only if the user opted in** (`motion_training_consent`) and only after a verification |
| the 3 teaching demos (raw landmarks) | **no** |
| V2 learned spec / embeddings, self-validation, live-test result | **no** |
| Teach failures / "too different" / learning errors | **no** (nothing server-side) |
| labels (was this attempt right?) | **no** |
No Worker route or table exists for teach captures. Pull tools exist only for sessions
(`session-latest`, `sessions-failed`).

## 2. Fix plan (phases, in order)

**P0 — done.** ONNX Runtime kept in the iOS binary; V2 failure falls back to V1.
Needs one release build on a phone to confirm.

**P1 — read movements as movements (app only).**
- New intent path `teachableMovement`: a lexicon of exercise nouns/verbs plus
  "N <x>", "most <x>", "<x> in 60 seconds" shapes; unit forced to reps/seconds,
  never `lb`/"in".
- Composer: name prefilled, no second name prompt; primary action "Teach Nuvo this",
  secondary "Count it by hand".
- Tests: the 40+ phrase probe above as a regression table. Files: `race_name_interpreter`,
  `race_intent`, `race_composer_screen`. Risk: medium (interpreter has 350 benchmark tests).

**P2 — Teach screens and flow cleanup (app only; needs screenshots first).**
One linear flow: Intro (camera tips) → Record ×3 (clear progress, retake) → Learning →
Result (works / try again with the reason) → Live test → Use it. Remove the dead
`train` page, hide debug UI in release, replace every raw error, make back/retry
consistent. Split `teach_movement_screen.dart` into stage widgets.

**P3 — capture everything in Cloudflare (Worker + app).**
New consent-gated endpoint + table for teach captures: raw demos (landmarks only),
V2 spec, self-validation, live-test results, learning errors with reason, model and
app versions; same encryption as motion sessions. Internal read routes and CLI
(`teach-list`, `teach-get`), and the replay tool opens them. Failed teaches are
recorded too, so we can see where the AI messed up.

**P4 — make the AI good, with data.**
Using P3 data, evaluate V1 vs V2 offline (Python + ONNX env already set up),
decide whether to wire V2 into race verification (needs a change to the no-touch
proof screen), and ship model/matcher changes through System B (model swap, OTA).

## 3. Decisions needed
1. Wire V2 into verification (better AI, bigger change) or keep V1 for races and use
   V2 only as the quality gate?
2. Teach captures: same opt-in consent as sessions, or require it for Teach (it is the
   user's own movement, landmarks only)?
3. Screenshots of every screen that looked broken (P2 depends on them).

## 4. Status (updated)
- **P0 done** (ORT link + V1 fallback) — device check pending.
- **P1 done** — `teachableMovement` intent path (`teachable_movements.dart`), 17 positive and
  25 negative regression phrases, benchmark 350/350. The composer asks ONE centred question
  ("Count Pull Ups with the camera?" → Teach Nuvo / Count it by hand / Pick a different movement).
- **P2 started** — shared `NuvoFocusedStage` (centred, scroll-safe); used by the composer's teach
  question, custom-movement form and training page, and by Teach Nuvo's intro, name, learning,
  failed and learned screens. The raw native error is gone. Still open: the live-test camera
  overlays and the capture screen chrome (need device screenshots); P4.
- **P3 done (code path; needs migration + device data)** — teach sessions upload like motion
  sessions. `motion_teach_sessions` (0045) + `POST /teach-sessions` (consent-gated, encrypted
  artifact in R2) + internal `GET /internal/teach-sessions[/:id|/users/:id]` + CLI
  `teach-list`/`teach-get`. The app records the full diagnostic session on every teach attempt
  (no longer behind `NUVO_DIAGNOSTICS`), and schema 2 adds the V1 half: the
  `CustomPoseVerifierSpec` the race actually verifies with, the builder diagnostics, the test
  result, the engine that ran (`v2|v1|v1_fallback`), the outcome
  (`used|learned|failed|abandoned`) and the failure stage. `teach-get` writes a `.json.gz`
  `tools/motion_v2/replay_session.py` opens directly. Before data flows: run migration 0045
  on prod D1 and redeploy the Worker.
