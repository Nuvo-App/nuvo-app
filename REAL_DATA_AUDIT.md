# Real Data Audit

_Last updated: 2026-06-19_

## Active Screens Checked
- Screen: Arena
- File: `lib/features/arena/presentation/arena_screen.dart`
- Data source currently used: `raceControllerProvider` backed by `GET /races`; auth user from `authControllerProvider`.

- Screen: Compete
- File: `lib/features/compete/presentation/compete_screen.dart`
- Data source currently used: `raceControllerProvider` backed by `GET /races`; quick starts are clearly labeled templates only.

- Screen: Race Detail
- File: `lib/features/race_detail/presentation/race_detail_screen.dart`
- Data source currently used: `GET /races/:id` through `RaceController.getRaceDetail`.

- Screen: Submit Proof
- File: `lib/features/races/presentation/submit_proof_screen.dart`
- Data source currently used: `POST /races/:id/proof` through `RaceController.submitProof`.

- Screen: AI Motion Proof
- File: `lib/features/races/presentation/ai_motion_proof_screen.dart`
- Data source currently used: local iPhone camera stream plus on-device ML Kit pose detection; verified result only is submitted to `POST /races/:id/proof` through `RaceController.submitAiMotionProof`.

- Screen: Pass
- File: `lib/features/pass/presentation/pass_screen.dart`
- Data source currently used: `GET /pass/me` through `AuthController.getMemberPass`; no crew backend exists yet.

- Screen: Profile
- File: `lib/features/profile/presentation/profile_screen.dart`
- Data source currently used: auth user from `authControllerProvider`; race stats calculated from `raceControllerProvider`.

- Screen: Onboarding Add Crew
- File: `lib/features/onboarding/presentation/add_crew_screen.dart`
- Data source currently used: no crew backend yet; uses honest empty and coming-soon states.

- Screen: Onboarding First Race
- File: `lib/features/onboarding/presentation/first_race_screen.dart`
- Data source currently used: static race templates; "Start this race" creates a real backend race with `POST /races`.

## Fake User Data Found
- Screen: Compete
- File: `lib/features/compete/presentation/compete_screen.dart`
- Fake data: mock race preview, fake crew cards, fake leaderboard players.
- Replacement plan: completed; screen now shows real user races, empty/error states, and clearly labeled quick-start templates.

- Screen: Pass
- File: `lib/features/pass/presentation/pass_screen.dart`
- Fake data: hardcoded crew list.
- Replacement plan: completed; crew area now shows an honest empty state until a real crew backend exists.

- Screen: Onboarding Add Crew
- File: `lib/features/onboarding/presentation/add_crew_screen.dart`
- Fake data: hardcoded selectable friends.
- Replacement plan: completed; screen now shows coming-soon sheets and no fake crew members.

- Screen: Onboarding First Race
- File: `lib/features/onboarding/presentation/first_race_screen.dart`
- Fake data: selected race preview with fake players.
- Replacement plan: completed; template card has no fake participants and starts a real backend race.

- Screen: Welcome/Auth Welcome
- File: `lib/features/welcome/presentation/welcome_screen.dart`, `lib/features/auth/presentation/welcome_auth_screen.dart`
- Fake data: marketing race preview with fake participants.
- Replacement plan: completed; replaced with static product loop cards.

- Screen: Legacy Proof
- File: `lib/features/proof/presentation/proof_screen.dart`, `lib/core/widgets/proof_scanner_card.dart`
- Fake data: local verified state and fake proof metrics.
- Replacement plan: completed; legacy proof screen links to the real proof form and fake scanner widget was removed.

- Screen: Profile
- File: `lib/features/profile/presentation/profile_screen.dart`
- Fake data: fake achievements and placeholder personal stats.
- Replacement plan: completed; stats now come from real race data or show loading/error/empty states.

## Static Data Kept
- Item: Race creation templates
- File: `lib/features/races/presentation/create_race_screen.dart`
- Reason it is allowed: templates are only used in create-race setup.

