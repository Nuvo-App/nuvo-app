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
- [ ] "Pull crew" navigates to Pass.
- [ ] Notifications bell shows "No race updates yet" and no fake activity.
- [ ] Real race card tap opens Race Detail.

## Compete

- [ ] Compete shows real user races from `GET /races`.
- [ ] If no races exist, Compete shows the clear start-line empty state.
- [ ] If race loading fails, Compete shows retryable error state and no fake race cards.
- [ ] Quick starts are clearly labeled suggestions and are separated from "Your races".
- [ ] Quick-start tap navigates to Create Race; it does not create or show fake data by itself.
- [ ] "Start a race" opens the real Create Race flow.

## Race Detail

- [ ] Race title, description, goal, participants, and recent proofs come from `GET /races/:id`.
- [ ] Race detail load failure shows retryable error state.
- [ ] If there are no participants, the crew waiting copy appears.
- [ ] If only the current user is a participant, only that user appears.
- [ ] If there are no proofs, "No proof submitted yet" appears.
- [ ] "Submit proof" opens `/race/:id/proof`.
- [ ] Returning from proof submission reloads detail.
- [ ] "Share race" opens the native share sheet using the current race title.
- [ ] Race creator sees Edit race, Race settings, Invite crew, Share race, Copy invite code, Archive, Cancel, and Delete.
- [ ] Non-owner participant sees Submit proof, Leave race, Share race, and Copy invite code.
- [ ] Non-participant preview shows Join race when direct join is allowed.
- [ ] Archive, cancel, delete, and leave all require confirmation before backend calls.

## Race Settings

- [ ] `/race/:id/settings` loads real race detail.
- [ ] `/race/:id/edit` opens the same real editor.
- [ ] Non-owner cannot edit settings.
- [ ] Basic details save through `PATCH /races/:id`.
- [ ] Goal fields save through `PATCH /races/:id`.
- [ ] Rules save through `PATCH /races/:id`.
- [ ] Proof requirement options show manual proof, photo/video coming soon, and AI proof check coming soon.
- [ ] Proof review mode options show auto accept, owner review, and AI review coming soon.
- [ ] Visibility options show private, crew only, and invite code.
- [ ] Save returns to Race Detail with updated backend data.
- [ ] Danger zone delete soft-deletes only after confirmation.

## Invite & Join

- [ ] `/race/:id/invite` loads real race title.
- [ ] Create invite code calls `POST /races/:id/invite-code`.
- [ ] Copy invite code copies the backend code.
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
- [ ] "Custom" template clears fields.
- [ ] Empty title disables "Start race".
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

## Pass & Crew

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
