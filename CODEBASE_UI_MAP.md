# Nuvo Codebase UI Map

Generated from a static repo read on 2026-06-19. This map reflects the current app, not older stale notes.

## App Architecture
- Router: `lib/app/router.dart` uses `GoRouter` with `/splash`, `/welcome`, email auth, onboarding, shell tabs, race detail, race settings, invite, join, proof, AI proof, proof review, and profile edit routes.
- State management: `flutter_riverpod`. Auth is held by `authControllerProvider`; races are held by `raceControllerProvider`.
- Auth flow: `WelcomeAuthScreen` supports Google and email. Email goes through `/auth/email/start` and `/auth/email/verify`; tokens are stored through `SecureTokenStore`; `AuthGate` redirects protected routes.
- Race flow: `CompeteScreen` and `ArenaScreen` read `raceControllerProvider`; `CreateRaceScreen` calls `RaceController.createRace`; `RaceDetailScreen` loads `GET /races/:id`.
- Proof flow: `SubmitProofScreen` posts manual proof through `RaceController.submitProof`; race detail reloads after proof submission.
- AI Motion Proof flow: `AiMotionProofScreen` opens the camera, runs ML Kit pose detection, counts jumping jacks locally, and submits verified `ai_motion` proof through `RaceController.submitAiMotionProof`.
- Backend API integration: Flutter talks directly to `https://nuvo-api.getnuvoapp.workers.dev` by default, overrideable with `NUVO_API_BASE_URL`. The backend is a Cloudflare Worker with Hono, D1, email auth, Google auth, profile, pass, races, proof review, and AI proof metadata routes.

## Key UI Files
- App shell: `lib/features/shell/presentation/main_shell.dart`, `lib/core/widgets/bottom_nav.dart`.
- Core widgets: `lib/core/widgets/nuvo_button.dart`, `nuvo_empty_state.dart`, `nuvo_error_state.dart`, `member_pass_card.dart`, `pressable_scale.dart`, `nuvo_progress_bar.dart`, `nuvo_chip.dart`.
- Buttons: `NuvoPrimaryButton`, `NuvoOutlineButton`, `NuvoGhostButton`, `NuvoDangerButton`, `NuvoIconAction`, `NuvoBackButton`.
- Cards: `MemberPassCard`, local card containers in Arena, Race Detail, AI Motion Proof, Profile, Pass, and onboarding screens.
- Empty/error/loading states: `NuvoEmptyState`, `NuvoErrorState`, inline `CircularProgressIndicator` states, and bottom sheets for honest coming-soon actions.
- Navigation helpers: `safePopOrGo(context, fallback)` prevents empty-stack back crashes.

## Feature Screens

### Auth
- Files: `welcome_auth_screen.dart`, `email_start_screen.dart`, `email_verify_screen.dart`, `auth_controller.dart`, `auth_gate.dart`, `auth_api.dart`, `auth_repository.dart`, `secure_token_store.dart`.
- Current state: Real email auth and Google auth are wired. The welcome screen uses a dark logo container correctly. Back buttons in email screens are plain icons, not the final `NuvoBackButton` style. Email validation is minimal but adequate for demo.

### Onboarding
- Files: `create_identity_screen.dart`, `onboarding_screen.dart`, `member_pass_screen.dart`, `add_crew_screen.dart`, `first_race_screen.dart`, `secure_account_screen.dart`.
- Current state: Profile creation and member pass are backend-backed. Crew is an honest coming-soon state. First race creates a real race, but its templates are still generic and manual; the first option is not `10 Jumping Jacks` and it does not create an AI Motion Proof race.

### Arena
- Files: `arena_screen.dart`.
- Current state: Shows greeting, real race data, featured race, quick actions, and honest empty/error states. "Submit proof" language is correct. Notifications are an honest bottom sheet. Header icon uses default filled tonal styling, so it is slightly outside the Nuvo button system.

### Compete
- Files: `compete_screen.dart`.
- Current state: Real race list, retryable error state, no duplicate empty-state CTA. Top quick start is `10 Jumping Jacks` with `AI Motion Proof · 10 reps`, but tapping it only opens the generic create-race form and does not pass the selected template or AI proof mode.

### Race Detail
- Files: `race_detail_screen.dart`.
- Current state: Current hierarchy is much closer to the target: back/status, title/context, my progress, submit proof/join/invite, leaderboard, proof method, recent proofs, rules, manage race. Danger actions still appear at the bottom of Race Detail as chips; they are not fully isolated in Settings/Danger Zone.

### Submit Proof
- Files: `submit_proof_screen.dart`.
- Current state: Manual proof is real. AI Motion Proof card is prominent and routes to the AI camera flow. Risk: the AI card appears for every race instead of only AI Motion races, so manual races can look AI-backed. Back buttons still use `IconButton.filledTonal`.

### AI Motion Proof
- Files: `ai_motion_proof_screen.dart`, `jumping_jack_counter.dart`, `pose_detector_service.dart`, `camera_image_converter.dart`, `ai_motion_models.dart`.
- Current state: Real camera and on-device ML Kit flow exists. It has setup, camera ready, recording, processing, verified, failed, and submit states. Debug metrics are behind `kDebugMode`. Major UX gap: `Record proof` is enabled when the body is not visible; there is no clear full-body guide overlay; the preferred camera is front-facing even though the demo requirement prefers back camera if possible.

### Profile / Pass
- Files: `profile_screen.dart`, `edit_profile_screen.dart`, `pass_screen.dart`, `member_pass_card.dart`.
- Current state: Profile uses real auth user and race stats. Pass uses real `/pass/me`. Crew remains an honest empty state. `trans.png` is used on dark navy pass/logo containers, which follows the logo rule.

## Design System Findings
- Colors: Icy-white page, deep navy text/cards, royal-blue CTAs, muted blue-gray body text, green success, red danger. This matches the Arena Card System direction.
- Typography: Inter via `AppTextStyles`, consistent weights and sizes. Some screens still use all-caps labels and plain Material form fields.
- Buttons: Core button system is strong, but inconsistent back buttons remain and some tiny actions use raw `GestureDetector`/`InkWell`.
- Cards: Cards use large rounded rectangles and navy/blue backplates. Race Detail and AI proof use the system well; Create Race and settings feel more generic form UI.
- Spacing: Most screens use 20px horizontal padding. Sticky bottom CTAs exist in auth, create race, submit proof, and onboarding. AI Motion Proof actions are in the scroll body, so bottom safety depends on scroll height.
- Shadows/backplates: Primary buttons and featured cards use the navy offset effect. The hierarchy needs restraint: not every small link/action should get a heavy backplate.

## Known Risk Areas
- Camera preview: The preview is inside `AspectRatio(3 / 4)`, which avoids a fully arbitrary stretch, but it does not explicitly fit/crop the sensor aspect ratio or guide full-body framing.
- SafeArea: Most screens use `SafeArea`; bottom CTAs are generally padded. AI actions are scroll content, not pinned, and should be checked on a real iPhone.
- Back navigation: `safePopOrGo` exists, but multiple screens still use default `IconButton.filledTonal` or plain icons instead of `NuvoBackButton`.
- Data refresh: `RaceController` clears races on logout and reloads on auth transition. Detail screens reload after proof submission in some paths.
- Fake data risk: Active UI no longer imports `mock_data`. Static templates remain, but they are setup suggestions. The main remaining risk is not fake data; it is misleading AI availability on manual races.
