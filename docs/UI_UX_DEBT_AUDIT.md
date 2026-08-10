# Nuvo UI/UX Debt Audit — Phase 1

**Date:** 2026-08-10
**Mode:** READ-ONLY audit. No production code modified.
**Scope:** All user-visible screens outside Arena (Arena is handled separately).
**Method:** Four parallel read-only subagents inspected auth/onboarding, main tabs/profile, races flow, and movement-scale UI. Findings were consolidated, de-duplicated, renumbered, and verified against the actual code. One subagent P0 claim was corrected after verification (see RELEASE-006 note).

---

## 1. Executive Summary

Nuvo is moving fast and accumulating UI debt that is starting to hurt the actual user experience. The app is not broken — there is one true P0 (a dead widget class that confuses developers, not users) — but there is a meaningful cluster of P1 issues that make the app feel cramped, confusing, or fragile on the devices most users actually carry.

**The dominant themes:**

1. **Small-iPhone neglect.** Multiple screens (Race Composer activity step, Submit Proof pre-verify, Create Race form, several auth/onboarding forms) push the primary CTA below the fold or fail to handle the keyboard, on 375×667/375×812 devices. This is the single highest-impact category.
2. **Weak state handling on network-backed screens.** Compete shows raw backend errors. Move silently shows empty state on error. Pass silently swallows search errors. Race Detail silently fails background refresh. Profile shows no refresh feedback. Users cannot tell "I have no races" from "the network is broken."
3. **Destructive actions are too easy to hit.** Delete account, archive/cancel/delete race, and reject proof are all full-width buttons one tap away from a single confirmation. Profile delete has no typing confirmation.
4. **Release hygiene leaks.** Hardcoded reviewer emails, a registered `/internal/teach-movement` route, `NUVO_DIAGNOSTICS` env-var bypass for debug panels, debug `print` statements in EditProfile, and a TODO referencing an internal doc in Welcome.
5. **Movement picker does not scale to 100.** "See all" does nothing, custom movements vanish after 5 recents, search is substring-only with no fuzzy match, demos are hand-authored per movement, and Quick Starts are hardcoded to 5 movements.
6. **Copy is inconsistent and sometimes user-blaming.** "MOVE DIDN'T COUNT" (all caps, punitive), "Nuvo hit a snag" (cutesy), "Editable camera race" (dev-facing), "Lifecycle" / "Danger zone" (technical), "move" vs "proof" terminology drift.
7. **Design-system drift is real but mostly code-only.** `NuvoColors` vs `AppColors` duplication, screen-local color constants (`_kTrackNavy`, `_kProfileBorder`), inline shadows instead of `AppShadows`, hardcoded step indicator in 4 onboarding screens. Users mostly can't see this — but the step indicator inconsistency and button-height drift are visible.

**What this audit is NOT:** a redesign proposal, a design-system rewrite, or a request to fix everything at once. Every finding has a minimal fix direction. Implementation batches are sized 3–8 findings and ordered by user impact.

---

## 2. Screen-by-Screen Audit

### Auth

#### WelcomeAuthScreen
`lib/features/auth/presentation/welcome_auth_screen.dart`
**Primary task:** Choose sign-in method (email or Google).
- Google button is a custom `GestureDetector`+`Container` instead of `NuvoButton` → inconsistent tap/press/loading behavior; loading is only an opacity change to 0.55 (weak feedback).
- Hero section is over-decorated: 5 private widget classes (`_BrandMark`, `_HeroBlock`, `_ProductPreviewCard`, `_StartLineChip`, `_LoopStrip`); `_LoopStrip` renders 4 purely decorative pills.
- TODO comment + `_kGoogleEnabled` flag reference an internal doc (`GOOGLE_OAUTH_FIX_PLAN.md`).

#### EmailStartScreen
`lib/features/auth/presentation/email_start_screen.dart`
**Primary task:** Enter email to receive a sign-in code.
- **Hardcoded reviewer emails** (`team@getnuvo.net`, `testing@getnuvo.net`, `testing@getnuvo`) expose a dev-only auth path in client code. When a reviewer email is typed, a password field appears and `signInReviewer` is called.
- No `resizeToAvoidBottomInset`/keyboard handling — CTA may be obscured on small iPhones when keyboard opens.

#### EmailVerifyScreen
`lib/features/auth/presentation/email_verify_screen.dart`
**Primary task:** Enter the 6-digit code from email.
- No keyboard handling (same as EmailStart).
- 500-error copy "Nuvo hit a snag. Try again." is cutesy and inconsistent with the rest of the app.
- OTP auto-verifies on 6 digits (good). Resend shows "Sending…" state (good).

### Onboarding

#### CreateIdentityScreen
`lib/features/onboarding/presentation/create_identity_screen.dart`
**Primary task:** Enter name + pick an available username.
- Input labels are ALL CAPS ("FULL NAME", "USERNAME") while the next onboarding screen uses title case ("Full name", "Username") — visible inconsistency within the same flow.
- Step indicator is hardcoded inline (5-segment loop) — duplicated in 3 other onboarding screens.
- Avatar preview uses an inline `BoxShadow` instead of `AppShadows`.
- No keyboard handling.

#### OnboardingScreen (profile)
`lib/features/onboarding/presentation/onboarding_screen.dart`
**Primary task:** Confirm profile, set privacy, accept terms.
- **Non-functional camera button** on the avatar — decorative `Container` with `Icons.camera_alt_rounded` and no `onTap`. Users tap it and nothing happens.
- "Username set" row is always shown even though username was set on the previous screen — redundant and confusing.
- Error path can expose raw `exception.toString()` to the user.
- Step indicator hardcoded (same duplication).
- Privacy toggle is an inline custom `Container` — no shared component.
- No keyboard handling.

#### MemberPassScreen
`lib/features/onboarding/presentation/member_pass_screen.dart`
**Primary task:** View member pass, share/copy, continue.
- Loading state replaces the **entire screen** with a spinner → jarring layout jump, loses context.
- Verification info card is an inline custom `Container` (no shared `NuvoInfoCard`).
- Otherwise clean: uses `MemberPassCard`, has proper error+retry, share/copy work.

#### AddCrewScreen
`lib/features/onboarding/presentation/add_crew_screen.dart`
**Primary task:** Placeholder — invite crew later.
- **"Continue" and "Skip for now" both navigate to the same destination** (`/onboarding/first-race`). The choice is meaningless.
- "Your crew is waiting at the start line." is generic/cliché placeholder copy.
- Step indicator hardcoded (same duplication).

#### FirstRaceScreen
`lib/features/onboarding/presentation/first_race_screen.dart`
**Primary task:** Pick a race template or explore the arena.
- Section label "Quick starts" and subtitle "Choose a race template" are redundant.
- `TemplateCard` uses an inline `BoxShadow` instead of `AppShadows`.
- Otherwise solid: chip selection, template card, loading disables chips+buttons, clear error.

#### SecureAccountScreen (DEAD)
`lib/features/onboarding/presentation/secure_account_screen.dart`
**Primary task:** None — passthrough.
- Dead passthrough: `addPostFrameCallback` redirects to `/onboarding/profile` immediately. Shows a spinner for no reason. Route exists only "for router continuity."

### Main Tabs

#### CompeteScreen
`lib/features/compete/presentation/compete_screen_fixed.dart`
**Primary task:** Start or join a race; see active/in-motion/waiting/finished races.
- **5 hardcoded Quick Start rows** (~300px) push active races below the fold on small iPhones. "Editable camera race" sublabel is dev-facing.
- **Raw backend error string** shown to users when `raceState.error` is set and races list is empty — no retry, no friendly message.
- Hero has two equal-weight CTAs ("Start race" + "Join") competing for attention.
- Inconsistent section spacing (conditional `0` vs `24`).

