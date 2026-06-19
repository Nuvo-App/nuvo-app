# Button Audit

_Last updated: 2026-06-19 — UX simplification pass_

## Summary

- Primary/action buttons using real backend data: 34
- Working local UI only: 10
- Coming soon placeholder: 8
- Disabled by design: 2
- Fake-data actions remaining in active screens: 0

## Live Demo UX Update - 2026-06-19

- `10 Jumping Jacks` quick start now opens Create Race with AI Motion Proof metadata instead of a blank manual race.
- Create Race uses `Start AI race` for the supported 10 Jumping Jacks AI template and `Start a race` otherwise.
- Submit Proof shows `Start AI proof` as the primary path only for supported AI Motion races.
- Manual races show manual proof as the primary action and an unavailable AI card for non-supported activities.
- AI Motion Proof actions are in a SafeArea-respecting bottom CTA area: `Start camera`, `Record proof`, `Done`, `Cancel`, `Submit verified proof`, `Record again`, and `Use manual proof`.
- Race Detail no longer shows Archive/Cancel/Delete action chips; destructive actions remain in Race Settings/Danger Zone with confirmation.
- Create Race, Submit Proof, AI Motion Proof, Race Detail, Edit Profile, and Race Settings use the standard `NuvoBackButton`.

## Working With Real Backend Data

| Button / action | File | Behavior |
|---|---|---|
| Continue with Google | `lib/features/auth/presentation/welcome_auth_screen.dart` | **Disabled** — `_kGoogleEnabled = false`. Non-interactive "needs setup" row shown. Code fully restored and ready; flip flag to `true` after completing GOOGLE_OAUTH_FIX_PLAN.md external steps. |
| Continue with Email | `lib/features/auth/presentation/welcome_auth_screen.dart` | Opens email auth flow (primary CTA, always active). |
| Send code | `lib/features/auth/presentation/email_start_screen.dart` | Calls `/auth/email/start`. |
| Verify code | `lib/features/auth/presentation/email_verify_screen.dart` | Calls `/auth/email/verify`. |
| Resend code | `lib/features/auth/presentation/email_verify_screen.dart` | Calls `/auth/email/start` again (styled as tappable blue text). |
| Continue / save profile | `lib/features/onboarding/presentation/create_identity_screen.dart` | Saves profile through backend auth/profile controller. |
| Continue / profile onboarding | `lib/features/onboarding/presentation/onboarding_screen.dart` | Saves profile/privacy state through backend. |
| Share pass | `lib/features/onboarding/presentation/member_pass_screen.dart` | Shares real pass URL from `/pass/me`. |
| Copy link | `lib/features/onboarding/presentation/member_pass_screen.dart` | Copies real pass URL from `/pass/me`. |
| Start this race | `lib/features/onboarding/presentation/first_race_screen.dart` | Creates a real race from the selected template, then completes onboarding. |
| Explore app | `lib/features/onboarding/presentation/first_race_screen.dart` | Completes onboarding through backend. |
| Start a race / Start AI race | `arena_screen.dart`, `compete_screen.dart`, `create_race_screen.dart` | Navigates to or creates a real race; AI CTA preserves 10 Jumping Jacks metadata. |
| Start another race | `race_detail_screen.dart` | Navigates to Create Race when user's own progress ≥ 100% on an active race. |
| Submit more proof | `race_detail_screen.dart` | Ghost secondary CTA when user progress ≥ 100%; still submits to proof endpoint. |
| Create race submit | `lib/features/races/presentation/create_race_screen.dart` | Calls `POST /races`. |
| Race card tap | `arena_screen.dart`, `compete_screen.dart` | Opens real race detail. |
| Submit proof | `race_detail_screen.dart`, `proof_screen.dart`, `submit_proof_screen.dart` | Opens or submits through real proof route; form calls `POST /races/:id/proof`. |
| Start AI proof | `lib/features/races/presentation/submit_proof_screen.dart` | Opens the on-device AI Motion Proof camera flow. |
| Start camera / Record / Done | `lib/features/races/presentation/ai_motion_proof_screen.dart` | Starts the iPhone camera stream, runs local pose detection, and finalizes the local rep count. |
| Submit verified proof | `lib/features/races/presentation/ai_motion_proof_screen.dart` | Sends only the verified AI motion result to `POST /races/:id/proof`. |
| Back to race | `lib/features/races/presentation/submit_proof_screen.dart` | Returns to the real race detail. |
| Edit profile | `lib/features/profile/presentation/profile_screen.dart` | Opens edit profile screen. |
| Save profile | `lib/features/profile/presentation/edit_profile_screen.dart` | Saves profile through backend. |
| Sign out | `lib/features/profile/presentation/profile_screen.dart` | Logs out through auth controller and clears protected state. |
| Save changes | `lib/features/races/presentation/race_settings_screen.dart` | Calls `PATCH /races/:id`. |
| Archive race | `race_settings_screen.dart` | Calls `POST /races/:id/archive` after confirmation. |
| Cancel race | `race_settings_screen.dart` | Calls `POST /races/:id/cancel` after confirmation. |
| Delete race | `race_settings_screen.dart` | Calls `DELETE /races/:id` after confirmation. |
| Leave race | `lib/features/race_detail/presentation/race_detail_screen.dart` | Calls `POST /races/:id/leave` after confirmation. |
| Join race | `race_detail_screen.dart`, `join_race_screen.dart` | Calls direct join or `POST /races/join-code`. |
| Invite crew | `race_detail_screen.dart` | Opens invite screen. |
| Create invite code | `lib/features/races/presentation/invite_crew_screen.dart` | Calls `POST /races/:id/invite-code`. |
| Copy code | `race_detail_screen.dart`, `invite_crew_screen.dart` | Uses backend invite code; creator can create one first. |
| Review proof | `proof_review_screen.dart`, `race_detail_screen.dart` | Opens proof review and calls `PATCH /races/:id/proofs/:proofId`. |

