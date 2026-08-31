# Nuvo UI/UX Rebuild Plan

## Goal
Make Nuvo feel premium, focused, and live-demo ready without breaking working auth/race/AI functionality.

## Principles
1. Preserve real backend, auth, race, proof, and AI counting flows.
2. Make the demo path deterministic: `10 Jumping Jacks` must create an actual AI Motion Proof race.
3. Treat AI Motion Proof as a guided camera product, not a normal form page.
4. Keep Race Detail focused on competing: progress, proof, leaderboard, crew.
5. Move owner/admin/destructive actions away from the main competition surface.
6. Use Nuvo language and the Arena Card System consistently.

## Phase 1 - Fix demo blockers
- Item: Wire `10 Jumping Jacks` quick start into real AI race creation.
- Files likely affected: `lib/features/compete/presentation/compete_screen.dart`, `lib/features/races/presentation/create_race_screen.dart`, possibly `lib/app/router.dart`.
- Why: The current quick start promises AI but opens a generic manual race form.
- Risk: Low to medium. Race creation already supports `proofRequirement`; the main risk is changing navigation data shape.
- Acceptance criteria: Tapping `10 Jumping Jacks` pre-fills title, target `10`, unit `reps`, category `fitness`, proof requirement `ai_check`, and creates a race whose Race Detail shows `AI Motion Proof · 10 reps`.

- Item: Gate Submit Proof by race proof method.
- Files likely affected: `lib/features/races/presentation/submit_proof_screen.dart`, `lib/features/races/presentation/race_controller.dart`.
- Why: AI proof currently appears for every race.
- Risk: Medium. Submit Proof must load race metadata without adding race-state bugs.
- Acceptance criteria: AI races show AI Motion Proof as the primary path; manual races show manual proof first and do not imply AI verification.

- Item: Move Race Detail danger actions fully out of detail.
- Files likely affected: `lib/features/race_detail/presentation/race_detail_screen.dart`, `lib/features/races/presentation/race_settings_screen.dart`.
- Why: Main detail should not feel like an admin panel.
- Risk: Low. Settings already has lifecycle and danger-zone actions.
- Acceptance criteria: Race Detail has a calm `Manage race` entry; Archive, Cancel, Delete appear only in Settings/Danger Zone.

## Phase 2 - Redesign AI Motion Proof UX
- Item: Add guided camera overlay.
- Files likely affected: `lib/features/races/presentation/ai_motion_proof_screen.dart`.
- Why: Users need visual setup guidance for full-body movement.
- Risk: Medium. Camera overlay must not interfere with preview or controls.
- Acceptance criteria: Camera panel shows full-body frame, target pill, body visibility pill, camera toggle, and recording HUD without stretching or clipping.

- Item: Add pre-record body visibility check.
- Files likely affected: `ai_motion_proof_screen.dart`, possibly `pose_detector_service.dart`.
- Why: The screen must not say ready until pose/body readiness is actually valid.
- Risk: Medium. The current pose stream starts only while recording, so this may require a lightweight preview-analysis state.
- Acceptance criteria: `Record proof` is disabled or replaced with setup guidance until required body points are visible with sufficient confidence.

- Item: Prefer back camera for jumping-jack demo when available.
- Files likely affected: `ai_motion_proof_screen.dart`.
- Why: The requested demo direction prefers back camera if possible.
- Risk: Low. Camera toggle already exists.
- Acceptance criteria: Initial camera selection prefers back camera for AI proof, with toggle still available.

- Item: Polish result states.
- Files likely affected: `ai_motion_proof_screen.dart`.
- Why: Verified/failed states should feel premium and decisive.
- Risk: Low.
- Acceptance criteria: Verified state shows detected reps, confidence, and submit CTA; failed state shows detected reps and one clear setup correction.

## Phase 3 - Redesign Race Detail hierarchy
- Item: Tighten top hierarchy around progress and proof.
- Files likely affected: `lib/features/race_detail/presentation/race_detail_screen.dart`.
- Why: Race Detail should feel like the competition arena.
- Risk: Low.
- Acceptance criteria: First fold contains title/context, my progress, and `Submit proof`; leaderboard begins soon after.

- Item: Make proof method metadata-driven.
- Files likely affected: `race_detail_screen.dart`, `race_models.dart` only if helper getters are added.
- Why: Title substring fallback can misclassify races.
- Risk: Low.
- Acceptance criteria: AI display depends on `proofRequirement == ai_check` or explicit supported activity metadata, not title text.

- Item: Improve recent proof rows for AI proof.
- Files likely affected: `race_detail_screen.dart`.
- Why: Demo should show AI proof as credible, not raw technical data.
- Risk: Low.
- Acceptance criteria: Recent AI proof row shows `AI Motion Proof`, detected reps, confidence, and `Verified` status cleanly.

## Phase 4 - Button/design-system consistency
- Item: Standardize all standalone back buttons.
- Files likely affected: `email_start_screen.dart`, `email_verify_screen.dart`, `create_race_screen.dart`, `submit_proof_screen.dart`, `edit_profile_screen.dart`, `race_settings_screen.dart`, `proof_review_screen.dart`, `invite_crew_screen.dart`, `join_race_screen.dart`.
- Why: Back navigation currently mixes several visual styles.
- Risk: Low.
- Acceptance criteria: Detail/flow screens use `NuvoBackButton` with `safePopOrGo`.

- Item: Remove raw mini-buttons from premium surfaces.
- Files likely affected: `arena_screen.dart`, possibly `pass_screen.dart`.
- Why: Raw local buttons reduce perceived polish.
- Risk: Low.
- Acceptance criteria: Empty-state and featured-card actions use Nuvo button/control patterns.

