# Full Nuvo UI/UX Audit

Static audit date: 2026-06-19. No simulator or physical-device UI run was performed in this pass.

## Overall Rating
- Functionality: 8/10. Auth, races, pass, manual proof, AI proof, invite, join, and race management are wired to real systems.
- UI polish: 7/10. The Arena Card System is visible, but several screens still feel like functional forms rather than a premium social competition product.
- UX clarity: 6.5/10. The race loop is mostly understandable, but AI proof is not consistently gated by race type and the guided camera setup is not strong enough.
- Demo readiness: 6/10. The app can demo real flows, but the exact 10 Jumping Jacks path is not deterministic enough yet.
- Biggest blocker: The Compete quick start promises `AI Motion Proof · 10 reps`, but it opens a generic race creation form that creates a manual race unless the user edits settings later.

## Global Issues

### 1. AI quick start does not create an AI race
- Severity: Critical
- Screens affected: Compete, Create Race, Race Detail, Submit Proof
- What is wrong: The first quick start is `10 Jumping Jacks`, but tapping it only opens `/races/new`; `CreateRaceScreen` defaults to generic templates and creates a manual proof race.
- Why it matters: The live demo can fall off the intended path before AI Motion Proof starts.
- Recommended fix: Pass a quick-start template into `CreateRaceScreen` or add a dedicated AI quick-start create path that pre-fills title, target `10`, unit `reps`, category `fitness`, proof requirement `ai_check`, and AI review mode.

### 2. AI Motion Proof can record before body readiness is valid
- Severity: Critical
- Screens affected: AI Motion Proof
- What is wrong: `Record proof` is enabled as soon as the camera is ready, even when `_counter.fullBodyVisible` is false.
- Why it matters: The screen can imply readiness when the model has not validated body visibility, increasing failed recordings during a live demo.
- Recommended fix: Add a pre-record body visibility gate based on pose frames. Show `Body visible` / `Step back` status, disable or soften the CTA until valid, and never say ready unless the state is actually valid.

### 3. Submit Proof exposes AI proof for every race
- Severity: High
- Screens affected: Submit Proof, Race Detail
- What is wrong: `_AiMotionProofCard` appears before manual proof regardless of `race.proofRequirement`.
- Why it matters: Manual races can look AI-backed, and AI can feel bolted on rather than intentionally part of the race setup.
- Recommended fix: Load race metadata in `SubmitProofScreen` and conditionally show AI Motion Proof only for `ai_check` or supported AI quick-start races. For manual races, make manual proof primary.

### 4. Camera experience lacks a full-body guide overlay
- Severity: High
- Screens affected: AI Motion Proof
- What is wrong: The camera panel has a target pill and recording HUD, but no visual body frame, foot/arm safe area, or body visibility pill.
- Why it matters: Users need immediate physical setup guidance; text alone is weak during a motion demo.
- Recommended fix: Add a premium guided camera overlay: full-body outline/frame, bottom distance cue, body visibility pill, target pill, recording count HUD, and camera toggle.

### 5. Race management is still visible on main detail
- Severity: Medium
- Screens affected: Race Detail, Race Settings
- What is wrong: Archive, cancel, and delete still appear as lifecycle chips on Race Detail, even though they are also in Race Settings.
- Why it matters: The main detail should feel like an arena, not an admin console.
- Recommended fix: Keep only `Manage race` / `Race settings` on detail, and move all destructive actions to Settings/Danger Zone.

### 6. Back button style is inconsistent
- Severity: Medium
- Screens affected: Auth email, Create Race, Submit Proof, Edit Profile, Arena notifications icon area
- What is wrong: Some screens use `NuvoBackButton`, others use `IconButton.filledTonal`, `NuvoIconAction`, or plain `GestureDetector` icons.
- Why it matters: Navigation feels assembled screen-by-screen instead of designed as one app.
- Recommended fix: Use `NuvoBackButton` for back navigation across standalone/detail flows.