## Working Local UI Only

| Button / action | File | Behavior |
|---|---|---|
| Signup/login toggle | `lib/features/auth/presentation/welcome_auth_screen.dart` | Switches local welcome copy only. |
| Template chips | `lib/features/races/presentation/create_race_screen.dart` | Fill local create-race form fields. |
| Quick-start tiles | `lib/features/compete/presentation/compete_screen.dart` | Navigate to create-race flow; templates are suggestions only. |
| Onboarding quick-start chips | `lib/features/onboarding/presentation/first_race_screen.dart` | Select a template before real race creation. |
| Notifications bell | `lib/features/arena/presentation/arena_screen.dart` | Opens honest empty updates sheet. |
| Notifications setting | `lib/features/profile/presentation/profile_screen.dart` | Opens honest empty updates sheet. |
| Share race | `lib/features/race_detail/presentation/race_detail_screen.dart` | Opens native share sheet with current race title. |
| Back buttons | Multiple screens | Use `safePopOrGo` or normal router navigation with fallbacks where needed. |
| Lifecycle confirmation dialogs | `race_detail_screen.dart`, `race_settings_screen.dart` | Local confirmation before backend action. |
| Proof review summary field | `lib/features/races/presentation/proof_review_screen.dart` | Local text input sent with review status. |

## Coming Soon Placeholder

| Button / action | File | Status |
|---|---|---|
| QR scanner on Pass | `lib/features/pass/presentation/pass_screen.dart` | Coming soon placeholder; no fake scan result. |
| Crew search field | `lib/features/onboarding/presentation/add_crew_screen.dart` | Coming soon placeholder; no fake users. |
| QR scanner in Add Crew | `lib/features/onboarding/presentation/add_crew_screen.dart` | Coming soon placeholder; no fake scan result. |
| Scan QR action tile | `lib/features/onboarding/presentation/add_crew_screen.dart` | Coming soon placeholder. |
| Invite link action tile | `lib/features/onboarding/presentation/add_crew_screen.dart` | Direct race links coming soon. |
| Contacts action tile | `lib/features/onboarding/presentation/add_crew_screen.dart` | Contact invites coming soon. |
| Privacy settings row | `lib/features/profile/presentation/profile_screen.dart` | Coming soon sheet; no fake privacy state. |
| Push-up AI proof | `lib/features/races/ai/push_up_counter.dart` | Experimental scaffold only; not visible as a primary v1 flow. |