- Item: Clarify primary vs secondary hierarchy.
- Files likely affected: `compete_screen.dart`, `race_detail_screen.dart`, `submit_proof_screen.dart`.
- Why: Primary CTAs should be obvious without every action receiving heavy visual weight.
- Risk: Low.
- Acceptance criteria: Each screen has one dominant next action; secondary actions are visually quieter.

## Phase 5 - Compete/Quick Start demo polish
- Item: Make `10 Jumping Jacks` the hero quick start.
- Files likely affected: `compete_screen.dart`.
- Why: The demo should start from a confident, obvious tile.
- Risk: Low.
- Acceptance criteria: The first fold shows `10 Jumping Jacks`, `AI Motion Proof · 10 reps`, and a clear start affordance.

- Item: Update onboarding first race templates.
- Files likely affected: `lib/features/onboarding/presentation/first_race_screen.dart`.
- Why: New users should also see AI Motion Proof as a first-class product path.
- Risk: Low to medium. It changes onboarding starter data.
- Acceptance criteria: First onboarding quick start is `10 Jumping Jacks`; creating it produces an AI Motion Proof race.

- Item: Align Create Race templates with Nuvo language.
- Files likely affected: `create_race_screen.dart`.
- Why: Current templates feel generic.
- Risk: Low.
- Acceptance criteria: Template labels and subtitles use race, proof, start line, finish line, and crew language without banned vocabulary.

## Phase 6 - Final QA polish
- Item: Physical iPhone demo-path QA.
- Files likely affected: None unless bugs are found.
- Why: Camera crop, safe area, keyboard, and button clipping are device-specific.
- Risk: None for audit; medium for fixes discovered.
- Acceptance criteria: Verified screenshots or notes for the exact 12-step demo path.

- Item: Static verification after edits.
- Files likely affected: None.
- Why: Ensure no regressions in Flutter or Worker types.
- Risk: Low.
- Acceptance criteria: `flutter analyze` passes. Worker typecheck only if backend files are touched.

- Item: Release/demo UI check.
- Files likely affected: `ai_motion_proof_screen.dart` if debug UI leaks.
- Why: Debug metrics must not appear in demo/release UI.
- Risk: Low.
- Acceptance criteria: Debug metrics are hidden in release/profile builds and not present in demo screenshots.

## Exact Screens To Change
- Screen: Compete
- File: `lib/features/compete/presentation/compete_screen.dart`
- Proposed change: Make the AI quick start pass template data and become the dominant demo entry.

- Screen: Create Race
- File: `lib/features/races/presentation/create_race_screen.dart`
- Proposed change: Accept quick-start prefill, add supported proof method awareness, and create AI Motion Proof races correctly.

- Screen: Submit Proof
- File: `lib/features/races/presentation/submit_proof_screen.dart`
- Proposed change: Load race metadata and conditionally show AI/manual proof hierarchy.

- Screen: AI Motion Proof
- File: `lib/features/races/presentation/ai_motion_proof_screen.dart`
- Proposed change: Guided camera overlay, body visibility gate, preferred back camera, refined result states, bottom-safe controls.

- Screen: Race Detail
- File: `lib/features/race_detail/presentation/race_detail_screen.dart`
- Proposed change: Remove danger chips, make proof method metadata-driven, tighten first-fold hierarchy.

- Screen: Race Settings
- File: `lib/features/races/presentation/race_settings_screen.dart`
- Proposed change: Keep danger zone here, rename supported AI proof option, reduce generic form feel where low risk.

- Screen: Onboarding First Race
- File: `lib/features/onboarding/presentation/first_race_screen.dart`
- Proposed change: Put `10 Jumping Jacks` first and create a real AI Motion Proof race.

- Screen: Auth/Create/Profile/Edit standalone flows
- Files: `email_start_screen.dart`, `email_verify_screen.dart`, `edit_profile_screen.dart`, `create_race_screen.dart`, `submit_proof_screen.dart`
- Proposed change: Standardize back controls with `NuvoBackButton`.

## Do Not Touch
- Backend unless absolutely necessary.
- Auth logic.
- Race proof logic.
- AI counting logic unless UI state requires a pre-record readiness stream.
- Deployed API URL.
- iOS bundle ID.
- Secrets.
- D1 migrations.
- Fake data must not be reintroduced.

## Live Demo UX Pass - 2026-06-19
- Completed: `10 Jumping Jacks` quick start now opens Create Race with AI Motion Proof metadata preserved.
- Completed: Create Race starts with `10 Jumping Jacks`, shows proof mode clearly, and uses `Start AI race` for the supported AI template.
- Completed: Submit Proof loads race metadata and shows AI Motion Proof as primary only for supported 10 Jumping Jacks AI races.
- Completed: Manual races default to manual proof and show AI Motion Proof as unavailable for non-jumping-jack races.
- Completed: AI Motion Proof now has a guided setup card, full-body camera guide overlay, back-camera preference, safer bottom CTA area, and no raw debug metrics in the main UI.
- Completed: Race Detail no longer exposes Archive/Cancel/Delete chips; those remain in Race Settings/Danger Zone.
- Completed: Race Detail proof method uses race metadata and shows `AI Motion Proof` with live-camera/auto-verified copy for supported AI races.
- Completed: Create Race, Submit Proof, AI Motion Proof, Race Detail, Edit Profile, and Race Settings use the standard `NuvoBackButton`.
- Verification: `flutter pub get` passed; `flutter analyze` passed.
- Not verified: physical iPhone camera framing, release run, and real demo-path progress update.
