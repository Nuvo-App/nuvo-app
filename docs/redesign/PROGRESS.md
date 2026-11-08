# v13 redesign — progress

Branch: `redesign/v13` (base `motion-ota-tuning` 0a6f761). Plan: `FEASIBILITY.md`.

## Done
- Phase A: spec (eca532e), area specs + inventory (a7aa8b1, 1a23452, ca247d7), activity/onboarding spec + feasibility (this commit).

- S1 CI (9f2c611, merge feb71d0): GitHub Actions — analyze, flutter test gated on tool/ci/known_failing_tests.txt, worker typecheck + tests. Test-file analyzer warnings 7 → 0.
- W3 worker races (276f4c5, merge 47b40fa): GET /races/open, GET /leaderboard?scope=friends, racesTogether on GET /crew, racerCount on activities, viewerContext.previousRank; friends of any racer may read/join crew_only races (blocks respected). 550/550 worker tests. Not yet deployed to dev.
- S3 design system (ba9bf12, merge b7b350f): lib/core/v13 tokens/motion/26 widgets, kNuvoV13 flag constant, openPerson helper; 41 widget tests.

## In progress
- W1 worker profile, W2 worker crews (Devin).
- S2 flag + v13 shell, S4 Arena, S5 Compete/New race/Race detail/Submit proof (Devin, parallel). Screen stages don't edit router.dart; the orchestrator wires routes at merge.
- Queued: S6 Crew, S7 Profile, S8 Activity/onboarding (machine has 4 CPUs, so at most 3 Flutter agents run at once).

## Blocked / needs Akshay
- Production Worker deploy + D1 migrations 0048+ (dev only until approved).
- Devin weekly quota on the paid models is used up; agents run on the free SWE-2 Max model, with closer orchestrator review.

## Baseline (pre-existing, not caused by the redesign)
- `flutter analyze`: 0 errors, 7 warnings (test files), 117 infos.
- `flutter test`: 21 failing tests on the base commit (motion benchmarks/animation demos); list in `tool/ci/known_failing_tests.txt` (S1).
- Worker `npm test`: 535/535 pass.

## Adaptations
See FEASIBILITY.md §2 (A1–A17).

## pubspec changes
None.
