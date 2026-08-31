# Live Demo QA Audit

_Last updated: 2026-06-19 — UX simplification pass_

Use this checklist before a live demo or investor walkthrough. Focus on the critical path only.

---

## Final Live Demo

- [ ] Email login works end-to-end
- [ ] Google sign-in is safely disabled — shows "needs setup" non-interactive row
- [ ] Google row is not tappable or interactive in any way
- [ ] Welcome screen hero says "Compete on anything. With anyone." — "anything." is royal blue
- [ ] Welcome screen product preview card is dark navy with race preview content
- [ ] Welcome screen email CTA is blue primary button (mail icon, always first)
- [ ] Login mode shows "Welcome back." hero — "back." in blue
- [ ] Email entry screen uses NuvoBackButton + styled TextField + pinned CTA
- [ ] Email verify screen uses NuvoBackButton + "Check your email" title + pinned CTA
- [ ] Bottom nav tab 2 shows "Crew" (not "Pass")
- [ ] Compete shows Start a race + Join + Quick starts only — no race list
- [ ] 10 Jumping Jacks quick start is the visually dominant card on Compete
- [ ] Create Race with JJ prefill shows locked goal row ("Goal: 10 jumping jacks · Customize")
- [ ] Create Race screen shows "Start AI race" title when AI template is selected
- [ ] Create Race AI banner says "Nuvo verifies 10 clean jumping jacks live"
- [ ] Create Race template pills are custom Nuvo style (not Material ChoiceChips)
- [ ] Race Detail shows AI Motion Proof method card correctly
- [ ] Submit Proof for AI races: compact header row (Back + "AI Motion Proof" inline), card as hero, text link for manual
- [ ] Submit Proof makes AI primary for AI races
- [ ] AI Motion Proof camera UI is demo-ready (large stage, back button top-left)
- [ ] Verified proof submits and returns to Race Detail
- [ ] Leaderboard / progress updates after proof submission
- [ ] Duplicate demo races cleaned before presenting

---

## Core Flow Readiness

- [ ] App cold-starts without crash on physical iPhone
- [ ] Email login completes successfully
- [ ] Arena shows real races for the logged-in user
- [ ] Tapping a race opens Race Detail with real data
- [ ] Submit proof opens correctly for AI and manual races
- [ ] AI Motion Proof flow runs on device (10 Jumping Jacks)
- [ ] Manual proof submit succeeds and reflects on leaderboard
- [ ] Race creation flow completes and new race appears in Arena and Compete
- [ ] Compete quick start for 10 Jumping Jacks prefills Create Race correctly
- [ ] Pass card loads real member ID and QR
- [ ] Profile shows real stats (no fake numbers)
- [ ] Sign out returns to Welcome

---

## Visual System Checks

- [ ] Welcome screen Start Line card has Nuvo hard offset backplate shadow
- [ ] Welcome screen Email CTA is the primary blue button (not Google)
- [ ] Welcome screen Google row is clearly informational / muted (not interactive)
- [ ] Arena hero card has navy backplate shadow
- [ ] Arena active race rows show progress pills (AI pill, Complete pill, % pill)
- [ ] Arena quick action cards have offset shadow (not flat white boxes)
- [ ] Compete 10 Jumping Jacks quick start is visually dominant (dark navy card)
- [ ] Compete non-featured quick starts use compact card with subtle shadow
- [ ] Create Race title says "Start AI race" when AI template selected
- [ ] Create Race template chips are custom navy/blue pills (not Material ChoiceChips)
- [ ] Race Detail progress card has backplate shadow
- [ ] Race Detail sections flow without excess vertical whitespace
- [ ] Race Detail Manage race uses action tile rows (not button grid)
- [ ] Submit Proof AI card is dark navy with blue CTA and reassurance copy
- [ ] AI Motion Proof setup card is compact — CTA button visible without scrolling
- [ ] AI Motion Proof back button is top-left, inline with title — not centered
- [ ] AI Motion Proof camera stage fills available screen space (Expanded)
- [ ] AI Motion Proof CTA is never clipped — SafeArea bottomNavigationBar
- [ ] AI Motion Proof recording HUD shows "Target reached — tap Done" at 10 reps
- [ ] AI Motion Proof result panel (Verified / Try again) fills the Expanded stage area
- [ ] AI Motion Proof status hint is compact and hidden during recording
- [ ] Pass search field uses custom styled Nuvo card (not default Flutter TextField)
- [ ] Pass crew empty state is a compact card row (not a tall centered block)
- [ ] Profile stats grid is compact (shorter cells, 2-column tight layout)
- [ ] Profile settings rows use NuvoActionTile with icon badge and arrow
- [ ] Profile race history rows include status pill
- [ ] Bottom nav does not overlap screen content