### 7. Create Race and onboarding are not AI-demo focused
- Severity: Medium
- Screens affected: Create Race, Onboarding First Race
- What is wrong: Create Race starts with `Read more`; onboarding first race starts with `Race to a 6-pack`.
- Why it matters: The product claim is now strongest around AI Motion Proof, but setup still foregrounds generic manual races.
- Recommended fix: Put `10 Jumping Jacks` first in both places and make it visibly AI Motion Proof.

### 8. Proof settings copy needed supported-AI scoping
- Severity: Medium
- Screens affected: Race Settings
- What was wrong: `ai_check` was labelled as coming soon even though AI Motion Proof works for jumping jacks.
- Why it matters: Owners could read the app as if the supported AI path was unavailable.
- Current status: Updated in the live demo UX pass to label the supported option as `AI Motion Proof - 10 jumping jacks`.

### 9. Product loop copy is correct but visually plain
- Severity: Low
- Screens affected: Auth Welcome, Arena, Compete
- What is wrong: The app has good language, but some places are text-first with simple cards rather than a premium sports/social rhythm.
- Why it matters: The demo should feel designed, not just functional.
- Recommended fix: Add stronger first-fold hierarchy: one dark featured arena card, one clear next action, and fewer equal-weight secondary controls.

### 10. No current rendered QA evidence
- Severity: Medium
- Screens affected: Whole app
- What is wrong: This audit is static. I did not verify real iPhone screenshots, camera framing, clipping, or text truncation.
- Why it matters: The key risks are visual and device-specific.
- Recommended fix: After implementation approval, run physical iPhone demo QA and capture screenshots for the exact flow.

## Screen-by-Screen Audit

### Auth / Welcome
- What works: Real Google/email auth, dark logo treatment, pinned CTAs, clean Nuvo copy, no fake race players.
- Problems: Email flow back icons are plain and inconsistent; the product-loop text uses `->` style copy and feels more explanatory than premium.
- Fixes: Standardize `NuvoBackButton`; make the loop card feel more like a small arena card; keep CTAs pinned and simple.

### Onboarding
- What works: Real profile save, username availability, real member pass, honest crew coming-soon state.
- Problems: First race templates are generic and manual; `10 Jumping Jacks` is absent; onboarding does not teach AI Motion Proof.
- Fixes: Make `10 Jumping Jacks` the first onboarding starter, mark it `AI Motion Proof · 10 reps`, and create the race with `proofRequirement: ai_check`.

### Arena
- What works: Real races, greeting, featured race, `Submit proof`, clean empty state, honest notifications.
- Problems: Header notifications use default Material styling; empty state CTA is a raw local mini button; featured card could better emphasize progress and next proof action.
- Fixes: Use Nuvo icon controls; make featured race card a richer "next move" panel with progress, goal, leaderboard position, and one primary proof CTA.

### Compete
- What works: Real race list; quick starts are clearly separate; top quick start is `10 Jumping Jacks`; no duplicate empty-state CTA.
- Problems: Quick-start tap loses template data; quick starts below the first remain generic; two top CTAs compete for attention.
- Fixes: Wire quick-start data into create flow; make `10 Jumping Jacks` the dominant demo action; keep `Join with code` secondary.

### Create Race
- What works: Simple form, real backend race creation, sticky primary button.
- Problems: The generic create-race form still needs device QA, but the first template is now demo-aligned and the AI CTA says `Start AI race`.
- Fixes: Add AI quick-start prefill; optionally expose proof method as a designed segmented control; use `NuvoBackButton`; update CTA label.

### Race Detail
- What works: Good current hierarchy: title, progress, submit proof, leaderboard, proof method, recent proofs, rules, manage. Title-case display and AI proof method are present.
- Problems: Danger actions remain on the main detail; AI detection uses title substring fallback; `Invite crew` can feel nearly as important as `Submit proof`.
- Fixes: Move danger actions fully to settings; make proof method rely on metadata; tighten owner secondary actions under a smaller manage row.

