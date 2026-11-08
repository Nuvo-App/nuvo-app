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

- S6 Crew tab + crew page (merge af91a93), S8 Activity + auth/onboarding/splash restyle (merge 1a1eac6). Orchestrator QA fixes: composer empty name field + live "auto" chips (7cc3453), toast/overlay underline (995c17a), compact V13Button no longer stretches, race detail full-width CTA.
- S9 cleanup (merge, this commit): NUVO_V13 flag removed; 39 lib files that became unreachable from lib/main.dart deleted (import-graph walk, tool in redesign-orch/tools/unreachable.py); 46 test files that only covered deleted screens removed, mixed logic tests pruned case-by-case; shell_motion_test now drives V13TabBar. Full suite: 2242 tests, 16 known pre-existing failures, 0 new.

- S10 restyle (merges a1fb8ab r2 races, 1d93f2d r1 social, 5a4909c r3 badges/teach) + QA: /race/:id/proof now opens Race detail with the v13 Submit proof sheet (old SubmitProofScreen deleted, 82a47e2); old core widgets left dead by the restyle deleted (f1c1014); faces on requests and feed items open profiles (8e8cd36); pre-v13 first-race coach tour retired (dd1f388).
- Final state (dd1f388): flutter analyze 0 errors / 0 warnings; flutter test 2196 tests, only the 16 pre-existing failures in tool/ci/known_failing_tests.txt; worker npm test 586/586; GitHub Actions CI green.

## Not built / open
- Crew battle (W4): no backend yet. The Crew page only renders the section when the API sends an active battle, so nothing dead shows.
- AI Motion Proof camera screen (no-touch) keeps its pre-v13 chrome. Restyling only its chrome needs Akshay's explicit approval for that file.
- Device QA on a physical iPhone (Mac thread) has not been done; everything here is verified with analyzer, widget tests and real-font screenshots.

## Blocked / needs Akshay
- Production Worker deploy + prod D1 migrations 0048_v13_profile and 0049_v13_crews (plus the older unapplied 0047_reconcile_prod). The v13 app needs these endpoints in prod; until then the new sections hide themselves. Dev (nuvo-api-dev) is deployed and at 0049.
- Merging redesign/v13 into main (no PR opened yet).
- Devin weekly quota on the paid models is used up; agents run on the free SWE-2 Max model, with closer orchestrator review.

## Baseline (pre-existing, not caused by the redesign)
- `flutter analyze`: 0 errors, 7 warnings (test files), 117 infos.
- `flutter test`: 21 failing tests on the base commit (motion benchmarks/animation demos); list in `tool/ci/known_failing_tests.txt` (S1).
- Worker `npm test`: 535/535 pass.

## Adaptations
See FEASIBILITY.md §2 (A1–A17).

## pubspec changes
None.