#### MoveScreen
`lib/features/move/presentation/move_screen.dart`
**Primary task:** See ready races, submit proof, view history.
- **No error state** — if `raceState.error` is set, it's silently ignored and the empty state is shown. Users think they have no races when the network failed.
- Completed section is **collapsed by default** — extra friction to view history.
- Recent-moves status pills use **9px font** — barely readable.
- Hero subtitle "Choose a race, then verify your move." is slightly robotic.

#### PassScreen
`lib/features/pass/presentation/pass_screen.dart`
**Primary task:** View member pass, search/add crew, see closest race.
- **Search errors silently swallowed** (`catch (_)`) — users see a spinner that never resolves.
- Add-crew button shows "…" during loading but the `_adding` set may not be updated before rebuild → double-submission risk.
- "Could not load your crew." is generic.
- Closest-race track uses a fixed 60px height with manual marker positioning — fragile across widths.
- Member pass, search, and crew list all have similar visual weight — no clear primary action.

#### ProfileScreen
`lib/features/profile/presentation/profile_screen.dart`
**Primary task:** View identity, stats, history, settings.
- **Race history capped at 6** with no "See all" — users with more races can't see older history.
- **Delete account is one confirmation dialog away** — no typing confirmation, no cooldown. Too easy to permanently destroy an account.
- Loading state only shows spinner when `races.isEmpty` — no refresh feedback when stale data is displayed.
- 4 equal-weight stats (Active/Finished/Moves/Avg) — no primary metric.
- Screen-local color constants (`_kProfileBorder`, `_kProfileTextMuted`) instead of using `NuvoColors` directly.

