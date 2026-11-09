# Nuvo Onboarding v2 — Build Plan

## Rules
Devin codes, Claude reviews; max 5 Devin agents (2 while throttled), each with at most 2 read-only explore subagents; do not touch AI Motion camera screen logic, validators, or Worker route behavior beyond the additive XP grant; old App Store builds must keep working; branch onboarding/v2 off redesign/v13, sub-branches per part; no merge to main; push only onboarding/v2.

## Architecture
One OnboardingFlow state machine (S1-S16) drives a single OnboardingShell (persistent Track painter, XP rail, fixed CTA slot, transitions). Each step is a small widget reporting completion + XP. TourEngine is a separate overlay with a declarative script. Tokens in NuvoMotion / NuvoHaptics / NuvoSounds. Practice data via TourFixtures. State persists locally and mirrors the existing server onboardingComplete flag; router redirect rule stays "destination depends only on onboarding flags".

## Parts
- **Part 0 Foundation** (Devin A, first and alone, ~1 day): NuvoMotion, NuvoHaptics, NuvoSounds, OnboardingShell (Track painter, XP rail, fixed CTA slot, transitions, reduce-motion), OnboardingFlow + persistence, router wiring, feature flag, stub screens for every step, analytics hooks. NOTHING else starts until the shell interface is on onboarding/v2.
- Then parallel:
  - **Part A Intro**: S0 handoff, S1 tap duel, S2 skeleton hero painter, S3 board hero, dots, skip.
  - **Part B Auth visuals**: S4 sheet, S5 ticket, S6 code boxes/stamp/resend/paste, errors/loading, Apple/Google visuals; behavior unchanged.
  - **Part C Player setup**: S7, S8, S9, seed first race template from answers.
  - **Part D Tour**: TourEngine, tour_script.dart, TourFixtures, ghost racer script, GlobalKey anchors, S10-S14, Getting started row, Replay tour in Settings > Help.
  - **Part E Level-up + empties**: S15, XP award animation, share card, S11 sheet, empty-state redesign for Arena/Compete/Crew/heat map/achievements/avatar slot, server idempotent XP grant.
  - **Part F QA**: widget/golden/router/tour-anchor tests, device checklist, perf profile, accessibility, analytics.
- If quota is tight: Cut 1 = Parts 0, B, C, D with a plain celebration; Cut 2 = A and E.

## File ownership
Part 0 owns lib/features/onboarding/shell/** and lib/core/motion/**; A owns .../onboarding/intro/**; B owns lib/features/auth/** (visual layer only); C owns .../onboarding/player/**; D owns lib/features/tour/** and only adds one-line GlobalKey anchors elsewhere; E owns .../onboarding/levelup/** and empty-state widgets. Shared constants (copy, XP table) in onboarding_copy.dart and xp_table.dart, edited only by Part 0 and E. Leave the old 3,354-line nuvo_onboarding_screen.dart in place behind the flag, do not edit it.

## Server (additive)
POST /onboarding/complete grants 100 XP once via an idempotent ledger row keyed onboarding_v2 and returns new level+xp; old builds get the same 200. Read the real XP curve first and size the grant so the user lands on Level 2. Optional onboarding_tour_step column (next free migration) can be skipped for v1. Practice data never goes to the server. Production deploy of additive Worker changes/migrations is pre-approved; merging to main is not.

## Tests
Unit (XP table sums to the Level 2 requirement, step machine, resume after kill at every step, skip tour leaves missions, router redirect order, username validation, OTP boxes paste/autofill/backspace); widget+golden at 390x844 and 320x568, Dynamic Type 1.0 and 1.5; integration (full first run new account, demo/review account still walks the real flow, camera-denied path, offline, old-build compat vs dev Worker); device checks on Akshay's iPhone release build, perf overlay on S1, S2, S3, S15.

## Acceptance
1. No screen has an empty area >120px without a hero or animation.
2. Launch to first Submit proof under 3 min with only name, username, email and 13+ tap required.
3. Every step awards visible XP, rail visible S4-S15, total XP exactly moves a fresh account Level 1 to 2 on the real server.
4. Tour covers Arena (race + Submit proof), Compete, Crew, Profile with one real tap each, only the highlighted target takes touches, Skip after 2s, Replay from Settings.
5. Level-up follows the timeline within 100ms per beat, skippable to CTA after 900ms, real server data.
6. Designed content during tour and designed empty states after, no dashed empty boxes.
7. All animations use NuvoMotion tokens (lint-style test greps the onboarding folder).
8. Every tappable sinks with a haptic, primary CTA stays in place.
9. 60fps (no frame >20ms in more than 1% of frames) on iPhone 12+, S1,S2,S3,S5,S7,S15.
10. Reduce Motion and haptics toggle honored.
11. Camera permission only on Submit proof with one-line reason, notification permission only after the in-context moment, motion consent deferred.
12. Practice data never reaches the server and is labeled Practice.
13. Kill at every step and relaunch resumes without repeating or double-awarding XP.
14. Old App Store builds keep working, XP grant idempotent.
15. VoiceOver labels, tap targets >=44pt, contrast >=4.5:1, Dynamic Type to 1.5x.
16. Apple/Google sign-in, email OTP, username check, photo upload, 13+/terms behave as before, analyze clean, no new failing tests beyond the known 16.

Analytics (PostHog on analytics/posthog): ob_step_viewed, ob_step_completed, ob_skipped, ob_tour_stop, ob_proof_started, ob_proof_completed, ob_level_up_seen with step and ms_on_step.

## Risks
Devin quota (2 agents at a time, ship Cut 1 first); painter heroes look amateur (review in simulator screenshots, flat fills + 2.5px navy strokes); camera flaky in simulator (fallback is in spec, device test on Akshay's iPhone); tour anchors break on layout changes (anchor tests fail loudly, missing anchor skips the step); any extra screen not in the spec needs Akshay's OK.

When the first complete flow works: release build installed on Akshay's iPhone from the Mac, then report. Poll Devin rarely (30-60 min), report only milestones.