### Race Settings / Edit Race
- What works: Real owner-gated edit, lifecycle, and danger zone actions; destructive actions confirm.
- Problems: Form styling feels generic; AI proof option says coming soon; start/finish dates are raw ISO fields; back button uses `NuvoIconAction`.
- Fixes: Make settings calmer and more operational; rename supported AI option; keep danger zone here only; avoid date complexity for the demo unless needed.

### Submit Proof
- What works: Manual proof is real; AI Motion Proof card is strong visually; bottom CTA is pinned.
- Problems: AI card appears for every race; manual proof remains visible for AI race without hierarchy; back buttons are inconsistent.
- Fixes: Load race before rendering; for AI races, show AI Motion Proof as primary and manual as fallback; for manual races, hide or de-emphasize AI.

### AI Motion Proof
- What works: Real camera, ML Kit pose detection, rep counter, processing/result states, no video upload, debug panel hidden outside debug builds.
- Problems: No full-body guide overlay; record is enabled before body visibility is valid; preferred camera is front rather than back; camera readiness copy can imply readiness too early.
- Fixes: Build a guided camera experience: setup shot -> body visibility check -> ready to record -> recording/counting -> processing -> verified/try again -> submit.

### AI Result / Verified State
- What works: Verified state is a premium navy panel; failed state is coaching rather than a harsh error; submit sends verified result only.
- Problems: Result details are minimal; confidence is shown but not contextual; failed state does not show a precise setup correction beyond full body copy.
- Fixes: Add a concise result summary: detected reps, target, confidence, and one coaching line. Keep debug metrics out of release/demo UI.

### Profile
- What works: Real user, real race stats, honest history/empty/error states, sign out clears auth.
- Problems: Stats can average all participants, not just the current user, which may read oddly as "your" average progress.
- Fixes: Scope profile stats to current user participation where possible, or label as race activity.

### Pass / Member Pass
- What works: Real pass data, correct dark logo use, QR card feels premium, crew empty state is honest.
- Problems: Search field is interactive-looking but not functional; QR scan is coming soon.
- Fixes: Consider making search read-only with an explicit coming-soon sheet, matching onboarding, until crew search exists.

## Button Audit
- Primary CTAs: Strong Nuvo blue/backplate treatment is in place. Primary hierarchy needs improvement in Create Race, Submit Proof by race type, and AI record readiness.
- Secondary CTAs: Outline buttons are clear. Some secondary actions still compete visually when stacked near primaries.
- Danger actions: Correctly implemented in Settings/Danger Zone, but still exposed on Race Detail as lifecycle chips.
- Buttons that look too boring: Raw mini CTA in Arena empty state; email back icons; form screen back buttons.
- Buttons that are too visually heavy: Primary button treatment inside the dark AI card can feel nested-heavy but acceptable for demo.
- Labels that may truncate: `Race settings`, `Submit verified proof`, and long quick-start subtitles should be checked on standard iPhone widths.

## Navigation / SafeArea Audit
- Back button consistency: Incomplete. `NuvoBackButton` exists but is not universal.
- Status bar: Global dark-icon overlay is set in `main.dart` and `NuvoApp`.
- Bottom nav: Clean and consistent. It uses a floating pill and respects bottom inset.
- Sticky CTA safety: Auth, Create Race, Submit Proof, and onboarding use pinned or bottom bars. AI Motion Proof actions are in scroll content and need device verification.
- Keyboard safety: Form screens use scroll views; bottom CTA plus keyboard should still be checked on small iPhones.

## AI Motion Proof UX Audit
- Camera preview aspect ratio: Uses a fixed `3 / 4` panel with `CameraPreview`. Needs real iPhone verification for crop/stretch and body framing.
- Full-body guidance: Text exists, visual overlay does not.
- Body visibility status: Counter has `fullBodyVisible`, but the UI does not gate recording on it before recording.
- Record flow: Setup -> start camera -> record -> done -> process works, but readiness is too loose.
- Result flow: Verified and failed panels exist and are directionally good.
- Failure states: Permission, camera error, pose detector failure, and failed reps are handled.
- Demo safety: Needs deterministic back-camera/preferred-camera plan, full-body gate, and no debug metrics in demo build.

