# Nuvo QA Checklist

_Use this checklist before each release candidate. Mark items as Pass / Fail / N/A._

## Auth Flow

- [ ] Open app cold — splash screen shows briefly, then routes to Welcome or Arena correctly.
- [ ] Tap "Continue with Email" from Welcome — EmailStartScreen pushes and back button works.
- [ ] Enter valid email and tap "Send code" — navigates to EmailVerifyScreen.
- [ ] Enter incorrect OTP code — shows an error and does not show fake app data.
- [ ] Enter correct OTP code — navigates to onboarding or arena.
- [ ] Tap "Continue with Google" — Google picker opens; cancel returns to Welcome without crash.
- [ ] Authenticated user navigating to `/welcome` redirects to `/arena`.
- [ ] Unauthenticated user navigating to `/races/new`, `/race/:id`, `/race/:id/proof`, or `/profile` redirects to `/welcome`.

## Arena

- [ ] Arena loads real races from `GET /races`.
- [ ] Loading state appears while initial race list is loading.
- [ ] If the backend returns no races, Arena shows "Your start line is clear" and no fake race cards.
- [ ] If race loading fails, Arena shows retryable error state and no fake races.
- [ ] "Start a race" navigates to Create Race.
- [ ] "Invite crew" navigates to Crew tab.
- [ ] Notifications bell shows "No race updates yet" and no fake activity.
- [ ] Real race card tap opens Race Detail.
- [ ] Featured race card shows "Submit proof" when progress < 100%.
- [ ] Featured race card shows "Finished" label and green "Complete" pill when own progress ≥ 100%.

## Compete

- [ ] Compete shows Start a race, Join with code, and Quick starts only — no race list.
- [ ] Quick starts are clearly labeled suggestions.
- [ ] Quick-start tap navigates to Create Race; it does not create or show fake data by itself.
- [ ] "Start a race" opens the real Create Race flow.
- [ ] "Join with code" opens the join screen.

## Race Detail

- [ ] Race title, description, goal, participants, and recent proofs come from `GET /races/:id`.
- [ ] Race detail load failure shows retryable error state.
- [ ] If there are no participants, the crew waiting copy appears.
- [ ] If only the current user is a participant, only that user appears.
- [ ] If there are no proofs, "No proof submitted yet" appears.
- [ ] "Submit proof" opens `/race/:id/proof` when user progress < 100%.
- [ ] When user progress ≥ 100%: "Race complete" card + "Start another race" primary + "Submit more proof" ghost.
- [ ] Returning from proof submission reloads detail.
- [ ] "Share race" opens the native share sheet using the current race title.
- [ ] Race creator sees Submit proof (or complete card), Invite crew, and a lower Manage race section.
- [ ] Archive, Cancel, and Delete are only available from Race Settings / Danger Zone.
- [ ] Non-owner participant sees Submit proof (or complete card), Leave race, Share race, and Copy code.
- [ ] Non-participant preview shows Join race when direct join is allowed.
- [ ] Archive, cancel, delete, and leave all require confirmation before backend calls.

## Race Settings

- [ ] `/race/:id/settings` loads real race detail.
- [ ] `/race/:id/edit` opens the same real editor.
- [ ] Non-owner cannot edit settings.
- [ ] Basic details save through `PATCH /races/:id`.
- [ ] Goal fields save through `PATCH /races/:id`.
- [ ] Rules save through `PATCH /races/:id`.
- [ ] Proof requirement options show manual proof, photo/video coming soon, and AI Motion Proof for 10 jumping jacks.
- [ ] Proof review mode options show auto accept, owner review, and AI review coming soon.
- [ ] Visibility options show private, crew only, and invite code.
- [ ] Save returns to Race Detail with updated backend data.
- [ ] Danger zone delete soft-deletes only after confirmation.

## Invite & Join

- [ ] `/race/:id/invite` loads real race title.
- [ ] Create invite code calls `POST /races/:id/invite-code`.
- [ ] Copy code copies the backend invite code.
- [ ] Share race uses copy text: "Join my Nuvo race" and "Open Nuvo and enter code".
- [ ] Invite screen says direct race links are coming soon.
- [ ] `/races/join` accepts an invite code.
- [ ] Join by code calls `POST /races/join-code` and opens Race Detail.
- [ ] Invalid invite code shows backend error and no fake preview.

## Proof Review

- [ ] Owner review mode submits proof without claiming AI validation.
- [ ] Owner can open a proof review screen from Recent proofs.
- [ ] Proof review shows submitted by, proof value, note, and status badge.
- [ ] Accept proof calls `PATCH /races/:id/proofs/:proofId`.
- [ ] Reject proof calls `PATCH /races/:id/proofs/:proofId`.
- [ ] Needs review calls `PATCH /races/:id/proofs/:proofId`.
- [ ] Non-owner cannot review proof.
- [ ] AI statuses are present as infrastructure only; no AI validation is claimed.

