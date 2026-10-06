# Batch B — Motion Conversion Report

Additive migration study: can the 11 hand-written Batch-B validators be
replaced by Cloudflare-editable declarative releases that behave identically?

The 0026 revert was caused by fixed normalized-coordinate rules
(`leftKnee.y >= 0.78`) that are blind to camera distance and body scale. Every
spec below uses only body-relative features — `angle`, `axis_delta`, and
`segment_ratio` on `sequence_match_v1` — so the exact failure mode of 0016 is
excluded by construction (the Worker-side test asserts no `landmark_axis`
predicate and no raw rule lists exist anywhere in the specs).

**Scope of proof:** equivalence is proven on synthetic pose sequences
(parametric generators + the app's own preview keyframes), covering full
reps, partial reps, idle, jitter, camera scale 0.6x–1.4x, translation, and
body-proportion variation ±15%. **The owner must still validate each motion
on physical devices before any promotion** — these results are necessary but
not sufficient evidence for a channel change.

Artifacts:

- Specs: `server/worker/motion-releases/<activity>-remote-2026.10.0.json`
- Differential tests: `test/motion_conversion/<activity>_equivalence_test.dart`
- Shared harness: `test/motion_conversion/conversion_support.dart`,
  `conversion_poses.dart`, `signal_calibration_test.dart`
- Worker validation: `server/worker/test/motion_release_batch_b.test.mjs`
- SQL draft: `server/worker/migrations/DRAFT_converted_remote_releases_batch_b.sql`
  (deliberately un-numbered; inserts `status='draft'` rows only, never touches
  `activity_channel_releases`; checksums from
  `scripts/motion_release_checksums.mjs` = the draft route's
  `sha256:hex(JSON.stringify(spec))`)

## Results

| Motion | Native logic summary | Engine | Expr. | Differential result | Scale robustness | Risks / missing capability |
|---|---|---|---|---|---|---|
| squats | `ConfigurableRepValidator` — start `hipToKnee>0.72`, active `<0.50`, 3-frame stability, dead-zone tolerated | `sequence_match_v1` | **YES** | **PASS 10/10** — 4/4 full, 0/0 partial & idle, scale+translation+morphs exact; harsh jitter diverged 4 vs 3 (tol 1) | exact at 0.6–1.4x, ±15% morphs, shifts | sequence engine resets dwell on any miss (native pauses); reps that linger >8 frames between phases reset — document tempo limit |
| sumo_squats | same counter — adds `ankleW/bodyW>1.5` stance gate (`bodyW=max(shW,hipW)`) | `sequence_match_v1` | **YES** | **PASS 9/9** — 4/4 full, 0/0 narrow-stance deep & partial & idle; harsh jitter 4 vs 2 (tol 2) | exact at 0.6–1.4x, ±15% morphs, shifts | same dwell-reset caveat; `x > T·max(a,b)` is exactly `x>T·a AND x>T·b`, so the stance gate IS expressible |
| squat_jacks | same counter — closed: `wristsNearBody & ankleW/bodyW<1.18 & h2k>0.72`; open: `wristsAboveShoulders & ankleW/bodyW>1.38 & h2k<0.60` | `sequence_match_v1` | **YES** | **PASS 10/10** — 4/4 full, 0/0 arms-down-deep / no-squat / shallow; harsh jitter 4 vs 3 (tol 1) | exact at 0.6–1.4x, ±15% morphs, shifts | arms-up uses `angle(wrist,shoulder,hip)>=120` (~13° down vs ~180° up); the closed stance `x<T·max` is an OR — spec uses the shoulder-width ref alone, marginally stricter when `hipW>shW` |
| push_ups | `PushupsValidator` — elbow >150° start, elbow <125° + shoulderDrop>0.10·movementScale active vs **adaptive top baseline**, 2-frame stability, framing + asymmetry + hands-below gates | `sequence_match_v1` | **PARTIAL** | **PASS 10/10** incl. 4/4 demo keyframes, transforms, harsh jitter 4/4; gap proven: without hips native=3 remote=0 | exact at 0.6–1.4x, ±15% morphs | missing: (a) adaptive per-session baseline predicate, (b) frame-edge/framing gate, (c) left-vs-right asymmetry tolerance, (d) optional landmarks — spec must require hips for its depth ratio while native treats them as optional |
| side_lunges | same counter — start both knees >154°, active `kneeSep/hipW>0.85 AND (kneeL<118 OR kneeR<118)` | `sequence_match_v1` | **PARTIAL** | **PASS 9/9** — 6/6 alternating, 0/0 idle & narrow; gap proven: wide straight-leg stance counts remote=3 native=0 | exact at 0.6–1.4x, ±15% morphs | missing: phase predicate disjunction ("either knee bent") or parallel alternative phases — the spec approximates the active phase by separation alone and accepts a wide stance with straight legs |
| plank_hold | `PlankHoldValidator` — HoldTimer + collinearity (hip/knee deviation from shoulder-ankle line <0.16/0.18), avg knee angle >148°, pause/resume on form loss | none | **NO** | native holds 2s/90f; best-effort `hold_v1` fixed-band holds nominal but **remote=0** under −0.15 translation and **holds a sagging hip** (native=0, remote=2) | n/a | missing: derived predicates (`angle`/`segment_ratio` = collinearity) inside `hold_v1` rules — `holdRules` only accepts raw point/axis thresholds |
| running_in_place | `CadenceMotionValidator` — `AlternatingGaitSignal` (swing=(Δx−centre)+Δy vs torso·0.18, adaptive baseline) + CadenceDetector(2) | none | **NO** | native=11 on 6 cycles; naive `alternating_rep_v1` (fixed y<0.56) works nominally but **remote=0** at +0.08 translation and **over-counts** at −0.08 | n/a | missing: stateful torso-normalized alternating-swing feature (baseline-adaptive Δx+Δy of a landmark pair) |
| treadmill_running | same gait signal + `VirtualDistanceEstimator` — `currentValue` is **metres**, not reps | none | **NO** | native=13 m on 8 cycles; naive spec remote=0 under same translation | n/a | missing: the gait feature above **plus** a distance-measurement runtime (`measurementType:'distance'` doesn't exist for remote specs) |
| walking_in_place | same gait signal, `liftFraction 0.12` | none | **NO** | native=11; naive remote=0 under +0.08 translation | n/a | missing: same stateful gait feature |
| step_ups | same gait signal, `liftFraction 0.30` (deliberate march) | none | **NO** | native=11 (and correctly 0 at shallow lift=0.5, which walk accepts) | n/a | missing: same stateful gait feature |
| mountain_climbers | `MountainClimbersValidator` — plank-context (torso off-vertical + hands-near-shoulders), knee-drive projected onto the torso axis, alternating via CadenceDetector(2) | none | **NO** | native=11 on 6 alternating drives; naive remote=0 under +0.08 translation | n/a | missing: projection of a landmark onto a derived body axis, a stateful left-vs-right drive-difference signal, and a contextual hand-support gate — none exist as predicates |

## Engine/feature findings that shaped the verdicts

- `sequence_match_v1` is the only generic engine with scale-invariant
  predicates. `state_machine_v1`, `alternating_rep_v1`, and `hold_v1` accept
  only `landmark_axis`-style raw-coordinate rules — the 0016 format that 0026
  reverted. This alone confines every YES/PARTIAL candidate to the sequence
  engine.
- Phase predicates are strictly conjunctive and the chain is strictly linear.
  `x > T·max(a,b)` encodes exactly (`x>T·a AND x>T·b`); `x < T·max(a,b)` does
  NOT (it is an OR). The squat-jacks closed-stance gate uses the shoulder ref
  alone — a documented, mildly conservative approximation for hip-wider-than-
  shoulder bodies.
- The sequence engine is tempo-sensitive where the native is not: a phase
  resets after `breakToleranceFrames` (max 8) consecutive misses, while the
  native `RepCounterStateMachine` ignores dead-zone frames indefinitely. Very
  slow reps and harsh jitter are the residual divergence (quantified above).
- `CadenceDetector` counts each confirmed side switch — a full left-right
  cycle is 2 counts — and `alternating_rep_v1` counts the first side too
  (off-by-one by design even before the coordinate problem).
- `hold_v1` reports held seconds only through the update object
  (`rt.count` stays 0) — `runRemote` reads the last update, matching
  `currentValue` semantics.

## Exact app-release requirements for the unconverted motions

1. **`gait_swing` feature kind** (running, treadmill, walking, step_ups):
   a stateful per-session signal `(Δx−centreDx)+Δy` of the knee pair
   normalized by torso height, with the native's adaptive-centre update
   (alpha 0.04) and vertical tilt trim (alpha 0.01), plus a per-motion
   `liftFraction` threshold — then an alternating engine that consumes it.
2. **Distance measurement** (treadmill): a `measurementType:'distance'` spec
   field and a runtime equivalent of `VirtualDistanceEstimator` integrating
   confirmed steps into metres.
3. **Derived predicates in `hold_v1`** (plank_hold): allow `angle`,
   `axis_delta`, `segment_ratio` in `holdRules` with the existing duration
   accumulation and pause-on-form-loss semantics — equivalently, a
   line-deviation predicate (`point_from_line(a, refA, refB) / |refA-refB|`).
4. **Predicate disjunction or parallel branches** (side_lunges): phase
   alternatives — e.g. `predicates: [[…left…],[…right…]]` — or a `min`/`max`
   combinator over per-side signals, so "either knee <118°" is expressible.
5. **Adaptive baseline + context gates** (push_ups, mountain_climbers):
   a session-seeded reference predicate (e.g. `baseline(a)` = per-session
   calibration) and framing/asymmetry gates; climbers additionally need
   projection onto a derived body axis (`project(point, onto: [a,b])`).
   Without (5) the push_ups draft cannot reproduce the native's shoulder-drop
   or framing requirements — its PARTIAL marking stands even though counting
   matched on synthetic data.

## Ready for device validation

Differential tests pass; specs are drafted (not promoted). Each row still
requires on-device owner validation before any channel change:

- squats — `squats-remote-2026.10.0` (draft)
- sumo_squats — `sumo_squats-remote-2026.10.0` (draft)
- squat_jacks — `squat_jacks-remote-2026.10.0` (draft)
- push_ups — `push_ups-remote-2026.10.0` (draft, PARTIAL: no adaptive
  baseline / framing / asymmetry gates; requires hips the native treats as
  optional — validate with real camera framing before deciding)
- side_lunges — `side_lunges-remote-2026.10.0` (draft, PARTIAL: accepts a
  wide straight-leg stance the native rejects — judge whether the
  over-acceptance is tolerable for the use case)

## Needs an app release first (blocking before the App Store build)

No spec drafted — the shipped engines cannot express the native signal:

- plank_hold — needs derived predicates in `hold_v1` (requirement 3)
- running_in_place — needs `gait_swing` (requirement 1)
- treadmill_running — needs `gait_swing` + distance measurement (1, 2)
- walking_in_place — needs `gait_swing` (1)
- step_ups — needs `gait_swing` (1)
- mountain_climbers — needs body-axis projection + context gate + alternation (5)

## Verification run (real output)

- `flutter test test/motion_conversion/` — **68 tests, all passed**
  (10 YES/PARTIAL suites of equivalence cases + 6 NO gap-quantification
  suites + calibration probe).
- `cd server/worker && npm test` — **331 pass / 0 fail** (incl. the new
  `motion_release_batch_b.test.mjs`: all 5 specs pass
  `validateMotionVerifierSpec`, no `landmark_axis` anywhere, checksums are
  `sha256:`-prefixed hex of `JSON.stringify(spec)`).
- `cd server/worker && npm run typecheck` — clean.
- `flutter analyze --no-fatal-infos` — **no new issues** in any touched file
  (2 early warnings fixed: unused locals).
- `git diff` on existing production files: **empty** — every file added is
  new (specs, tests, draft SQL, report, checksum script).
- DRAFT SQL verified against the real `verifier_releases` schema in-memory:
  5 `draft` rows, `parent_release_id` = the `*-legacy-2026.09.0` releases,
  `activity_channel_releases` untouched (0 rows).

## Honest limitations

- Pose sequences are synthetic. They exercise geometry, scale, translation,
  proportion, and noise — but not real MLKit failure modes (temporal dropouts,
  left/right mirroring, occlusions). On-device validation is still required.
- Jitter divergences are real engine semantics, not test artefacts: the
  sequence engine resets consecutive-dwell on a miss; the native pauses on
  unknown frames. At `PoseNoise.harsh` the remote counts 1–2 fewer reps than
  native over 4 — users grinding noisy reps on a cheap camera may see fewer
  counts than today.
- The demo keyframe tests drive authored poses through parametric timing —
  the demo clock itself lingers at depth longer than the 8-frame miss budget,
  so timing equivalence is proven on the parametric paths, not the eased demo
  timeline.
