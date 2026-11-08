# v13 redesign — progress

Branch: `redesign/v13` (base `motion-ota-tuning` 0a6f761). Plan: `FEASIBILITY.md`.

## Done
- Phase A: spec (eca532e), area specs + inventory (a7aa8b1, 1a23452, ca247d7), activity/onboarding spec + feasibility (this commit).

## In progress
- S3 design system, W1 worker profile, W3 worker races (Devin, parallel).

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