#### EditProfileScreen
`lib/features/profile/presentation/edit_profile_screen.dart`
**Primary task:** Edit photo, name, username.
- **~13 `debugPrint` statements** in production code (`PROFILE_PHOTO_SHEET_OPENED`, `PHOTO_PICK_STARTED`, `PENDING_IMAGE_BYTES_SET: ${bytes.length} bytes`, etc.).
- Photo upload failure keeps the pending preview visible but only shows a SnackBar — confusing state (preview looks saved but isn't).
- "Nuvo hit a snag. Try again." error copy (cutesy, inconsistent).
- Save button loading-state disable not confirmed in visible code — double-submit risk.
- Photo section is centered with a 104×104 avatar — pushes form fields below fold on small screens.

#### BottomNav
`lib/core/widgets/bottom_nav.dart`
**Primary task:** Navigate between 5 tabs.
- Screen-local colors `_kTrackNavy` (`0xFF071B35`) and `_kTrackActiveBlue` (`0xFF2F7CFF`) instead of `NuvoColors` tokens.
- "Verify" (index 2) is treated as `isPrimary` with special styling but this isn't visually communicated — may look like a bug.
- Complex height calculation with 8 constants — may not cover all device edge cases.

### Races Flow

#### RaceComposerScreen
`lib/features/races/presentation/race_composer_screen.dart`
**Primary task:** Create a race via 5-step wizard (name → activity → goal → racers → review).
- **"Teach a movement" secondary button competes with the primary CTA** on the activity step — full-width, icon, navigates to `/internal/teach-movement` and exits the composer flow, losing draft progress.
- **Form state can disappear on back navigation** — `_GoalPageState` edit mode (`_editing`/`_editCtrl`) doesn't commit on step change; uns edits to custom target value are lost.
- No loading indicator on "Start race" — button just disables.
- `kNuvoDiagnosticsEnabled` (`NUVO_DIAGNOSTICS` env var) can expose debug UI in release builds if `--dart-define` is set.
- Generic instructional copy ("Give your crew something worth chasing", "Camera verifies every rep").
- Excessive `flutter_animate` on every text element per step — feels sluggish on slower devices.

#### CreateRaceScreen (DEAD WIDGET, LIVE FILE)
`lib/features/races/presentation/create_race_screen.dart`
**Primary task:** Legacy single-page race creation form.
- **The `CreateRaceScreen` widget class is dead** — no route uses it, no file instantiates it. The active route `/races/new` uses `RaceComposerScreen`.
- **BUT the file is NOT orphaned** — `RaceCreatePrefill` (defined here) is actively imported and used by `compete_screen_fixed.dart` (5 quick-start presets), `race_composer_screen.dart` (prefill param), and `router.dart` (type check). The file cannot be deleted without moving `RaceCreatePrefill`.
- *(Subagent originally flagged this P0 "orphaned file" — corrected after verification. The file is live; only the widget class is dead.)*

#### JoinRaceScreen
`lib/features/races/presentation/join_race_screen.dart`
**Primary task:** Enter an invite code to join a race.
- "Could not join this race." is generic — doesn't distinguish invalid/expired/full/network error.
- Success is a silent redirect — no "Joined!" feedback.
- No keyboard dismissal on join.

#### RaceDetailScreen
`lib/features/race_detail/presentation/race_detail_screen.dart`
**Primary task:** View the leaderboard room for one race.
- **Leaderboard is buried** below "Path to goal", "Race pulse", and "Final standings" — the primary purpose of the screen is not the hero.
- **Competing primary actions**: summary card button, "Invite crew" full-width outline button, and 4 manage rows all compete.
- **Duplicate routes**: `/race/:id/settings` and `/race/:id/edit` both point to `RaceSettingsScreen` — confusing, back-button surprises.
- **Silent background refresh failures** — `_silentRefresh` catches errors and only `debugPrint`s; users never know the leaderboard is stale.
- Inconsistent section spacing (12/14/18/24 mixed).
- "Board moved X times recently" — "recently" is vague, "moved" is technical.

#### InviteCrewScreen
`lib/features/races/presentation/invite_crew_screen.dart`
**Primary task:** Search users to add; share invite code.
- Search debounce is 280ms — too short; triggers excess API calls while typing.
- Invite code card (navy, 26px font) visually dominates over the actual add-to-race actions (small outline buttons).
- Empty-state copy is robotic ("No matching Nuvo members found.").
- No loading indicator in search results area.

#### SubmitProofScreen
`lib/features/races/presentation/submit_proof_screen.dart`
**Primary task:** Choose proof method and begin verification.
- Pre-verify animation is fixed 340px — pushes CTA below fold on small iPhones.
- Back button lacks the `_navigating` double-tap guard that the CTA has.
- Time estimate ("~3 sec per rep") is a hardcoded assumption exposed to users.

#### RaceSettingsScreen
`lib/features/races/presentation/race_settings_screen.dart`
**Primary task:** Edit race details, goal, rules, visibility, lifecycle.
- **3 destructive actions (Archive/Cancel/Delete) are full-width buttons** at the bottom of a long scrollable form — easy to mis-tap while scrolling.
- "unsupported movement" exposes backend state; "Lifecycle" and "Danger zone" are technical section titles.
- Form state lost on save failure if user navigates away.
- No keyboard dismissal on save.
- Inconsistent input patterns (camera vs non-camera goal sections look unrelated).

#### ProofReviewScreen
`lib/features/races/presentation/proof_review_screen.dart`
**Primary task:** Review a submitted proof; accept/reject/resubmit.
- **"Reject move" danger button is the same size/prominence as "Accept move"** — only color differentiates. Easy to tap the wrong one.
- Terminology drift: title is "Review move", buttons say "Accept move"/"Reject move" — product language is "proof" not "move".
- No loading indicator on buttons during save.

#### BoardMovedScreen
`lib/features/races/presentation/board_moved_screen.dart`
**Primary task:** Celebrate leaderboard movement after proof.
- Rejected-state copy "MOVE DIDN'T COUNT" (all caps, danger color) is punitive; "Try again with a clearer move" blames the user.
- "Record again" uses `pushReplacement` — users lose the ability to go back and see their rank achievement.

#### TeachMovementScreen
`lib/features/races/presentation/custom_pose/teach_movement_screen.dart`
**Primary task:** Teach Nuvo a custom movement via camera demonstration.
- **`/internal/teach-movement` route is registered in the production router** — reachable by deep link. The `fixture=ready` seeding is guarded by `kDebugMode`, but the route itself is not.
- `kNuvoDiagnosticsEnabled` (`NUVO_DIAGNOSTICS` env var) can expose a debug panel with similarity scores and rejection reasons in release builds.
- Guidance messages are robotic ("Step back", "Move into the starting position").
- No confirmation before navigating to race creation with the learned movement.

---

## 3. Master Finding Table

| ID | Severity | Screen | Category | Short description | Files |
|----|----------|--------|----------|-------------------|-------|
| RELEASE-001 | P2 | Welcome | Release | TODO + internal doc reference + `_kGoogleEnabled` flag | welcome_auth_screen.dart |
| CONSISTENCY-001 | P2 | Welcome | Consistency | Google button is custom GestureDetector, not NuvoButton | welcome_auth_screen.dart |
| INTERACTION-001 | P2 | Welcome | Interaction | Google loading is only opacity 0.55; no retry on error | welcome_auth_screen.dart |
| HIERARCHY-001 | P3 | Welcome | Hierarchy | Over-decorated hero (5 private widgets, decorative pill strip) | welcome_auth_screen.dart |
| RELEASE-002 | P1 | Email Start | Release | Hardcoded reviewer emails + dev-only password field | email_start_screen.dart |
| INTERACTION-002 | P2 | Email Start | Interaction | No keyboard handling; CTA may be obscured on small iPhones | email_start_screen.dart |
| COPY-001 | P3 | Email Verify | Copy | "Nuvo hit a snag. Try again." is cutesy/inconsistent | email_verify_screen.dart |
| INTERACTION-003 | P2 | Email Verify | Interaction | No keyboard handling | email_verify_screen.dart |
| CONSISTENCY-002 | P2 | Create Identity | Consistency | ALL CAPS labels vs title case on next screen | create_identity_screen.dart |
| CONSISTENCY-003 | P2 | Onboarding (all) | Consistency | Step indicator hardcoded inline in 4 screens | create_identity/onboarding/add_crew/first_race |
| CONSISTENCY-004 | P3 | Create Identity | Consistency | Inline BoxShadow instead of AppShadows | create_identity_screen.dart |
| INTERACTION-004 | P2 | Create Identity | Interaction | No keyboard handling | create_identity_screen.dart |
| HIERARCHY-002 | P2 | Onboarding Profile | Hierarchy | Non-functional camera button on avatar (no onTap) | onboarding_screen.dart |
| COPY-002 | P2 | Onboarding Profile | Copy | "Username set" always shown (redundant); raw exception exposed | onboarding_screen.dart |
| CONSISTENCY-005 | P3 | Onboarding Profile | Consistency | Privacy toggle is inline custom Container | onboarding_screen.dart |
| INTERACTION-005 | P2 | Onboarding Profile | Interaction | No keyboard handling | onboarding_screen.dart |
| STATE-001 | P2 | Member Pass | State | Loading replaces entire screen with spinner (layout jump) | member_pass_screen.dart |
| CONSISTENCY-006 | P3 | Member Pass | Consistency | Verification info card is inline custom Container | member_pass_screen.dart |
| INTERACTION-006 | P2 | Add Crew | Interaction | "Continue" and "Skip for now" both go to same destination | add_crew_screen.dart |
| COPY-003 | P3 | Add Crew | Copy | "Your crew is waiting at the start line." generic/cliché | add_crew_screen.dart |
| CONSISTENCY-007 | P3 | First Race | Consistency | TemplateCard inline BoxShadow | first_race_screen.dart |
| COPY-004 | P3 | First Race | Copy | Section label + subtitle redundant | first_race_screen.dart |
| RELEASE-003 | P1 | Secure Account | Release | Dead passthrough screen; route exists only "for continuity" | secure_account_screen.dart |
| LAYOUT-001 | P1 | Compete | Layout | 5 hardcoded Quick Start rows push active races below fold | compete_screen_fixed.dart |
| STATE-002 | P1 | Compete | State | Raw backend error string shown; no retry | compete_screen_fixed.dart |
| COPY-005 | P2 | Compete | Copy | "Editable camera race" sublabel is dev-facing | compete_screen_fixed.dart |
| HIERARCHY-003 | P2 | Compete | Hierarchy | Two equal-weight CTAs (Start race + Join) compete | compete_screen_fixed.dart |
| CONSISTENCY-008 | P3 | Compete | Consistency | Inconsistent section spacing (conditional 0 vs 24) | compete_screen_fixed.dart |
| STATE-003 | P1 | Move | State | No error state; error silently shows empty state | move_screen.dart |
| INTERACTION-007 | P1 | Move | Interaction | Completed section collapsed by default (extra friction) | move_screen.dart |
| COPY-006 | P2 | Move | Copy | "Choose a race, then verify your move." robotic | move_screen.dart |
| HIERARCHY-004 | P2 | Move | Hierarchy | Recent-moves status pills use 9px font (barely readable) | move_screen.dart |
| INTERACTION-008 | P1 | Pass | Interaction | Search errors silently swallowed; spinner never resolves | pass_screen.dart |
| INTERACTION-009 | P1 | Pass | Interaction | Add-crew double-submission risk (loading state race) | pass_screen.dart |
| COPY-007 | P2 | Pass | Copy | "Could not load your crew." generic | pass_screen.dart |
| LAYOUT-002 | P2 | Pass | Layout | Closest-race track fixed 60px + manual marker positioning | pass_screen.dart |
| HIERARCHY-005 | P3 | Pass | Hierarchy | Pass/search/crew list all similar visual weight | pass_screen.dart |
| LAYOUT-003 | P1 | Profile | Layout | Race history capped at 6, no "See all" | profile_screen.dart |
| INTERACTION-010 | P1 | Profile | Interaction | Delete account is one dialog away; no typing confirmation | profile_screen.dart |
| STATE-004 | P1 | Profile | State | No refresh feedback when stale data is displayed | profile_screen.dart |
| HIERARCHY-006 | P2 | Profile | Hierarchy | 4 equal-weight stats; no primary metric | profile_screen.dart |
| COPY-008 | P2 | Profile | Copy | "Could not delete account. Try again." generic | profile_screen.dart |
| CONSISTENCY-009 | P3 | Profile | Consistency | Screen-local color constants instead of NuvoColors | profile_screen.dart |
| RELEASE-004 | P1 | Edit Profile | Release | ~13 debugPrint statements in production code | edit_profile_screen.dart |
| INTERACTION-011 | P1 | Edit Profile | Interaction | Save button loading-disable not confirmed; double-submit risk | edit_profile_screen.dart |
| STATE-005 | P2 | Edit Profile | State | Photo upload failure keeps pending preview; confusing state | edit_profile_screen.dart |
| COPY-009 | P2 | Edit Profile | Copy | "Nuvo hit a snag. Try again." cutesy | edit_profile_screen.dart |
| HIERARCHY-007 | P3 | Edit Profile | Hierarchy | 104×104 centered photo section pushes form below fold | edit_profile_screen.dart |
| CONSISTENCY-010 | P2 | Bottom Nav | Consistency | Screen-local colors `_kTrackNavy`/`_kTrackActiveBlue` | bottom_nav.dart |
| INTERACTION-012 | P3 | Bottom Nav | Interaction | "Verify" isPrimary styling not visually communicated | bottom_nav.dart |
| LAYOUT-004 | P3 | Bottom Nav | Layout | Complex height calc with 8 constants | bottom_nav.dart |
| HIERARCHY-008 | P1 | Race Composer | Hierarchy | "Teach a movement" competes with primary CTA; exits flow | race_composer_screen.dart |
| INTERACTION-013 | P1 | Race Composer | Interaction | Form state (custom target) lost on back navigation | race_composer_screen.dart |
| STATE-006 | P2 | Race Composer | State | No loading indicator on "Start race"; button just disables | race_composer_screen.dart |
| RELEASE-005 | P2 | Race Composer | Release | `NUVO_DIAGNOSTICS` env var can expose debug UI in release | race_composer_screen.dart |
| COPY-010 | P2 | Race Composer | Copy | Generic instructional copy on multiple steps | race_composer_screen.dart |
| CONSISTENCY-011 | P2 | Race Composer | Consistency | Button heights may differ between NuvoPrimary/NuvoSecondary | race_composer_screen.dart |
| HIERARCHY-009 | P3 | Race Composer | Hierarchy | Excessive flutter_animate on every text element | race_composer_screen.dart |
| RELEASE-006 | P2 | Create Race | Release | `CreateRaceScreen` widget class is dead (file is live via `RaceCreatePrefill`) | create_race_screen.dart |
| INTERACTION-014 | P1 | Join Race | Interaction | Generic error; no distinction invalid/expired/full; silent success | join_race_screen.dart |
| INTERACTION-015 | P3 | Join Race | Interaction | No keyboard dismissal on join | join_race_screen.dart |
| LAYOUT-005 | P2 | Race Detail | Layout | Leaderboard buried below path/pulse/standings | race_detail_screen.dart |
| HIERARCHY-010 | P1 | Race Detail | Hierarchy | Competing primary actions (summary/invite/manage) | race_detail_screen.dart |
| INTERACTION-016 | P1 | Race Detail | Interaction | Duplicate routes `/edit` and `/settings` → same screen | router.dart, race_detail_screen.dart |
| STATE-007 | P2 | Race Detail | State | Silent background refresh failures; stale data undetected | race_detail_screen.dart |
| CONSISTENCY-012 | P2 | Race Detail | Consistency | Inconsistent section spacing (12/14/18/24) | race_detail_screen.dart |
| COPY-011 | P3 | Race Detail | Copy | "Board moved X times recently" vague + technical | race_detail_screen.dart |
| HIERARCHY-011 | P3 | Race Detail | Hierarchy | Manage section is card soup (4 identical rows) | race_detail_screen.dart |
| INTERACTION-017 | P1 | Invite Crew | Interaction | Search debounce 280ms too short; excess API calls | invite_crew_screen.dart |
| LAYOUT-006 | P2 | Invite Crew | Layout | Invite code card visually dominates over add-to-race actions | invite_crew_screen.dart |
| COPY-012 | P2 | Invite Crew | Copy | Empty-state copy robotic | invite_crew_screen.dart |
| STATE-008 | P3 | Invite Crew | State | No loading indicator in search results area | invite_crew_screen.dart |
| INTERACTION-018 | P1 | Submit Proof | Interaction | Back button lacks `_navigating` double-tap guard | submit_proof_screen.dart |
| LAYOUT-007 | P2 | Submit Proof | Layout | Pre-verify animation fixed 340px; CTA below fold on small iPhones | submit_proof_screen.dart |
| COPY-013 | P3 | Submit Proof | Copy | "~3 sec per rep" hardcoded assumption exposed | submit_proof_screen.dart |
| HIERARCHY-012 | P1 | Race Settings | Hierarchy | 3 destructive actions full-width at bottom of scroll form | race_settings_screen.dart |
| COPY-014 | P1 | Race Settings | Copy | "unsupported movement" + "Lifecycle" + "Danger zone" dev-facing | race_settings_screen.dart |
| CONSISTENCY-013 | P2 | Race Settings | Consistency | Inconsistent input patterns (camera vs non-camera goal) | race_settings_screen.dart |
| STATE-009 | P2 | Race Settings | State | Form state lost on save failure if user navigates away | race_settings_screen.dart |
| INTERACTION-019 | P2 | Race Settings | Interaction | No keyboard dismissal on save | race_settings_screen.dart |
| RELEASE-007 | P3 | Race Settings | Release | Start/Finish date labels generic; backend field names technical | race_settings_screen.dart |
| HIERARCHY-013 | P1 | Proof Review | Hierarchy | "Reject move" same size as "Accept move"; easy mis-tap | proof_review_screen.dart |
| COPY-015 | P2 | Proof Review | Copy | "move" vs "proof" terminology drift | proof_review_screen.dart |
| STATE-010 | P3 | Proof Review | State | No loading indicator on buttons during save | proof_review_screen.dart |
| COPY-016 | P2 | Board Moved | Copy | "MOVE DIDN'T COUNT" punitive all-caps; user-blaming | board_moved_screen.dart |
| INTERACTION-020 | P3 | Board Moved | Interaction | "Record again" uses pushReplacement; loses celebration | board_moved_screen.dart |
| RELEASE-008 | P2 | Teach Movement | Release | `/internal/teach-movement` route registered in production router | router.dart, teach_movement_screen.dart |
| RELEASE-009 | P2 | Teach Movement | Release | `NUVO_DIAGNOSTICS` env var exposes debug panel in release | teach_movement_screen.dart |
| COPY-017 | P2 | Teach Movement | Copy | Guidance messages robotic ("Step back", "Move into the starting position") | teach_movement_screen.dart |
| INTERACTION-021 | P2 | Teach Movement | Interaction | No confirmation before navigating to race creation | teach_movement_screen.dart |
| STATE-011 | P3 | Teach Movement | State | Camera error display unclear | teach_movement_screen.dart |
| SCALE-001 | P1 | Race Composer | Scale | "See all" category link does nothing; 80% of movements hidden at 100 | race_composer_screen.dart |
| SCALE-002 | P1 | Compete | Scale | Quick Starts hardcoded to 5 movements; static at 100 | compete_screen_fixed.dart |
| SCALE-003 | P1 | Submit Proof | Scale | Demos hand-authored per movement; blocks catalog growth at 100 | preset_movement_demos.dart |
| SCALE-004 | P1 | Race Composer | Scale | Custom movements only in Recent (max 5); vanish after 5 uses | race_composer_screen.dart |
| SCALE-005 | P2 | Race Composer | Scale | Search results non-virtualized Column; slow at 100+ | race_composer_screen.dart |
| SCALE-006 | P2 | Race Composer | Scale | Category tabs no overflow affordance; 20 categories invisible | race_composer_screen.dart |
| SCALE-007 | P2 | Race Composer | Scale | Search is substring-only; no fuzzy/typo tolerance | motion_activity_catalog.dart |
| SCALE-008 | P2 | Race Composer | Scale | Expanded category grid renders all items (no virtualization) | race_composer_screen.dart |
| SCALE-009 | P2 | All | Scale | Only 5 broad categories; overloaded at 100 (30+ per category) | motion_activity.dart |
| SCALE-010 | P3 | Race Composer | Scale | Recent movements capped at 5 | recent_movements_provider.dart |
| SCALE-011 | P3 | Race Composer | Scale | Movement names truncate badly at 100+ (ellipsis) | race_composer_screen.dart |
| SCALE-012 | P3 | All | Scale | `featured` flag exists but no "Popular" section in picker | motion_activity_catalog.dart |
| SCALE-013 | P3 | Race Detail | Scale | Movement name in badge may truncate at 100+ | race_detail_screen.dart |

---

## 4. P0 Findings

**No user-facing P0 issues were found.** The app functions; no screen is broken in a way that prevents completing an important flow.

The subagent's original P0 claim on `create_race_screen.dart` (RELEASE-006) was **corrected after verification**: the file is actively used (`RaceCreatePrefill` is imported by 3 files), only the `CreateRaceScreen` widget class is dead. This is P2 dead-code, not P0 broken.

---

## 5. P1 Findings (22)

| ID | Screen | Issue |
|----|--------|-------|
| RELEASE-002 | Email Start | Hardcoded reviewer emails + dev-only password field in client code |
| RELEASE-003 | Secure Account | Dead passthrough screen; route exists only "for continuity" |
| LAYOUT-001 | Compete | 5 hardcoded Quick Start rows push active races below fold on small iPhones |
| STATE-002 | Compete | Raw backend error string shown to users; no retry |
| STATE-003 | Move | No error state; error silently shows empty state |
| INTERACTION-007 | Move | Completed section collapsed by default (extra friction) |
| INTERACTION-008 | Pass | Search errors silently swallowed; spinner never resolves |
| INTERACTION-009 | Pass | Add-crew double-submission risk |
| LAYOUT-003 | Profile | Race history capped at 6, no "See all" |
| INTERACTION-010 | Profile | Delete account one dialog away; no typing confirmation |
| STATE-004 | Profile | No refresh feedback when stale data displayed |
| RELEASE-004 | Edit Profile | ~13 debugPrint statements in production code |
| INTERACTION-011 | Edit Profile | Save button loading-disable not confirmed; double-submit risk |
| HIERARCHY-008 | Race Composer | "Teach a movement" competes with primary CTA; exits flow |
| INTERACTION-013 | Race Composer | Form state (custom target) lost on back navigation |
| INTERACTION-014 | Join Race | Generic error; no distinction invalid/expired/full; silent success |
| HIERARCHY-010 | Race Detail | Competing primary actions (summary/invite/manage) |
| INTERACTION-016 | Race Detail | Duplicate routes `/edit` and `/settings` → same screen |
| INTERACTION-017 | Invite Crew | Search debounce 280ms too short; excess API calls |
| INTERACTION-018 | Submit Proof | Back button lacks double-tap guard |
| HIERARCHY-012 | Race Settings | 3 destructive actions full-width at bottom of scroll form |
| COPY-014 | Race Settings | "unsupported movement" + "Lifecycle" + "Danger zone" dev-facing |
| HIERARCHY-013 | Proof Review | "Reject move" same size as "Accept move"; easy mis-tap |
| SCALE-001 | Race Composer | "See all" does nothing; 80% of movements hidden at 100 |
| SCALE-002 | Compete | Quick Starts hardcoded to 5 movements; static at 100 |
| SCALE-003 | Submit Proof | Demos hand-authored per movement; blocks catalog growth |
| SCALE-004 | Race Composer | Custom movements only in Recent (max 5); vanish after 5 uses |

---

## 6. P2 Findings (38)

| ID | Screen | Issue |
|----|--------|-------|
| RELEASE-001 | Welcome | TODO + internal doc reference + `_kGoogleEnabled` flag |
| CONSISTENCY-001 | Welcome | Google button is custom GestureDetector, not NuvoButton |
| INTERACTION-001 | Welcome | Google loading is only opacity 0.55; no retry |
| INTERACTION-002 | Email Start | No keyboard handling; CTA obscured on small iPhones |
| INTERACTION-003 | Email Verify | No keyboard handling |
| CONSISTENCY-002 | Create Identity | ALL CAPS labels vs title case on next screen |
| CONSISTENCY-003 | Onboarding (all) | Step indicator hardcoded inline in 4 screens |
| HIERARCHY-002 | Onboarding Profile | Non-functional camera button on avatar |
| COPY-002 | Onboarding Profile | "Username set" always shown; raw exception exposed |
| INTERACTION-004 | Create Identity | No keyboard handling |
| INTERACTION-005 | Onboarding Profile | No keyboard handling |
| STATE-001 | Member Pass | Loading replaces entire screen with spinner |
| INTERACTION-006 | Add Crew | "Continue" and "Skip" both go to same destination |
| COPY-005 | Compete | "Editable camera race" dev-facing |
| HIERARCHY-003 | Compete | Two equal-weight CTAs compete |
| COPY-006 | Move | "Choose a race, then verify your move." robotic |
| HIERARCHY-004 | Move | Status pills 9px font (barely readable) |
| COPY-007 | Pass | "Could not load your crew." generic |
| LAYOUT-002 | Pass | Closest-race track fixed 60px + manual positioning |
| HIERARCHY-006 | Profile | 4 equal-weight stats; no primary metric |
| COPY-008 | Profile | "Could not delete account. Try again." generic |
| STATE-005 | Edit Profile | Photo upload failure keeps pending preview |
| COPY-009 | Edit Profile | "Nuvo hit a snag. Try again." cutesy |
| CONSISTENCY-010 | Bottom Nav | Screen-local colors `_kTrackNavy`/`_kTrackActiveBlue` |
| STATE-006 | Race Composer | No loading indicator on "Start race" |
| RELEASE-005 | Race Composer | `NUVO_DIAGNOSTICS` env var exposes debug UI in release |
| COPY-010 | Race Composer | Generic instructional copy on multiple steps |
| CONSISTENCY-011 | Race Composer | Button heights may differ between variants |
| RELEASE-006 | Create Race | `CreateRaceScreen` widget class dead (file live via `RaceCreatePrefill`) |
| LAYOUT-005 | Race Detail | Leaderboard buried below path/pulse/standings |
| STATE-007 | Race Detail | Silent background refresh failures |
| CONSISTENCY-012 | Race Detail | Inconsistent section spacing (12/14/18/24) |
| LAYOUT-006 | Invite Crew | Invite code card visually dominates over add actions |
| COPY-012 | Invite Crew | Empty-state copy robotic |
| LAYOUT-007 | Submit Proof | Pre-verify animation fixed 340px; CTA below fold |
| CONSISTENCY-013 | Race Settings | Inconsistent input patterns (camera vs non-camera) |
| STATE-009 | Race Settings | Form state lost on save failure if user navigates away |
| INTERACTION-019 | Race Settings | No keyboard dismissal on save |
| COPY-015 | Proof Review | "move" vs "proof" terminology drift |
| COPY-016 | Board Moved | "MOVE DIDN'T COUNT" punitive all-caps |
| RELEASE-008 | Teach Movement | `/internal/teach-movement` route registered in production |
| RELEASE-009 | Teach Movement | `NUVO_DIAGNOSTICS` env var exposes debug panel |
| COPY-017 | Teach Movement | Guidance messages robotic |
| INTERACTION-021 | Teach Movement | No confirmation before navigating to race creation |
| SCALE-005 | Race Composer | Search results non-virtualized Column |
| SCALE-006 | Race Composer | Category tabs no overflow affordance |
| SCALE-007 | Race Composer | Search substring-only; no fuzzy/typo tolerance |
| SCALE-008 | Race Composer | Expanded category grid renders all items |
| SCALE-009 | All | Only 5 broad categories; overloaded at 100 |

---

## 7. P3 Findings (28)

| ID | Screen | Issue |
|----|--------|-------|
| HIERARCHY-001 | Welcome | Over-decorated hero (5 private widgets, decorative pills) |
| COPY-001 | Email Verify | "Nuvo hit a snag. Try again." cutesy |
| CONSISTENCY-004 | Create Identity | Inline BoxShadow instead of AppShadows |
| CONSISTENCY-005 | Onboarding Profile | Privacy toggle inline custom Container |
| CONSISTENCY-006 | Member Pass | Verification info card inline custom Container |
| CONSISTENCY-007 | First Race | TemplateCard inline BoxShadow |
| COPY-003 | Add Crew | "Your crew is waiting at the start line." cliché |
| COPY-004 | First Race | Section label + subtitle redundant |
| CONSISTENCY-008 | Compete | Inconsistent section spacing (0 vs 24) |
| HIERARCHY-005 | Pass | Pass/search/crew list all similar visual weight |
| CONSISTENCY-009 | Profile | Screen-local color constants |
| HIERARCHY-007 | Edit Profile | 104×104 centered photo pushes form below fold |
| INTERACTION-012 | Bottom Nav | "Verify" isPrimary styling not communicated |
| LAYOUT-004 | Bottom Nav | Complex height calc with 8 constants |
| HIERARCHY-009 | Race Composer | Excessive flutter_animate on every text element |
| INTERACTION-015 | Join Race | No keyboard dismissal on join |
| COPY-011 | Race Detail | "Board moved X times recently" vague |
| HIERARCHY-011 | Race Detail | Manage section card soup (4 identical rows) |
| STATE-008 | Invite Crew | No loading indicator in search results |
| COPY-013 | Submit Proof | "~3 sec per rep" hardcoded assumption |
| RELEASE-007 | Race Settings | Start/Finish labels generic; backend field names technical |
| STATE-010 | Proof Review | No loading indicator on buttons during save |
| INTERACTION-020 | Board Moved | "Record again" pushReplacement loses celebration |
| STATE-011 | Teach Movement | Camera error display unclear |
| SCALE-010 | Race Composer | Recent movements capped at 5 |
| SCALE-011 | Race Composer | Movement names truncate badly at 100+ |
| SCALE-012 | All | `featured` flag exists but no "Popular" section |
| SCALE-013 | Race Detail | Movement name in badge may truncate at 100+ |

---

## 8. Movement-Scale Findings (100–250 movements)

**Current state:** 13 preset movements, 5 categories, 7 flagged `featured` (unused in UI), recent capped at 5, search is substring-only, demos hand-authored per movement, custom movements only appear in Recent.

### What breaks at scale

| At | What breaks |
|----|-------------|
| **25** | "See all" doing nothing becomes noticeable (5 categories × 5 movements = 25, capped at 4 displayed) |
| **50** | Recent (max 5) can't hold a week of diverse usage; custom movements vanish; search results scroll excessively |
| **100** | Category tabs overflow with no affordance; "Lower Body" has 30+ movements; Quick Starts still show the original 5; demos require authoring 100×50 lines = 5000 lines of key poses |
| **250** | Substring search returns too many results; 5 categories are meaningless (50 per category); movement names truncate badly; no favorites/pin mechanism |

### Top 4 scale fixes (by impact)

1. **SCALE-001 (P1):** Make "See all" actually expand the category section inline. One-line fix to toggle `showAll` on tap.
2. **SCALE-002 (P1):** Replace hardcoded Quick Starts with the user's 5 most recent movements from `recentMovementIdsProvider`. Auto-personalizes, scales automatically.
3. **SCALE-003 (P1):** Make demos optional. Movements without demos already skip the pre-verify screen — formalize this so adding a movement doesn't require authoring a demo.
4. **SCALE-004 (P1):** Add a "My movements" section/tab for custom (Teach Nuvo) movements so they don't vanish after 5 recents.

### Scale mechanisms report

| Mechanism | Current | File |
|-----------|---------|------|
| Categories | 5 (Upper Body, Lower Body, Cardio, Core, Full Body) | `motion_activity.dart:90-103` |
| Featured flag | 7 of 13 set `featured: true`; **not used in UI** | `motion_activity_catalog.dart` |
| Recent | Max 5, persisted in `FlutterSecureStorage` as JSON array of backend IDs | `recent_movements_provider.dart:20` |
| Search | Substring on title + aliases; no fuzzy/typo tolerance | `motion_activity_catalog.dart:395-413` |
| Custom movements | Only in Recent; not in categories or search | `race_composer_screen.dart:862-886` |
| Demos | Hand-authored switch statement, 13 cases, ~50 lines each | `preset_movement_demos.dart:776-792` |

---

## 9. Navigation / Interaction Findings

| ID | Issue |
|----|-------|
| INTERACTION-006 | Add Crew: "Continue" and "Skip" both go to `/onboarding/first-race` — meaningless choice |
| INTERACTION-016 | Race Detail: `/race/:id/edit` and `/race/:id/settings` both → `RaceSettingsScreen` — duplicate routes |
| INTERACTION-020 | Board Moved: "Record again" uses `pushReplacement` — loses celebration in nav stack |
| RELEASE-003 | Secure Account: dead passthrough route `/onboarding/secure-account` |
| RELEASE-008 | Teach Movement: `/internal/teach-movement` registered in production router (reachable by deep link) |
| INTERACTION-013 | Race Composer: custom target value lost on back navigation (edit mode not committed) |
| INTERACTION-009 | Pass: add-crew double-submission risk (loading state race) |
| INTERACTION-011 | Edit Profile: save button loading-disable not confirmed |
| INTERACTION-018 | Submit Proof: back button lacks double-tap guard |
| INTERACTION-010 | Profile: delete account one dialog away, no typing confirmation |

---

## 10. Design-System Inconsistencies

**Visible to users (matters more):**
- CONSISTENCY-002: ALL CAPS input labels on Create Identity vs title case on Onboarding Profile — visible within the same flow.
- CONSISTENCY-003: Step indicator hardcoded in 4 onboarding screens — styling can drift between them.
- CONSISTENCY-011: Button heights may differ between `NuvoPrimaryButton` and `NuvoSecondaryButton` when both `expand: true`.
- CONSISTENCY-012: Race Detail section spacing is 12/14/18/24 with no pattern.
- CONSISTENCY-013: Race Settings camera vs non-camera goal sections look unrelated.

**Code-only (matters less):**
- CONSISTENCY-001, 004, 005, 006, 007, 008, 009, 010: inline shadows, inline containers, screen-local color constants. Users can't perceive these unless they drift.
- `NuvoColors` vs `AppColors` duplication in `app_colors.dart` — two classes, same tokens, different names. Legacy aliases (`platinum`, `icyBlue`, `softBlue`, `lavenderRow`) add confusion but are not user-visible.

---

## 11. Copy Problems

| ID | Screen | Bad copy | Suggested replacement |
|----|--------|----------|----------------------|
| COPY-001 | Email Verify | "Nuvo hit a snag. Try again." | "Something went wrong. Please try again." |
| COPY-002 | Onboarding Profile | "Username set" (always shown, redundant) | Remove the row entirely |
| COPY-003 | Add Crew | "Your crew is waiting at the start line." | "Add crew members anytime from the Crew tab." |
| COPY-004 | First Race | Section label "Quick starts" + subtitle "Choose a race template" | Remove subtitle, keep label |
| COPY-005 | Compete | "Editable camera race" | "Camera-verified race" or remove sublabel |
| COPY-006 | Move | "Choose a race, then verify your move." | "Your active races are ready." |
| COPY-007 | Pass | "Could not load your crew." | "Couldn't load your crew. Check your connection and try again." |
| COPY-008 | Profile | "Could not delete account. Try again." | "Couldn't delete your account. Check your connection and try again." |
| COPY-009 | Edit Profile | "Nuvo hit a snag. Try again." | "Something went wrong. Please try again." |
| COPY-010 | Race Composer | "Give your crew something worth chasing" / "Camera verifies every rep" | "What are you racing toward?" / "AI counts each rep automatically." |
| COPY-011 | Race Detail | "Board moved X times recently" | "X moves in the last hour" |
| COPY-012 | Invite Crew | "No matching Nuvo members found." | "No one matches that name." |
| COPY-013 | Submit Proof | "~3 sec per rep" hardcoded estimate | Remove specific estimate or use a range ("1–2 min") |
| COPY-014 | Race Settings | "unsupported movement" / "Lifecycle" / "Danger zone" | "Camera verification not available" / "Race status" / "Delete race" |
| COPY-015 | Proof Review | "Review move" / "Accept move" / "Reject move" | "Review proof" / "Accept proof" / "Reject proof" |
| COPY-016 | Board Moved | "MOVE DIDN'T COUNT" / "Try again with a clearer move" | "Move not verified" / "Try again — make sure your whole body is visible" |
| COPY-017 | Teach Movement | "Step back" / "Move into the starting position" | "Step back so your whole body is visible" / "Stand in your starting position" |

**Terminology drift:** "move" is used where product language requires "proof" (Proof Review, Board Moved). "Lifecycle" and "Danger zone" are technical. "Editable camera race" is dev-facing.

---

## 12. Loading / Error / Empty-State Problems

| ID | Screen | Problem |
|----|--------|---------|
| STATE-001 | Member Pass | Loading replaces entire screen with spinner (layout jump) |
| STATE-002 | Compete | Raw backend error string shown; no retry |
| STATE-003 | Move | No error state; error silently shows empty state |
| STATE-004 | Profile | No refresh feedback when stale data displayed |
| STATE-005 | Edit Profile | Photo upload failure keeps pending preview (confusing) |
| STATE-006 | Race Composer | No loading indicator on "Start race" |
| STATE-007 | Race Detail | Silent background refresh failures; stale data undetected |
| STATE-008 | Invite Crew | No loading indicator in search results |
| STATE-009 | Race Settings | Form state lost on save failure if user navigates away |
| STATE-010 | Proof Review | No loading indicator on buttons during save |
| STATE-011 | Teach Movement | Camera error display unclear |

**Pattern:** Most network-backed screens either show raw errors (Compete) or silently swallow them (Move, Pass search, Race Detail refresh). There is no consistent error/retry component used across all screens — `NuvoErrorState` exists but is not used everywhere.

---

## 13. Release Hygiene Findings

| ID | Screen | Issue |
|----|--------|-------|
| RELEASE-001 | Welcome | TODO + `_kGoogleEnabled` flag + internal doc reference (`GOOGLE_OAUTH_FIX_PLAN.md`) |
| RELEASE-002 | Email Start | Hardcoded reviewer emails (`team@getnuvo.net`, `testing@getnuvo.net`, `testing@getnuvo`) |
| RELEASE-003 | Secure Account | Dead passthrough screen + route |
| RELEASE-004 | Edit Profile | ~13 `debugPrint` statements in production (`PROFILE_PHOTO_SHEET_OPENED`, `PENDING_IMAGE_BYTES_SET`, etc.) |
| RELEASE-005 | Race Composer | `NUVO_DIAGNOSTICS` env var (`bool.fromEnvironment`) can expose debug UI in release if `--dart-define` is set |
| RELEASE-006 | Create Race | `CreateRaceScreen` widget class is dead (file is live via `RaceCreatePrefill` — cannot delete file without moving class) |
| RELEASE-007 | Race Settings | Start/Finish date labels generic; backend field names technical |
| RELEASE-008 | Teach Movement | `/internal/teach-movement` route registered in production router (reachable by deep link; `fixture=ready` seeding is `kDebugMode`-guarded) |
| RELEASE-009 | Teach Movement | `NUVO_DIAGNOSTICS` env var exposes debug panel with similarity scores |

**Debug-only verification:** `seedReadyFixture` on `/internal/teach-movement` IS guarded by `kDebugMode` (router.dart:228) — good. But the route itself is registered unconditionally — the screen is reachable. `kNuvoDiagnosticsEnabled` uses `bool.fromEnvironment('NUVO_DIAGNOSTICS')` which is NOT `kDebugMode`-guarded — it can be enabled in release via `--dart-define=NUVO_DIAGNOSTICS=true`.

---

## 14. Security Follow-Up (Backend, NOT UI Work)

These are backend/architecture issues discovered through UI inspection. They are **not** UI fixes and should be tracked separately.

| ID | Issue | Where | Notes |
|----|-------|-------|-------|
| SEC-001 | Client-trusted proof model | `ai_motion_proof_screen_io.dart` → `race_api.dart` → `races.ts:678` | Server trusts client-reported rep counts without re-verification. Compromised client can submit arbitrary reps. |
| SEC-002 | No rate limiting (except OTP) | `server/worker/src/` | OTP, race creation, proof submission all unthrottled. |
| SEC-003 | Admin routes lack role check | `reports.ts:127,157` | `/reports/admin/*` only require `requireAuth` — any authenticated user can list/update reports. |
| SEC-004 | Terms bypassed | `lib/terms.ts` | `hasAcceptedTerms` always returns true (dev override). |
| SEC-005 | Hardcoded reviewer credentials in client | `email_start_screen.dart:42-45` | `team@getnuvo.net` etc. in client code. Dev-only auth path discoverable. |
| SEC-006 | `/internal/teach-movement` reachable in production | `router.dart:223` | Route registered unconditionally; only fixture seeding is `kDebugMode`-guarded. |

---

## 15. Recommended Implementation Batches

Each batch is sized 3–8 tightly related findings. Batches are ordered by user impact, not by category.

### Batch 1: Network state handling (Compete + Move + Pass)
**Findings:** STATE-002, STATE-003, INTERACTION-008, COPY-007
**Files:** `compete_screen_fixed.dart`, `move_screen.dart`, `pass_screen.dart`
**Risk:** Low-medium (state handling only, no layout/architecture changes)
**Phone testing required:** Yes — test error/empty/offline states on each screen
**Expected improvement:** Users can distinguish "no races" from "network failed"; search errors don't leave users stuck
**Approach:** Use existing `NuvoErrorState` with retry on all three screens. Add error check before empty state on Move. Surface search errors on Pass.

### Batch 2: Small-iPhone layout fixes (CTA below fold)
**Findings:** LAYOUT-001, LAYOUT-007, INTERACTION-002, INTERACTION-003, INTERACTION-004, INTERACTION-005
**Files:** `compete_screen_fixed.dart`, `submit_proof_screen.dart`, `email_start_screen.dart`, `email_verify_screen.dart`, `create_identity_screen.dart`, `onboarding_screen.dart`
**Risk:** Low (padding/height adjustments + `resizeToAvoidBottomInset`)
**Phone testing required:** Yes — test on iPhone SE (375×667) and iPhone 12 mini (375×812)
**Expected improvement:** Primary CTAs visible without scrolling on small devices; keyboard doesn't obscure CTAs
**Approach:** Reduce Quick Starts to 2-3 rows or horizontal rail. Make pre-verify animation height responsive. Add `resizeToAvoidBottomInset: true` to form screens.

### Batch 3: Destructive action safety
**Findings:** INTERACTION-010, HIERARCHY-012, HIERARCHY-013, COPY-014
**Files:** `profile_screen.dart`, `race_settings_screen.dart`, `proof_review_screen.dart`
**Risk:** Low-medium (confirmation flows, button sizing)
**Phone testing required:** Yes — test each destructive flow end-to-end
**Expected improvement:** Accidental deletion/rejection much harder; destructive actions visually distinct from primary actions
**Approach:** Add typing confirmation ("DELETE") for account deletion. Make Archive/Cancel/Delete small buttons in a grouped section. Make "Reject proof" smaller than "Accept proof". Rename "Danger zone" → "Delete race".

### Batch 4: Release hygiene cleanup
**Findings:** RELEASE-002, RELEASE-003, RELEASE-004, RELEASE-005, RELEASE-008, RELEASE-009
**Files:** `email_start_screen.dart`, `secure_account_screen.dart`, `edit_profile_screen.dart`, `race_composer_screen.dart`, `router.dart`, `teach_movement_screen.dart`
**Risk:** Low (removing debug code, guarding routes)
**Phone testing required:** No — verify in debug mode that dev tools still work
**Expected improvement:** No debug UI or dev credentials in production; no internal routes reachable
**Approach:** Move reviewer emails to backend config. Remove SecureAccountScreen + route. Remove `debugPrint`s in EditProfile. Guard `kNuvoDiagnosticsEnabled` with `kDebugMode &&`. Guard `/internal/teach-movement` route registration with `kDebugMode`.

### Batch 5: Race Composer flow fixes
**Findings:** HIERARCHY-008, INTERACTION-013, STATE-006, COPY-010
**Files:** `race_composer_screen.dart`
**Risk:** Medium (touches the main race creation flow)
**Phone testing required:** Yes — test full 5-step flow on small + large devices
**Expected improvement:** No competing CTA on activity step; no lost form state; clear loading on submit; better copy
**Approach:** Demote "Teach a movement" to a small tertiary link at top of activity page. Commit edit on step change. Pass `_loading` to review CTA. Rewrite generic copy.

### Batch 6: Race Detail hierarchy + duplicate routes
**Findings:** LAYOUT-005, HIERARCHY-010, INTERACTION-016, STATE-007
**Files:** `race_detail_screen.dart`, `router.dart`
**Risk:** Medium (touches the primary race screen)
**Phone testing required:** Yes — test as participant and as creator
**Expected improvement:** Leaderboard is the hero; one clear primary action; no duplicate routes; stale data indicated
**Approach:** Move "The board" section above path/pulse. Demote "Invite crew" to a ghost button in manage section. Remove `/race/:id/edit` route. Add "Updated X min ago" indicator.

### Batch 7: Movement picker scale (100-movement readiness)
**Findings:** SCALE-001, SCALE-002, SCALE-003, SCALE-004
**Files:** `race_composer_screen.dart`, `compete_screen_fixed.dart`, `preset_movement_demos.dart`, `submit_proof_screen.dart`
**Risk:** Medium (touches movement discovery across multiple screens)
**Phone testing required:** Yes — test with a 25+ movement catalog
**Expected improvement:** Users can discover movements beyond the first 4 per category; Quick Starts personalize; custom movements don't vanish; adding movements doesn't require demo authoring
**Approach:** Make "See all" toggle `showAll`. Replace hardcoded Quick Starts with `recentMovementIdsProvider`. Formalize optional demos. Add "My movements" section for custom movements.

### Batch 8: Copy consistency sweep
**Findings:** COPY-001, COPY-005, COPY-006, COPY-009, COPY-015, COPY-016, COPY-017
**Files:** `email_verify_screen.dart`, `compete_screen_fixed.dart`, `move_screen.dart`, `edit_profile_screen.dart`, `proof_review_screen.dart`, `board_moved_screen.dart`, `teach_movement_screen.dart`
**Risk:** Low (string replacements only)
**Phone testing required:** No — visual review only
**Expected improvement:** Consistent tone; "proof" not "move"; no punitive all-caps; no cutesy "hit a snag"
**Approach:** Apply the replacements from §11. Standardize on "proof" terminology.

### Batch 9: Onboarding flow cleanup
**Findings:** CONSISTENCY-002, CONSISTENCY-003, HIERARCHY-002, COPY-002, INTERACTION-006
**Files:** `create_identity_screen.dart`, `onboarding_screen.dart`, `add_crew_screen.dart`, `first_race_screen.dart`
**Risk:** Low-medium (onboarding only, no auth logic)
**Phone testing required:** Yes — test full onboarding flow
**Expected improvement:** Consistent labels; shared step indicator; no non-functional camera button; no meaningless Skip/Continue choice
**Approach:** Change ALL CAPS labels to title case. Extract `NuvoStepIndicator` and use in all 4 screens. Remove camera button decoration or make it functional. Remove redundant "Username set" row. Make "Skip" actually skip (or remove it).

### Batch 10: Dead code + design-system drift (low priority)
**Findings:** RELEASE-006, CONSISTENCY-010, CONSISTENCY-009, RELEASE-001, RELEASE-007
**Files:** `create_race_screen.dart`, `bottom_nav.dart`, `profile_screen.dart`, `welcome_auth_screen.dart`, `race_settings_screen.dart`
**Risk:** Low (cleanup, no behavior change)
**Phone testing required:** No
**Expected improvement:** Less code confusion; colors come from tokens
**Approach:** Move `RaceCreatePrefill` to a shared file, then remove dead `CreateRaceScreen` widget. Replace `_kTrackNavy`/`_kTrackActiveBlue` with `NuvoColors` tokens. Remove `_kProfileBorder`/`_kProfileTextMuted`. Remove TODO + internal doc reference in Welcome. Clarify Start/Finish labels.

---

## Final Summary

- **Total screens inspected:** 22 (excluding Arena)
- **Total findings:** 95
- **P0 count:** 0 (one subagent P0 corrected to P2 after verification)
- **P1 count:** 22
- **P2 count:** 38
- **P3 count:** 28
- **Scale findings:** 13

### Top 10 highest-value fixes
1. **STATE-003** (Move): Add error state — users think they have no races when the network failed
2. **STATE-002** (Compete): Replace raw backend errors with friendly retry
3. **INTERACTION-008** (Pass): Surface search errors — spinner never resolves
4. **LAYOUT-001** (Compete): Reduce Quick Start rows — active races buried on small iPhones
5. **INTERACTION-010** (Profile): Add typing confirmation for account deletion
6. **HIERARCHY-012** (Race Settings): Make destructive actions smaller/grouped
7. **RELEASE-002** (Email Start): Remove hardcoded reviewer emails from client
8. **HIERARCHY-008** (Race Composer): Demote "Teach a movement" — it exits the flow
9. **SCALE-001** (Race Composer): Make "See all" work — 80% of movements hidden at 100
10. **LAYOUT-005** (Race Detail): Move leaderboard above path/pulse — it's the screen's purpose

### Top 5 "AI UI" patterns found
1. **Card soup** — Race Detail manage section (4 identical `_ManageRow` cards), Compete Quick Starts (5 identical rows)
2. **Text soup** — Race Composer instructional copy ("Give your crew something worth chasing", "Camera verifies every rep")
3. **Over-designed empty/decorative states** — Welcome `_LoopStrip` (4 decorative pills), AddCrew placeholder, Onboarding non-functional camera button
4. **Everything animated** — Race Composer animates every text element per step with staggered delays
5. **Generic copy** — "Nuvo hit a snag" (×2 screens), "Your crew is waiting at the start line", "Editable camera race"

### Screens with unnecessary scrolling
- **Compete** — 5 Quick Start rows force scroll to see active races on small iPhones
- **Submit Proof** — fixed 340px pre-verify animation forces scroll to CTA on small iPhones
- **Race Detail** — leaderboard buried below 3-4 sections
- **Race Composer (activity step)** — category sections can stack beyond viewport on small iPhones

### Screens most at risk on smaller iPhones (375×667 / 375×812)
1. **Compete** — Quick Starts + hero + active races don't fit
2. **Submit Proof** — 340px animation + CTA don't fit
3. **Race Composer (activity step)** — categories + CTA don't fit
4. **Email Start / Email Verify / Create Identity / Onboarding Profile** — no keyboard handling, CTA may be obscured
5. **Edit Profile** — 104×104 photo + form fields don't fit

### Screens most at risk when movement count reaches 100
1. **Race Composer (activity picker)** — "See all" broken, categories overflow, search not fuzzy, custom movements vanish
2. **Compete** — Quick Starts hardcoded to 5, won't reflect the 100-movement catalog
3. **Submit Proof** — demos required per movement, blocks catalog growth
4. **Race Detail** — movement name in badge may truncate

### Recommended Batch 1
**Network state handling (Compete + Move + Pass)** — 4 findings, 3 files, low-medium risk, high user impact. Use existing `NuvoErrorState` with retry. Test error/empty/offline states on each screen.

### Exact file created
`docs/UI_UX_DEBT_AUDIT.md` (this file)

### Confirmation
**NO production code was modified.** Only this audit document was created. No `.dart` files were edited, no routes were changed, no backend code was touched, no Arena files were inspected for redesign purposes, and no commits were made.