---

## Anti-Regression Checks

- [ ] No fake race data displayed anywhere
- [ ] No AI validation claimed for non-AI races (only 10 Jumping Jacks)
- [ ] AI Motion Proof detection still works (jumping jacks count increments)
- [ ] Manual proof still submits and shows on leaderboard
- [ ] Race creation still works end-to-end
- [ ] Back buttons work on all detail/proof screens
- [ ] App does not crash on camera permission deny during AI proof

---

## Google Sign-In Status

**Current status: Disabled — "needs setup" non-interactive row shown**

Code is fully restored in `welcome_auth_screen.dart` behind `const _kGoogleEnabled = false`.
All layers work: `AuthApi.signInWithGoogle()`, `AuthRepository.signInWithGoogle()`, `AuthController.signInWithGoogle()`, backend `/auth/google`.

To enable, complete these two external steps (see `GOOGLE_OAUTH_FIX_PLAN.md` for exact steps):
1. Verify Google Cloud Console has an iOS OAuth client registered for bundle ID `com.example.nuvo`
2. Set `GOOGLE_IOS_CLIENT_ID` in Cloudflare Worker secrets: `wrangler secret put GOOGLE_IOS_CLIENT_ID`
3. Flip `const _kGoogleEnabled = false` → `true` in `welcome_auth_screen.dart`

Until those external steps are done, Google sign-in shows a muted "needs setup" informational row (not tappable). Email login is the primary auth path for the live demo.

---

## Demo Data Checklist

**Ideal demo-account state before presenting:**
- 0 races (fresh account) → create 10 Jumping Jacks live → submit AI proof → show 100%
- OR: exactly 1 clean 10 Jumping Jacks race, previously verified

**Pre-demo steps:**
1. Open Profile → verify your name and username look correct
2. If there are test races cluttering Arena: go to each Race Detail → Manage race → Archive or Delete
3. Sign out and sign back in to confirm session works cleanly
4. Open Compete → tap 10 Jumping Jacks → confirm prefill fills correctly
5. Place iPhone 6–8 feet away with good lighting before the demo starts

---

## Physical iPhone Status

_To be filled in during actual device test:_

- Device tested:
- iOS version:
- Build mode: release / debug
- Overall verdict: pass / fail
- Known issues:
## Demo Social + AI - 2026-06-19

- Remote D1 migration `0005_demo_social_ai.sql` applied.
- Worker deployed to `https://nuvo-api.getnuvoapp.workers.dev`.
- `/health` returned `{"ok":true,"service":"nuvo-api",...}`.
- `flutter pub get`, `npm run typecheck`, and `flutter analyze --no-fatal-infos` completed.
- Physical two-phone and live movement tests were not run in this Codex session.

## Demo Social + AI Checklist
- [x] User search works by username/member ID
- [x] Current user cannot add self
- [x] Add to crew works in backend/UI path
- [x] Crew list uses real data
- [x] Invite Crew can add a user to a race
- [x] Invite code still works
- [x] Added user should see race in Arena via existing participant `GET /races`
- [x] Added user can open Race Detail through existing detail route
- [x] Leaderboard includes multiple participants
- [ ] Proof submitted by one physical phone updates on other physical phone after refresh/poll
- [x] Supported typed movements show AI Motion Proof available
- [x] Unsupported movements stay manual
- [x] Proof submits with correct activity type
