# v13 redesign — progress

Branch: `redesign/v13` (base `motion-ota-tuning` 0a6f761). Plan: `FEASIBILITY.md`.

## Done
- Phase A: spec (eca532e), area specs + inventory (a7aa8b1, 1a23452, ca247d7), activity/onboarding spec + feasibility (this commit).

- S1 CI (9f2c611, merge feb71d0): GitHub Actions — analyze, flutter test gated on tool/ci/known_failing_tests.txt, worker typecheck + tests. Test-file analyzer warnings 7 → 0.
- W3 worker races (276f4c5, merge 47b40fa): GET /races/open, GET /leaderboard?scope=friends, racesTogether on GET /crew, racerCount on activities, viewerContext.previousRank; friends of any racer may read/join crew_only races (blocks respected). 550/550 worker tests. Not yet deployed to dev.
- S3 design system (ba9bf12, merge b7b350f): lib/core/v13 tokens/motion/26 widgets, kNuvoV13 flag constant, openPerson helper; 41 widget tests.

- W1 worker profile (709ba8f + crew-race fix, merge 2c96265): migration 0048, bio/favorite movement/activity-map/who-can-race-me prefs, day streaks, public profile bundle (mutuals, versus, friendship badges, locked achievements), GET /users/:id/activity, mutes (feed + notification suppression).
- W2 worker crews (bbc2ed7, merge 9eccde0): migration 0049, crew identity, week/all-time standings, discover/preview, join requests + approve/decline, mute, report crew, recurring crew races + auto-join + cron spawn, badge_earned feed items, mutuals on requests. 586/586 worker tests.
- Dev deploy: nuvo-api-dev version 848b2d12 (dev D1 now at 0049; 0044-0047 were also pending on dev and applied there). Production untouched.
- S2 v13 shell (merge 967a175): Crew tab label on the /pass route (auth_gate protects /pass; /crew redirects), V13TabBar, light-only. CI runs the pre-v13 suite with NUVO_V13=false.
- S5 Compete/New race/Race detail/Submit proof (merge f5637f3), S4 Arena (merge 51a2226), S7 Profile cluster (merge 8ca2475) + orchestrator polish (befa31d, c9ab97b): screenshots reviewed with real fonts; fixed collapsed progress bars, extra blue actions, profile section spacing, duplicate delete-account row.

## In progress
- S6 Crew tab + crew page, S8 Activity/onboarding/auth restyle (Devin, 2 at a time on free SWE-2 with auto-resume on rate limits).
- Next: S9 delete old screens + remove flag, S10 QA.

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