## Button System

| Variant | File | Use |
|---|---|---|
| `NuvoPrimaryButton` | `lib/core/widgets/nuvo_button.dart` | Royal-blue CTA with navy offset backplate. |
| `NuvoOutlineButton` / `NuvoSecondaryButton` | `lib/core/widgets/nuvo_button.dart` | White fill, navy border. Secondary actions. |
| `NuvoGhostButton` | `lib/core/widgets/nuvo_button.dart` | Icy-blue fill, border. Lower-emphasis lifecycle actions. |
| `NuvoDangerButton` | `lib/core/widgets/nuvo_button.dart` | Soft-red fill, red border. Destructive with confirmation. |
| `NuvoIconAction` | `lib/core/widgets/nuvo_button.dart` | White fill, 44×44 icon-only button. |
| `NuvoBackButton` | `lib/core/widgets/nuvo_button.dart` | Round pale-lavender circle, navy arrow. Back navigation. |
| `NuvoBackplateButton` | `lib/core/widgets/nuvo_button.dart` | Alias for `NuvoPrimaryButton`. |

### NuvoBackButton (added UI Polish pass)

Applied consistently across all detail/flow screens:
- `lib/features/race_detail/presentation/race_detail_screen.dart`
- `lib/features/races/presentation/ai_motion_proof_screen.dart`
- `lib/features/races/presentation/submit_proof_screen.dart`
- `lib/features/races/presentation/create_race_screen.dart`
- `lib/features/races/presentation/race_settings_screen.dart`
- `lib/features/profile/presentation/edit_profile_screen.dart`

Style: `NuvoColors.icyBlue` fill, `NuvoColors.border` stroke, `BoxShape.circle`, 44×44, `Icons.arrow_back_rounded` navy icon, subtle 2-3px navy shadow.

## Disabled By Design

| Button / action | File | Reason |
|---|---|---|
| Continue with Apple | `lib/features/auth/presentation/apple_placeholder_button.dart` | Apple auth requires future entitlements and backend support. |
| Resend code on old OTP screen | `lib/features/auth/presentation/otp_screen.dart` | Old phone OTP screen is not routed; action is disabled instead of empty. |

## Removed This Pass

| Removed fake action/data | File |
|---|---|
| Mock invite preview and fake crew cards | `lib/features/compete/presentation/compete_screen.dart` |
| Hardcoded pass crew list | `lib/features/pass/presentation/pass_screen.dart` |
| Hardcoded onboarding crew members | `lib/features/onboarding/presentation/add_crew_screen.dart` |
| Fake first-race leaderboard preview | `lib/features/onboarding/presentation/first_race_screen.dart` |
| Fake welcome/auth race preview players | `lib/features/welcome/presentation/welcome_screen.dart`, `lib/features/auth/presentation/welcome_auth_screen.dart` |
| Fake proof scanner metrics and local verified state | `lib/features/proof/presentation/proof_screen.dart`, `lib/core/widgets/proof_scanner_card.dart` |
| Fake achievements / personal profile stats | `lib/features/profile/presentation/profile_screen.dart` |
| Mock data source file | `lib/data/mock_data.dart` |
## Demo Social + AI Button Update - 2026-06-19

- Crew search uses compact Add/Added actions.
- Invite Crew uses Add to race/Added actions for search results and existing crew.
- Invite code fallback keeps Copy code and Share race CTAs.
- Create Race keeps a single primary CTA that changes between Start AI race and Start race.
- No QR scanning CTA was added.