## Create Race

- [ ] Templates populate title, unit, and goal amount.
- [ ] For non-Custom templates: goal + unit collapse into locked "Goal: X Y" row with "Customize" link.
- [ ] Tapping "Customize" expands the goal/unit fields.
- [ ] "Custom" template shows all fields immediately.
- [ ] Empty title disables "Start a race" or "Start AI race".
- [ ] Successful creation calls `POST /races` and navigates to the created Race Detail.
- [ ] Race list refreshes with the newly created real race.
- [ ] Back button returns to Compete or falls back safely.

## Submit Proof

- [ ] Zero or negative value shows inline error message.
- [ ] Valid value calls `POST /races/:id/proof`.
- [ ] Success state does not fake AI validation.
- [ ] AI Motion Proof opens `/race/:id/proof/ai-motion`.
- [ ] Manual proof remains available and still calls the existing proof endpoint.
- [ ] "Back to race" returns to Race Detail.
- [ ] Race Detail shows the real proof after reload.
- [ ] Legacy `/proof/:id` screen does not fake verification metrics and routes to the real proof form.

## AI Motion Proof

- [ ] Camera permission prompt appears.
- [ ] Camera opens on physical iPhone.
- [ ] Full-body guidance appears.
- [ ] Recording starts.
- [ ] Jumping jack count updates.
- [ ] Done shows verified/failed result.
- [ ] Failed recording does not submit progress.
- [ ] Verified proof submits to backend.
- [ ] Race progress updates.
- [ ] Leaderboard refreshes.
- [ ] App does not crash when backing out.
- [ ] Bad recording with no person visible fails gracefully.

## Crew Tab (was Pass)

- [ ] Bottom nav tab 2 is labelled "Crew" with a group icon.
- [ ] Pass loads member pass from `GET /pass/me`.
- [ ] Pass load failure shows retryable error state and no fake member ID.
- [ ] QR scanner button shows "QR scanning coming soon" and no fake scan result.
- [ ] Crew section shows "Your crew is waiting at the start line" and no hardcoded crew members.
- [ ] Onboarding Add Crew shows no fake friends.
- [ ] Add Crew search, QR, invite link, and contacts actions are clearly coming-soon placeholders.

## Profile

- [ ] Profile name, username, and initials come from authenticated user state.
- [ ] Active race count, finished race count, proof count, and average progress are calculated from real race data.
- [ ] If race stats are loading, a loading state appears.
- [ ] If race stats fail to load, a retryable error appears and no fake stats/history appear.
- [ ] If no races exist, race history shows honest empty copy.
- [ ] Notifications setting shows honest empty updates sheet.
- [ ] Privacy setting shows coming-soon sheet.
- [ ] Sign out clears protected state and routes back to Welcome.

## Onboarding

- [ ] Member Pass loads real pass data before showing the card.
- [ ] Member Pass load failure shows retryable error and no fallback fake ID.
- [ ] Share pass and Copy link use the real pass URL.
- [ ] First Race quick starts are clearly labeled templates.
- [ ] "Start this race" creates a real backend race and completes onboarding.
- [ ] "Explore app" completes onboarding without creating fake race data.

## Data & State

- [ ] Logout clears race data immediately.
- [ ] Login after logout loads fresh race data for the new user.
- [ ] Backend failure never falls back to mock races, fake crew, fake proof history, fake notifications, or fake stats.
- [ ] Empty backend responses show honest empty states.
- [ ] Race creation and proof submission invalidate or update race state.

## Accessibility & Polish

- [ ] Tappable elements have adequate touch targets.
- [ ] Loading spinners are centered and visible.
- [ ] Error text is visually distinct.
- [ ] Bottom sheets have drag handles and dismiss on backdrop tap.
- [ ] `trans.png` only appears on dark navy/blue backgrounds or inside dark logo containers.
- [ ] Important CTAs use Nuvo button variants, not default Flutter buttons.
- [ ] Primary race CTAs use royal-blue fill and navy offset/backplate treatment.

## UI Polish (2026-06-18 pass)