## Demo Flow Audit

1. Open app
- Current UX: Splash then router decides welcome or arena.
- What could go wrong live: Auth loading or stale session path changes expected start screen.
- Needed fix: Decide logged-in demo state before recording; use an authenticated prepared account.

2. Login
- Current UX: Google and email are available.
- What could go wrong live: Google picker/cancel/network friction; email code delay.
- Needed fix: Use a known logged-in account for the live video, or pre-test email code delivery.

3. Go to Compete
- Current UX: Bottom nav has Compete.
- What could go wrong live: Empty race state is okay; race loading error would block.
- Needed fix: Ensure backend is healthy and account has a clean demo state.

4. Choose 10 Jumping Jacks quick start
- Current UX: Tile exists and is first.
- What could go wrong live: It only opens generic Create Race.
- Needed fix: Pass quick-start data into Create Race or create the race directly after confirmation.

5. Create/open race
- Current UX: Form creates manual race by default.
- What could go wrong live: Race detail shows AI based only on title fallback, while backend metadata stays manual.
- Needed fix: Create race with `proofRequirement: ai_check`, `targetValue: 10`, `unit: reps`.

6. Submit proof
- Current UX: Race Detail has dominant `Submit proof`.
- What could go wrong live: Submit Proof shows AI for manual races too.
- Needed fix: Make the race metadata correct and gate UI on it.

7. Choose AI Motion Proof
- Current UX: AI card is prominent.
- What could go wrong live: Manual fallback and AI card hierarchy can confuse the story.
- Needed fix: For AI races, show AI Motion Proof as the main path, manual as fallback.

8. Set up camera
- Current UX: Text instructions and camera panel.
- What could go wrong live: User starts recording before full body is visible.
- Needed fix: Body visibility pill and disabled record CTA until valid.

9. Record 10 jumping jacks
- Current UX: Counter updates during recording.
- What could go wrong live: Bad framing, front/back camera mismatch, insufficient body visibility, unsteady counting.
- Needed fix: Prefer demo-tested camera, add full-body overlay, verify camera crop on physical iPhone.

10. Get verified result
- Current UX: Verified/try-again panels exist.
- What could go wrong live: Good recording fails if confidence threshold is not met.
- Needed fix: Add clearer pre-record validation and rehearse the exact setup distance.

11. Submit verified proof
- Current UX: Button posts AI proof and returns to Race Detail.
- What could go wrong live: Backend/network failure.
- Needed fix: Preflight `/health`, auth token, and proof endpoint before demo.

12. Show leaderboard/progress updated
- Current UX: Race detail reloads from backend after submit.
- What could go wrong live: Progress update depends on returned race and participant state.
- Needed fix: Verify the demo account is a participant and the AI result is `ai_verified`.

## Live Demo UX Pass Update - 2026-06-19
- Fixed: The `10 Jumping Jacks` quick start now preserves AI Motion Proof metadata through Create Race.
- Fixed: Create Race marks the supported 10 Jumping Jacks template as `AI Motion Proof` and uses `Start AI race`.
- Fixed: Submit Proof gates the working AI option to supported AI races; manual races default to manual proof and show AI as unavailable for non-supported activities.
- Fixed: Race Detail proof method no longer relies on title substring fallback for the working AI path; it uses `proofRequirement == ai_check` plus the 10-jumping-jacks target/unit.
- Fixed: Race Detail no longer shows Archive/Cancel/Delete on the main competition surface.
- Fixed: AI Motion Proof has a setup card, full-body guide overlay, natural camera preview fitting, back-camera preference, sticky safe CTAs, and user-facing body-framing status.
- Fixed: Raw debug metrics are no longer shown in the AI Motion Proof UI.
- Still needs device QA: physical iPhone camera crop/framing, home-indicator spacing, release build, and live proof-to-leaderboard refresh.