- Item: Onboarding first-race templates
- File: `lib/features/onboarding/presentation/first_race_screen.dart`
- Reason it is allowed: clearly labeled quick starts; selected template creates a real backend race.

- Item: Quick starts in Compete
- File: `lib/features/compete/presentation/compete_screen.dart`
- Reason it is allowed: clearly labeled suggestions, separated from "Your races".

- Item: AI Motion Proof launch target
- File: `lib/features/races/presentation/ai_motion_proof_screen.dart`
- Reason it is allowed: target is fixed to 10 jumping jacks for v1 demo and submits only real local detector output.

- Item: QR scanning / direct race links / contacts coming-soon copy
- File: `lib/features/pass/presentation/pass_screen.dart`, `lib/features/onboarding/presentation/add_crew_screen.dart`
- Reason it is allowed: explicitly labeled placeholders; no fake crew data is shown.

- Item: Apple Sign In placeholder
- File: `lib/features/auth/presentation/apple_placeholder_button.dart`
- Reason it is allowed: intentionally disabled until Apple auth support exists.

## Backend Sources Available
- Screen: Arena / Compete
- Endpoint/provider: `raceControllerProvider` -> `RaceRepository.getRaces()` -> `GET /races`.

- Screen: Race Detail
- Endpoint/provider: `RaceController.getRaceDetail(id)` -> `GET /races/:id`.

- Screen: Submit Proof
- Endpoint/provider: `RaceController.submitProof(...)` -> `POST /races/:id/proof`.

- Screen: Pass
- Endpoint/provider: `AuthController.getMemberPass()` -> `GET /pass/me`.

- Screen: Profile
- Endpoint/provider: `authControllerProvider` for user identity; `raceControllerProvider` for real race stats.

- Screen: Race Settings / Invite / Join / Proof Review
- Endpoint/provider: `PATCH /races/:id`, lifecycle race routes, invite-code routes, and `PATCH /races/:id/proofs/:proofId` through `RaceController`.

## Empty/Error States Needed
- Screen: Arena
- Empty state: "Your start line is clear. Create your first race and pull in your crew."
- Error state: retryable `NuvoErrorState`.

- Screen: Compete
- Empty state: same start-line copy with "Start a race" CTA.
- Error state: retryable `NuvoErrorState`.

- Screen: Race Detail
- Empty state: honest crew and proof copy when participants/proofs are absent.
- Error state: retryable `NuvoErrorState`.

- Screen: Pass
- Empty state: "Your crew is waiting at the start line. Invite friends to turn this into a race."
- Error state: retryable member-pass load error.

- Screen: Profile
- Empty state: race history appears once the user starts competing.
- Error state: retryable race stats load error.

## Known Placeholders
- Placeholder: Push-up AI proof
- Why it remains: jumping jacks are the primary v1 demo flow.
- Future feature needed: tune and validate a separate push-up counter before exposing it.

- Placeholder: QR scanning
- Why it remains: no QR scanner integration or crew backend exists yet.
- Future feature needed: scanner flow connected to real crew/race invites.

- Placeholder: Direct race links
- Why it remains: no direct app-opening link support in scope.
- Future feature needed: real invite codes or universal/app links.

- Placeholder: Contact invites
- Why it remains: no contacts permission/invite backend exists yet.
- Future feature needed: contact permission flow and invite backend.

- Placeholder: Apple Sign In
- Why it remains: intentionally disabled.
- Future feature needed: Apple Developer setup, entitlements, and backend endpoint.

## Race System Completion Addendum
- Race editor/settings now saves real backend race fields.
- Archive, cancel, delete, leave, join, invite-code, and proof-review actions call backend routes.
- Join race screen does not show a fake preview; it joins directly by backend invite code.
- Invite crew uses real invite codes and keeps direct app-opening links as honest coming-soon copy.
- Proof review supports manual owner review statuses; AI Motion Proof v1 stores local detector results and only auto-updates progress for `ai_verified`.