- [ ] Status bar readable on all light screens — dark icons on icy-white backgrounds
- [ ] Back button not clipped on AI Motion Proof
- [ ] Back button style consistent across detail screens — round lavender circle, navy arrow
- [ ] Race Detail opens with race header and My progress card — not an admin actions panel
- [ ] Submit proof CTA is the visually dominant first action on Race Detail
- [ ] Invite crew is secondary below Submit proof (owner only)
- [ ] Danger actions (Archive, Cancel, Delete) are in Manage race section at bottom of Race Detail
- [ ] Race title displays in title case (e.g. "Do 10 Jumping Jacks" not "do 10 jumping jacks")
- [ ] Race context line is clean (e.g. "AI Motion Proof · 10 reps")
- [ ] Status pill shows race status in Race Detail header
- [ ] My progress card appears for participants with a goal set
- [ ] Leaderboard leader row uses navy fill treatment
- [ ] Leaderboard rows show avatar initials, progress value, percentage, and bar
- [ ] Proof method shows "AI Motion Proof · Live camera · Auto verified" for jumping jack races
- [ ] Proof status badges use colour-coded pills (Verified = green, Try again = red)
- [ ] AI Motion Proof Record button labelled "Record proof" — no white dot icon
- [ ] AI verified result shows premium navy panel with large verified badge
- [ ] AI failed result shows coaching card (Try again + detected rep count)
- [ ] Submit verified proof uses NuvoPrimaryButton with navy backplate
- [ ] Compete screen has exactly one "Start a race" primary CTA
- [ ] Compete empty state has no duplicate start button
- [ ] Quick starts: "10 Jumping Jacks" is first with "AI Motion Proof · 10 reps" subtitle
- [ ] Quick start tiles have contextual icons and right arrow
- [ ] Featured quick start (10 Jumping Jacks) uses navy featured tile treatment
- [ ] Arena shows "Submit proof" on featured race card button (not "Log progress")
- [ ] Arena quick action reads "Start a race" (not "Start race")
- [ ] No button labels truncate on standard iPhone widths
- [ ] Copy code button is labelled "Copy code" (not "Copy invite code" — truncation-safe)
- [ ] No fake user data displayed anywhere
- [ ] No AI behaviour claimed for non-AI races

## Live Demo UX

- [ ] 10 Jumping Jacks quick start preserves AI metadata
- [ ] AI race shows AI Motion Proof, not manual proof
- [ ] Submit Proof shows AI as primary only for AI races
- [ ] Manual races do not misleadingly show working AI
- [ ] Camera preview is not stretched
- [ ] Debug metrics hidden in release/demo UI
- [ ] Screen does not say ready when body is not visible
- [ ] Record button not clipped
- [ ] Race Detail starts with progress/proof, not admin actions
- [ ] Danger actions moved to Settings/Danger Zone
- [ ] Back buttons consistent

## Visual System Final (2026-06-19 polish pass)

- [ ] Important cards use Nuvo custom surfaces (backplate offset shadow or compact card shadow)
- [ ] Major CTAs use navy backplate/double shadow (NuvoPrimaryButton)
- [ ] Repeated race rows use NuvoDenseRaceRow (icon badge, progress pill, AI pill, arrow)
- [ ] Arena active race rows show progress pills and Complete pill at 100%
- [ ] Arena quick action cards have offset navy backplate shadow
- [ ] Compete featured quick start (10 Jumping Jacks) uses strong navy backplate card
- [ ] Compete non-featured quick starts use compact card with subtle backplate
- [ ] Race Detail progress card has offset backplate shadow
- [ ] Race Detail sections use tighter 16px bottom spacing (not 20px)
- [ ] Race Detail Manage race uses NuvoActionTile rows (not 2×2 button grid)
- [ ] Race Detail info rows are compact (12px padding, not 14px)
- [ ] Submit Proof AI reassurance copy visible for AI races
- [ ] AI Motion Proof camera panel height ≤ 270px on standard iPhone (CTA stays on screen)
- [ ] AI Motion Proof setup state does not show duplicate status panel below camera
- [ ] AI Motion Proof setup card is compact checklist (not tall vertical list)
- [ ] Pass search field uses Nuvo card surface (not default Flutter TextField)
- [ ] Pass crew empty state is compact card row (not large centered block)
- [ ] Profile stats grid uses NuvoStatTile — childAspectRatio ≥ 2.0 (shorter cells)
- [ ] Profile race history rows use compact card with status pill
- [ ] Profile settings rows use NuvoActionTile with icon badge
- [ ] Bottom nav does not cover content (screens have correct bottom SafeArea padding)
- [ ] No fake data displayed
- [ ] AI only shown as real/active for 10 Jumping Jacks

## AI Motion Proof Camera Final (2026-06-19 camera polish pass)

- [ ] Back button top-left, not centered — inline with title in compact header row
- [ ] Camera stage is large enough for proof mode — fills remaining screen via Expanded
- [ ] Camera preview preserves aspect ratio (FittedBox cover, no stretching)
- [ ] CTA is never clipped — sticky in SafeArea bottomNavigationBar
- [ ] No huge dead space between camera stage and bottom CTA
- [ ] Full-body guide scales with camera stage height
- [ ] Status copy matches actual state: Frame body → Tracking → Full body needed → Target reached
- [ ] Recording HUD shows "Target reached — tap Done" when 10 reps detected
- [ ] Top-left pill turns green and shows "10 / 10" when target reached during recording
- [ ] Visibility pill shows "Frame body" (not "Ready") in non-recording camera-ready state
- [ ] Visibility pill shows "Tracking" (not "Ready") when body visible during recording
- [ ] Status hint panel is compact (not large card) and hidden during recording
- [ ] Verified result panel fills Expanded — centered navy card, not cramped small card
- [ ] Failed result panel fills Expanded — centered icy-blue card with coaching copy
- [ ] No debug metrics visible in demo UI
- [ ] AI detection still works — jumping jack count increments correctly on device

## Google OAuth + Welcome Screen (2026-06-19 auth pass)

### Google OAuth
- [ ] Bundle ID confirmed: `com.example.nuvo` (see `ios/Runner.xcodeproj/project.pbxproj`)
- [ ] Google iOS OAuth client created in Google Cloud Console for exact bundle ID `com.example.nuvo`
- [ ] `Info.plist` `GIDClientID` set to iOS client ID
- [ ] `Info.plist` `CFBundleURLSchemes` has reversed iOS client ID
- [ ] `GOOGLE_IOS_CLIENT_ID` Worker secret set via `wrangler secret put GOOGLE_IOS_CLIENT_ID`
- [ ] `_kGoogleEnabled = true` in `welcome_auth_screen.dart` (only after above steps done)
- [ ] Google sign-in tested on physical iPhone
- [ ] Backend `/auth/google` accepts token and returns JWT
- [ ] Broken/unconfigured Google button never visible or tappable

### Landing-Page Auth UI
- [ ] Welcome screen hero says "Compete on anything. With anyone."
- [ ] "anything." is rendered in royal blue (`NuvoColors.blue`)
- [ ] Login mode shows "Welcome back." with "back." in blue
- [ ] Product preview card is dark navy with static race preview content
- [ ] Email CTA is the primary blue button (mail icon, always first)
- [ ] Google is second (muted "needs setup" row or live button if configured)
- [ ] Terms text is always visible, never clipped
- [ ] Screen fits without ugly scrolling on standard iPhone
- [ ] No emoji, no generic SaaS language, no gradients

### Email + Verify Flow
- [ ] Email screen uses `NuvoBackButton` (not raw GestureDetector icon)
- [ ] Email screen title: "Enter your email"
- [ ] Email screen subtitle: "We'll send a sign-in code for your Nuvo race pass."
- [ ] Email `TextField` uses styled Nuvo input (white fill, border radius 16, blue focus)
- [ ] Email CTA pinned to bottom — never clipped by keyboard
- [ ] Verify screen uses `NuvoBackButton`
- [ ] Verify screen title: "Check your email"
- [ ] Verify screen subtitle shows sent-to email address
- [ ] Verify CTA label: "Verify code" (not just "Verify")
- [ ] Resend code styled as blue tappable text (not default TextButton)

## Final Demo Readiness (2026-06-19)

- [ ] Email login works end-to-end on device
- [ ] Google sign-in is safely disabled — "coming soon" muted row, not interactive
- [ ] No broken tappable Google button on welcome screen
- [ ] Welcome screen Start Line card uses Nuvo hard offset backplate shadow
- [ ] Welcome screen email CTA is the primary blue button
- [ ] Create Race title shows "Start AI race" when AI template selected
- [ ] Create Race template chips are custom navy/blue Nuvo pills (not Material ChoiceChips)
- [ ] Create Race AI proof card copy says "Nuvo verifies 10 clean jumping jacks live..."
- [ ] Demo account cleaned of stale test races before presenting
- [ ] AI Motion Proof demo path works on physical iPhone (camera → record → verify → submit)
## Demo Social + AI
- [x] User search works by username/member ID
- [x] Current user cannot add self
- [x] Add to crew works
- [x] Crew list is real data
- [x] Invite Crew can add a user to a race
- [x] Invite code still works
- [x] Added user sees race in Arena through participant race query
- [x] Added user can open Race Detail
- [x] Leaderboard includes multiple participants
- [ ] Proof submitted by one phone updates on other phone after refresh/poll
- [x] User can type "10 squats"
- [x] User can type "20 high knees"
- [x] User can type "10 arm raises"
- [x] User can type "20 second plank"
- [x] Supported movements show AI Motion Proof available
- [x] Unsupported movements stay manual
- [x] Quick starts use the same parser
- [x] Jumping jacks still works at compile/integration level
- [x] No fake AI for unsupported movements
- [x] AI proof screen labels match selected movement
- [x] Proof submits with correct activity type
- [ ] Physical two-phone flow validated
- [ ] Physical movement detection validated
