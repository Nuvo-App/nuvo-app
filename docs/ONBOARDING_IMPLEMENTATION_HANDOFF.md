# Nuvo Onboarding Implementation Handoff

This is a repository-specific handoff for a future onboarding implementation.
It records the current runtime architecture as implemented in the codebase as
of 2026-09-21. It is not an implementation plan that has already been applied,
and it is not permission to refactor unrelated systems.

The most important distinction for the next agent is that Nuvo currently has
two different onboarding-shaped flows:

1. `/welcome/intro` is a pre-auth, six-page race-builder/demo explanation.
2. `/onboarding/profile` and `/onboarding/member-pass` are post-auth account
   setup screens.

The planned redesign described at the end of this document is intended to
replace the first flow and finish at authentication. It should not silently
replace the post-auth profile/pass setup unless that is explicitly decided.

## Current first-launch flow

### Exact runtime path

```text
main()
  → WidgetsFlutterBinding.ensureInitialized()
  → portrait-only orientation + AppTheme system UI overlay
  → ProviderScope
  → NuvoApp
  → routerProvider creates GoRouter + RouterNotifier
  → initialLocation = /splash
       (unless a DEBUG-only NUVO_INITIAL_LOCATION dart define is present)
  → AuthController starts in AuthStatus.loading
  → AuthController._init()
  → AuthRepository.restoreSession()
       → SecureTokenStore reads nuvo_refresh_token
       → no token: RestoreNoSession
       → valid token + reachable API: refresh token, get /me, RestoreOk(user)
       → stored token + unreachable API: RestoreUnreachable
  → SplashScreen plays the 91-frame splash sequence and 900ms settle
  → after auth resolves and the splash is complete, SplashScreen chooses:
       → offline stored session: /arena
       → no session: /welcome/intro
       → demo/replay account: /welcome/intro
       → normal restored user: /arena
  → RouterNotifier re-evaluates on AuthState changes
  → protected shell entry is MainShell
       → /arena, /compete, /move, /pass, /profile
```

The app entrypoint is [`lib/main.dart`](../lib/main.dart). App construction,
router creation, deep-link/push startup, text scaling, keyboard dismissal, and
the web phone-column preview are in
[`lib/app/app.dart`](../lib/app/app.dart). Route registration is in
[`lib/app/router.dart`](../lib/app/router.dart).

### Guard behavior today

`RouterNotifier.redirect` in
[`lib/features/auth/presentation/auth_gate.dart`](../lib/features/auth/presentation/auth_gate.dart)
is the route guard. Its actual rules are:

- While `AuthStatus.loading`, protected locations redirect to `/splash`.
- While `AuthStatus.offline`, `/arena` and `/splash` remain reachable; other
  protected locations redirect to `/arena`.
- `AuthStatus.unauthenticated` redirects protected locations to `/welcome`.
- An authenticated user whose `AuthUser.onboardingComplete` is `false` is
  redirected to `/onboarding/profile` only when the current location is
  `/welcome`, an `/auth/*` route, or `/welcome/intro`.
- The same incomplete authenticated user is currently allowed to remain on a
  non-auth protected route such as `/arena`, because that branch returns
  `null`. This is a real current behavior and means the splash-to-`/arena`
  path does not globally enforce post-auth onboarding.
- An authenticated user whose `onboardingComplete` is `true` is sent from
  auth/onboarding/intro locations to `/arena`, or to `/compete` when
  `guideFirstRace` is true.
- Demo replay deliberately keeps the user in `/welcome/intro` and `/welcome`.

Do not assume that “new user always lands on profile setup” is already a
guaranteed invariant. The current guard only guarantees that redirect for the
specific pre-auth/onboarding locations above.

### Case-by-case behavior

| Situation | Current result |
|---|---|
| Brand-new install, no stored refresh token | Splash completes, then `/welcome/intro`. |
| Returning signed-out user | Same as no session: `/welcome/intro` after splash; direct protected deep links redirect to `/welcome`. |
| Returning signed-in, completed user | Session restores, splash hands off to `/arena`; shell is available. |
| Returning signed-in, incomplete user | Splash currently hands off to `/arena`; the guard does not redirect from `/arena`, so profile setup is not globally enforced. If the user is on `/welcome`, `/welcome/intro`, or `/auth/*`, the guard sends them to `/onboarding/profile`. |
| Demo/replay account | Splash goes to `/welcome/intro`; `demoReplayProvider` and `firstRaceGuideProvider` control the replay/coach flow. |
| Sign out | `AuthController.logout()` clears secure tokens and publishes unauthenticated state. The guard sends the protected current location to `/welcome`. |
| Account switch | There is no separate account-switch flow. A new auth result replaces the in-memory `AuthState`; server-owned user fields come from the new account. In-memory onboarding builder state is not explicitly reset on logout. |

### Auth and onboarding ordering

The current product flow is mixed:

- The cinematic/race explanation at `/welcome/intro` happens before auth.
- The email/Google/Apple authentication screen is `/welcome`.
- Profile setup and member pass happen after auth, because both call
  authenticated repository methods.

So the current implementation is not a single “all onboarding before auth” or
“all onboarding after auth” flow. The planned redesign should end at `/welcome`
and leave the existing auth and post-auth account setup contract explicit.

## Onboarding persistence

### What is persisted

There is no local onboarding-completion key. The authoritative completion field
is `AuthUser.onboardingComplete`, read from the authenticated backend `/me`
response in [`lib/features/auth/data/auth_models.dart`](../lib/features/auth/data/auth_models.dart).

The existing write API is present:

```text
AuthController.completeOnboarding()
  → AuthRepository.completeOnboarding()
  → AuthApi.completeOnboarding()
  → POST /onboarding/complete
  → AuthController refreshes /me
```

Those symbols are in:

- [`lib/features/auth/presentation/auth_controller.dart`](../lib/features/auth/presentation/auth_controller.dart)
- [`lib/features/auth/data/auth_repository.dart`](../lib/features/auth/data/auth_repository.dart)
- [`lib/features/auth/data/auth_api.dart`](../lib/features/auth/data/auth_api.dart)

As currently wired, `OnboardingMemberPassScreen`’s `Continue` button calls
`context.go('/arena')` directly. It does not call
`AuthController.completeOnboarding()`. This means the completion endpoint is
available but is not currently reached by the visible member-pass CTA. Do not
silently “fix” this in a visual onboarding redesign; treat it as a separate
auth/onboarding persistence decision and regression-test it if changed.

### Storage mechanisms and keys

`SecureTokenStore` in
[`lib/features/auth/data/secure_token_store.dart`](../lib/features/auth/data/secure_token_store.dart)
stores only:

- `nuvo_access_token`
- `nuvo_refresh_token`

Native uses `flutter_secure_storage`; web uses local storage through the
platform-specific `_ls_web.dart`/`_ls_stub.dart` adapter. There is no
`shared_preferences` onboarding flag.

The following are process-memory Riverpod state, not durable persistence:

- `welcomeOnboardingStateProvider` in
  [`lib/features/auth/presentation/welcome_onboarding_state.dart`](../lib/features/auth/presentation/welcome_onboarding_state.dart)
- `firstRaceGuideProvider` in
  [`lib/features/onboarding/presentation/first_use_guide.dart`](../lib/features/onboarding/presentation/first_use_guide.dart)
- `demoReplayProvider` in the same file

`WelcomeOnboardingState` holds selected intent, fitness goal, activity option,
proof type, target, and custom title only for the current provider lifetime.
It is not account-scoped and is lost on process restart. The notifier has a
`reset()` method, but the normal logout/account-switch path does not call it.

### Sign-out, reset, and leakage implications

- Sign-out clears the two token keys only; it does not clear the in-memory
  welcome builder state, first-race guide state, or demo replay flag by itself.
- Profile’s demo replay action sets `demoReplayProvider = true`, sets the first
  guide step, and routes to `/splash`.
- The special demo/reviewer email behavior is handled by
  `isNuvoStoreDemoEmail()` and splash logic, not by a persisted onboarding
  flag.
- Server completion is per account because it is returned in `AuthUser`; the
  local builder selections are effectively per app process.
- A redesigned pre-auth flow should not store account data locally unless the
  account ownership and reset behavior are made explicit. If selected race
  content needs to survive auth, use the existing in-memory provider or an
  intentional backend flow rather than inventing a second persistence system.

## Current onboarding implementation

### Runtime-affecting file map

| File | Class / symbol | Role | Safe to replace? | Important dependencies |
|---|---|---|---|---|
| `lib/features/auth/presentation/welcome_race_builder_screen.dart` | `WelcomeRaceBuilderScreen` | Pre-auth six-page race explanation and builder/demo flow at `/welcome/intro`. | The page composition and local visual animation are the primary replaceable onboarding surface. Preserve auth handoff/state contract unless deliberately changing it. | GoRouter, Riverpod, `welcomeOnboardingStateProvider`, `NuvoPrimaryButton`, custom painters, `PageController`. |
| `lib/features/auth/presentation/welcome_onboarding_state.dart` | `WelcomeOnboardingState`, `WelcomeOnboardingStateNotifier` | In-memory selections used by the legacy race-builder flow and auth preview. | Replace carefully; changing fields can affect `WelcomeAuthScreen` and race-builder logic. | `MotionActivityType`, `RaceBuilderOption`, Riverpod. |
| `lib/features/auth/presentation/welcome_auth_screen.dart` | `WelcomeAuthScreen` | Pre-auth auth choice screen at `/welcome`; supports email, Apple, Google, demo continuation, and legal links. | Visual hero/layout can change. Keep provider calls, auth routes, and guard assumptions intact. | AuthController, Google/Apple SDKs, `welcomeOnboardingStateProvider`, `Nuvo` buttons/cards. |
| `lib/features/auth/presentation/email_start_screen.dart` | `EmailStartScreen` | Email entry and reviewer password path at `/auth/email`. | Do not replace casually; it is the existing auth surface. | AuthController, `NuvoTextInput`, `NuvoPrimaryButton`. |
| `lib/features/auth/presentation/email_verify_screen.dart` | `EmailVerifyScreen` | Six-digit OTP verification at `/auth/verify`. | Do not replace casually. | AuthController, `OtpInput`, route `extra` email. |
| `lib/features/onboarding/presentation/onboarding_screen.dart` | `OnboardingScreen` | Post-auth profile setup at `/onboarding/profile`: terms, full name, username, privacy preference. | It is account setup, not the pre-auth cinematic. Replace only with explicit scope. | AuthController, username check, `NuvoTextInput`, legal URLs. |
| `lib/features/onboarding/presentation/member_pass_screen.dart` | `OnboardingMemberPassScreen` | Post-auth member pass fetch/share/copy and final Continue CTA. | Treat as account/pass setup, not a disposable intro page. | AuthController, `/pass/me`, `MemberPassCard`, share/clipboard. |
| `lib/features/onboarding/presentation/first_use_guide.dart` | `FirstRaceGuideStep`, `FirstRaceGuideCoach`, keys/providers | In-session coach marks after sign-in for first race creation and race detail. | Keep unless the separate tutorial is intentionally redesigned. | Riverpod, `GlobalKey`, `AnimationController`, composer/race screens. |
| `lib/features/splash/presentation/splash_screen.dart` | `SplashScreen` | Launch image-frame sequence, settle animation, auth-aware handoff. | Do not replace as part of a page-only redesign without checking launch routing and tests. | `AssetPaths`, AuthController, `demoReplayProvider`, GoRouter. |
| `lib/features/auth/presentation/auth_controller.dart` | `AuthController`, `AuthState` | Session restore, auth providers, profile setup, completion, logout/delete. | Do not touch casually. | AuthRepository, secure token store, RouterNotifier. |
| `lib/features/auth/presentation/auth_gate.dart` | `RouterNotifier` | Redirect/guard logic and first-race routing. | Do not touch casually. | GoRouter, AuthState, first-use providers. |
| `lib/app/router.dart` | `routerProvider`, route table | Route registration and page transition builders. | Only change with navigation-map review and routing tests. | GoRouter, MainShell, auth/onboarding screens. |

### Current pre-auth page sequence

`WelcomeRaceBuilderScreen` has `_pageCount = 6` and keeps the page body in a
`PageView`:

| Page | Widget | Current purpose/copy | Main visual | CTA / next |
|---:|---|---|---|---|
| 0 | `_WelcomePage` | Cinematic introduction: “Your goals are now competition.” | `_ImmersiveRacePainter` draws a moving dot/path and finish marker, then `_TypedWelcomeExplanation` reveals copy. | “See how it works”; after a 2.4s readiness delay. |
| 1 | `_LeaderboardPage` | Shows board movement and “Every rep changes your position.” | `_LeaderboardVisual` with three custom `_RankRow`s. | “Keep going”. |
| 2 | `_ProofPage` | “Move real. Count real.” / “Nuvo checks the movement before it moves the board.” | `_ProofVisual`, a custom painted proof runner in a dark card. | “See the board move”. |
| 3 | `_BoardMovePage` | “Proof turns effort into progress.” | `_ProofFlowVisual`: submit proof → AI checks it → board moves. | “Choose my direction”. |
| 4 | `_GoalPage` | “What do you want to train for?” | `FitnessGoal` selector chips and a small race path. | “Practice the move”. |
| 5 | `_PracticePage` | “See how your move becomes proof.” | `_PracticePosePainter` and a three-rep practice progress display. | “Practice the move”; after completion, “Create my first race” routes to `/welcome`. |

The current first page hides onboarding chrome during the early cinematic. The
header/footer appear after the scene is almost complete and a readiness timer
has fired. Later pages show `_OnboardingHeader` and `_OnboardingFooter`, which
include the wordmark, back/skip behavior, page dots, and one full-width primary
button.

### Post-auth sequence

`OnboardingScreen` at `/onboarding/profile` currently:

- reads the authenticated user from `AuthController`;
- collects full name and username;
- debounces username availability checks by 650ms;
- collects a private-stats preference;
- requires Terms of Service acceptance;
- calls `acceptTerms()` and `saveProfile()`;
- routes to `/onboarding/member-pass` on success;
- uses a pinned `NuvoPrimaryButton` CTA and a scrollable body;
- has a three-segment progress line where profile is the second step.

`OnboardingMemberPassScreen` then fetches `/pass/me`, displays
`MemberPassCard`, supports Share pass and Copy link, and routes to `/arena` on
Continue. It has loading/error states, but does not currently invoke
`completeOnboarding()`.

## Opening path / drawing animation

There are two related but different path implementations. Do not confuse them.

### Current cinematic opening path

The current pre-auth cinematic lives inside
[`lib/features/auth/presentation/welcome_race_builder_screen.dart`](../lib/features/auth/presentation/welcome_race_builder_screen.dart):

- `_sceneController`: `AnimationController`, 18,000ms, calls `forward()` once.
- `_ambientController`: 3,600ms, repeats continuously while the page is
  mounted.
- `_ImmersiveRacePainter`: uses the scene progress and is visible only during
  the opening page’s early phase.
- `_racePath(Size)`: a fixed normalized cubic path from roughly `(5%, 82%)`
  through controls near `(25%, 6%)` and `(62%, 98%)` to `(78%, 14%)`.
- The painter morphs a central dot into the route, draws the route with a
  19px navy outer stroke and 8px blue inner stroke, and applies rounded caps.
- The dot starts with a large 76px-to-12px zoomed radius, settles to roughly
  10–12px, and has a blue glow with a 28px blur.
- Route timing: initial dot zoom, route reveal, finish-flag reveal, then the
  typed explanation at roughly 12.5–18 seconds.
- `_drawNuvoFlag` draws a separate rounded blue pennant with navy outline and
  a navy pole. It is anchored just beyond the route endpoint.
- `_TypedWelcomeExplanation` reveals “Your goals / are now / competition.”
  followed by “Set a finish line, pull in your crew, and make every move
  visible.”

The path is coupled to `_WelcomePage.sceneProgress`, not to a reusable path
controller. The parent resets `_sceneController` with `forward(from: 0)` when
the PageView changes. The opening controller, ambient controller, page
controller, and practice controller are disposed in `dispose()`.

Current responsive assumption: `compact = constraints.maxHeight < 720`; the
page changes typography and spacing based on this boolean. The painter itself
uses percentages of the available canvas, which is safer than fixed screen
coordinates, but the surrounding layout still has fixed heights and padding.

There is no explicit reduced-motion branch in this onboarding implementation.
The current motion continues unless the future implementation adds a check for
`MediaQuery.disableAnimationsOf(context)`.

### Reusable production race path

[`lib/core/widgets/nuvo_race_path.dart`](../lib/core/widgets/nuvo_race_path.dart)
contains `NuvoRacePath` and `_RacePathPainter` for production race cards. It
is not the same cinematic sequence:

- `NuvoRacePathVariant.hero`, `compact`, and `mini` use heights 42, 30, and 16.
- Track strokes are 16, 8, and 3px; progress strokes are 10, 5, and 3px.
- The path shape is deterministic from a race ID using an FNV-1a seed; it does
  not change randomly between rebuilds.
- Progress uses `TweenAnimationBuilder`, 700ms, `Curves.easeOutCubic`.
- The marker follows `PathMetric`; completion changes the marker/progress to
  the semantic green color.
- Hero/compact variants draw a small finish flag; mini intentionally omits it.

The active Arena hero uses `NuvoRacePath` in
[`lib/features/arena/presentation/arena_screen_fixed.dart`](../lib/features/arena/presentation/arena_screen_fixed.dart).
`RaceHero`/`NuvoFeaturedRaceCard` uses the compact version when it has a stable
race ID. A future onboarding opening can preserve the cinematic concept, but
should not import the private painter or assume `NuvoRacePath` provides the
same opening choreography. Extracting the cinematic painter into a public
widget would be a deliberate, isolated change; it is not done here.

## Motion preview / Rive system

The working Rive system is for decorative pre-verification guidance. It is not
the camera verifier, does not affect rep acceptance, and should be embedded
without changing the AI Motion Proof path.

### Simplest safe embedding

The simplest existing standalone embedding is:

```dart
RiveMovementPreview(
  movement: MotionActivityType.jumpingJacks,
  fallback: const SizedBox.shrink(),
)
```

For an existing call site that only needs jumping jacks, the compatibility
wrapper is:

```dart
RiveJumpingJackPreview(fallback: fallbackWidget)
```

Place it inside a bounded `SizedBox`/`ConstrainedBox`. The current pre-verify
caller gives the widget a 300px height in
[`lib/features/races/presentation/submit_proof_screen.dart`](../lib/features/races/presentation/submit_proof_screen.dart).
Do not place it in an unconstrained `Expanded`/`Stack` and expect the Rive
viewbox to self-size.

### Files and APIs

| File | Symbol | Responsibility |
|---|---|---|
| `lib/features/races/presentation/widgets/rive_movement_preview.dart` | `RiveMovementPreview`, `RiveJumpingJackPreview` | Loads the correct asset, selects the artboard/state machine, binds data, runs a normalized sequence, applies framing, and falls back safely. |
| `lib/features/races/presentation/movement_preview/rive_pose_frame.dart` | `RivePoseFrame` | Typed front-view pose values, interpolation, finite/positive validation. |
| `lib/features/races/presentation/movement_preview/rive_pose_controller.dart` | `RivePoseController` | Caches front View Model number properties and writes poses. |
| `lib/features/races/presentation/movement_preview/nuvo_rive_rig_calibration.dart` | `NuvoRiveRigCalibration` | Holds raw defaults and the empirically visible standing pose. |
| `lib/features/races/presentation/movement_preview/rive_movement_sequences.dart` | `RiveMovementSequence`, front sequences | Routes movement types to normalized pose sequences. |
| `lib/features/races/presentation/movement_preview/jumping_jack_preview_sequence.dart` | `JumpingJackPreviewSequence` | Samples the measured jumping-jack channels and interpolates closed/open pose controls. |
| `lib/features/races/presentation/movement_preview/jumping_jack_human_motion_profile.dart` | `JumpingJackHumanMotionProfile` | 17-sample normalized arm/elbow/leg/root profile derived from read-only R2 motion-session artifacts; cycle duration is 1,000ms. |
| `lib/features/races/presentation/movement_preview/side_rig_treadmill_preview.dart` | `SideRigPose`, `SideRigPoseController`, `TreadmillRunningSideSequence` | Side-view contract, root initialization, and treadmill gait. |
| `lib/features/races/presentation/movement_preview/side_rig_movement_sequences.dart` | side movement profiles | Side-view sequences for movements without a dedicated front-view profile. |
| `lib/features/races/presentation/movement_preview/nuvo_motion_viewport.dart` | viewport helpers | Existing motion-preview framing helper; inspect before making a second viewport wrapper. |

The package is `rive: ^0.14.11` in `pubspec.yaml`. Existing code uses
`FileLoader.fromAsset`, `RiveWidgetBuilder`, `RiveWidget`, `Fit.contain`,
`Alignment.center`, `ArtboardNamed`, `StateMachineNamed`, and
`DataBind.auto()`.

### Front-view Rive asset contract

- Asset: `assets/animations/preverify/nuvo_stickman.riv`.
- Artboard: `nuvo stickman elite`.
- State machine: `Nuvo pose`.
- View Model: `NuvoPoseModel`.
- The inspection test confirms one state machine, 18 View Model properties,
  and a default instance.
- Required controls are `torsoAngle`, eight shoulder/elbow/hip/knee angle
  properties, eight upper/lower arm/leg scale properties, and `torsoScaleY`.
- `RivePoseFrame` uses degrees for angle values and the asset’s normalized
  scale input space where `100` is authored neutral. A raw scale default of
  `0` collapses the visible limb; the controller writes neutral scales before
  the first useful frame paints.

The calibrated visible standing frame in
`NuvoRiveRigCalibration.standing` is:

```text
torsoAngle       -90
left shoulder    -180       right shoulder  180
left elbow          0       right elbow       0
left hip         -180       right hip       180
left knee           0       right knee        0
all arm/leg scales 100       torsoScaleY     100
```

The raw exported defaults are intentionally different and include zero scale
inputs. Do not remove the initialization write or change the neutral frame
while embedding the preview.

### Side-view Rive asset contract

- Asset: `assets/animations/preverify/nuvo_stickman_side.riv`.
- Artboard: `Nuvo stickman side`.
- State machine: `Nuvo State machine`.
- View Model: `NuvoAngledataset`.
- Required articulated properties are torso angle, front/back shoulder and
  elbow angles, front/back hip and knee angles, front/back upper/lower arm and
  leg scales, and `torsoScaleY`.
- `rootX` and `rootY` are also present and are initialized once to
  `244.5` and `277.0` by `SideRigPoseController` because their raw binding
  defaults are zero.
- Side scale neutral is `100`; side view uses the same degree convention.

The widget selects the side asset for `treadmillRunning` and for the set in
`sideRigMovementPreviewActivities` (pushups, squats, high knees, plank, many
side/lower-body movements, and others). The front-view set currently includes
jumping jacks, lunges, arm raises, running in place, treadmill running as a
route entry, and marching in place, but the widget’s treadmill branch uses the
side rig.

### Loading, binding, lifecycle, and framing

`RiveMovementPreviewState.initState()` creates the sequence, `FileLoader`,
`DataBind.auto()`, and one `AnimationController` with the sequence duration.
It does not load the file or look up View Model handles per frame.

`RiveWidgetBuilder` receives `onLoaded`:

1. It obtains `state.viewModelInstance`.
2. It creates `RivePoseController` or `SideRigPoseController`.
3. It verifies required properties.
4. It writes the initial neutral/current frame so zero binding defaults cannot
   make the character invisible.
5. It stores the Rive controller and starts or statically poses the animation.

The render path is a real `RiveWidget` returned from the loaded builder state.
The builder uses `Fit.contain` and centered alignment. The outer widget applies
`ClipRect`, a centered transform, scale `1.35`, and a presentation offset:

- front: `x = -12`, `y = -44 + rootYOffset`;
- side: `x = 0`, `y = -16 + rootYOffset`.

These offsets are part of the currently working visual framing. Onboarding
should reuse the widget rather than adding another transform unless the new
bounded slot demonstrably requires a separate, documented viewport.

On `MediaQuery.disableAnimationsOf(context)`, the controller stops and applies
the representative normalized-time `.5` pose. Otherwise it repeats. `dispose`
removes the animation listener, disposes the animation controller, and disposes
the `FileLoader`. The Rive file/controller handles are cached for the widget
lifetime.

The fallback is the caller-provided widget when Rive fails, the View Model is
missing, or required controls are missing. Loading shows a 300×300 progress
indicator. Development diagnostics identify movement, artboard, View Model,
bound property count, and missing properties.

### Movement configuration

The front sequence router in `rive_movement_sequences.dart` currently defines:

- jumping jacks: measured motion profile, 1,000ms cycle;
- lunges: standing → right lunge → standing → left lunge → standing, 2,200ms;
- arm raises: standing → raised → standing, 1,800ms;
- running in place: alternating gait, 900ms;
- marching in place: alternating gait, 1,250ms.

The side treadmill sequence is 1,000ms and uses seven static phases with
opposite front/back shoulder and elbow signs. That sign choice is intentional:
the side rig’s mirrored chains otherwise make both forearms fold the same way.

All sequences consume normalized time and loop through one animation controller.
The preview is illustrative only; movement validation still happens in
`AiMotionProofScreen` and the AI verifier.

### Simplest onboarding use

Use `RiveMovementPreview` directly on the future “do the activity” page with
`MotionActivityType.jumpingJacks`, a bounded height, and a safe fallback. Do
not copy the internal controller into onboarding, add a second `DataBind`,
write View Model properties from the onboarding page, or connect onboarding
animation state to the camera verifier.

## Current design system to reuse

The detailed current design audit is in
[`docs/NUVO_DESIGN_SYSTEM_CONTEXT.md`](NUVO_DESIGN_SYSTEM_CONTEXT.md). The
implementation-critical pieces are:

| Need | Reuse | File |
|---|---|---|
| Colors/semantic roles | `NuvoColors`, `AppColors`, `NuvoSemanticColors` | `lib/core/theme/app_colors.dart` |
| Typography | `AppTextStyles`, Manrope | `lib/core/theme/app_text_styles.dart` |
| Spacing/radii/borders | `NuvoSpacing`, `NuvoRadii`, `NuvoBorders` | `lib/core/theme/app_geometry.dart` |
| Shadows | `AppShadows` hard offset tokens | `lib/core/theme/app_shadows.dart` |
| Responsive sizing | `NuvoResponsive`, `context.rs`, `NuvoTextScaleScope` | `lib/core/theme/nuvo_responsive.dart`, `lib/app/app.dart` |
| Primary action | `NuvoPrimaryButton` | `lib/core/widgets/nuvo_button.dart` |
| Secondary action | `NuvoOutlineButton` | `lib/core/widgets/nuvo_button.dart` |
| Quiet action | `NuvoTertiaryButton` / current `NuvoGhostButton` | `lib/core/widgets/nuvo_button.dart` |
| Back | `NuvoBackButton`, `NuvoBackNavRow` | `lib/core/widgets/nuvo_button.dart`, `nuvo_shared_components.dart` |
| Cards/surfaces | `NuvoCard`, `NuvoBackplateCard`, `NuvoCompactCard` | `nuvo_card.dart`, `nuvo_shared_components.dart` |
| Identity | `NuvoAvatar`, `NuvoAvatarStack`, `NuvoCompetitorAvatar` | `nuvo_avatar.dart` |
| Brand symbols | `NuvoIcon` | `nuvo_icons.dart` |
| Status/metadata | `NuvoPill`, `NuvoChip`, `NuvoMetaItem` | `nuvo_shared_components.dart`, `nuvo_chip.dart`, `nuvo_meta_row.dart` |
| Progress | `RaceProgress`, `NuvoRaceLane`, `NuvoRacePath` | `nuvo_race_components.dart`, `nuvo_shared_components.dart`, `nuvo_race_path.dart` |
| Loading/error/empty | `NuvoLoadingIndicator`, `NuvoErrorState`, `NuvoEmptyState` | corresponding `lib/core/widgets` files |
| Tactile interaction | `PressableScale` | `lib/core/widgets/pressable_scale.dart` |

Current core tokens are `NuvoColors.page = #FBFCFF`, `NuvoColors.navy =
#07152D`, `NuvoColors.blue = #1264FF`, and white surfaces. Current standard
button height is 56px with a 24px radius, navy 3px edge, and hard offset.
Use `AppTextStyles.screenTitle` for screen identity, `headlineLarge` or
`headlineMedium` for an instruction, and `bodyMedium`/`bodySmall` for support.
Current page margins are generally 20–22px, with the 4/8/12/16/20/24/32
spacing rhythm.

Do not add a repeated NUVO wordmark/logo watermark to each new onboarding
screen. The user is already inside Nuvo; the visual identity should come from
the actual color, type, outline, offset, and interaction language.

## Leaderboard implementation

### Existing production pieces

| Component | File | What it does | Direct onboarding reuse? |
|---|---|---|---|
| `NuvoPodium`, `NuvoPodiumEntry` | `lib/core/widgets/nuvo_podium.dart` | Flat top-three hierarchy; first place is larger/raised; avatars and rank marker carry podium colors; no pedestal blocks. | Reuse visually for a static final board or the settled state. Do not animate its private layout directly. |
| `NuvoLeaderboardRow` | `lib/core/widgets/nuvo_shared_components.dart` | Full-width rank/name/avatar/lane/value row; current-user state is highlighted. | Good styling reference and possible settled rows. Its internal row is stateless and not an overtaking controller. |
| `RacePlacement` | `lib/core/widgets/nuvo_race_components.dart` | Quiet rank number; gold/silver/bronze only for top-three placement. | Reuse for rank labels. |
| `RaceProgress` | `lib/core/widgets/nuvo_race_components.dart` | Thin race lane with start marker, progress marker, and finish check. | Reuse inside a lightweight onboarding row if needed. |
| `NuvoRaceLane` | `lib/core/widgets/nuvo_shared_components.dart` | Static compact lane for dense rows. | Reuse for the destination/settled row; do not rely on its ignored delay for choreography. |
| `NuvoRacePath` | `lib/core/widgets/nuvo_race_path.dart` | Deterministic curved production path; 700ms progress tween. | Reuse only if a race path is needed, not as the leaderboard carry path. |
| `NuvoAvatar` / `NuvoAvatarStack` | `lib/core/widgets/nuvo_avatar.dart` | Photo/initials identity with deterministic flat-color fallback. | Reuse directly. |

The current Race Detail leaderboard is in
[`lib/features/race_detail/presentation/race_detail_screen.dart`](../lib/features/race_detail/presentation/race_detail_screen.dart):
empty state first, `NuvoPodium` for top three, then outlined compact rows for
the rest, with current-user emphasis. The Arena preview is in
[`lib/features/arena/presentation/arena_screen_fixed.dart`](../lib/features/arena/presentation/arena_screen_fixed.dart):
same podium-first treatment and a compact remaining list.

### Current onboarding leaderboard visual

The legacy `/welcome/intro` page does not use `NuvoPodium` or
`NuvoLeaderboardRow`. `_LeaderboardVisual` in
`welcome_race_builder_screen.dart` creates three local `_RankRow`s in a
`Stack`, interpolates their `top` positions, changes rank labels/scores, and
uses scale/shadow emphasis when “You” wins. This is a visual prototype, not a
production leaderboard component.

### Safe future architecture for the requested overtaking motion

The requested animation is not a normal list reorder. The compatible Flutter
shape is an onboarding-local `StatefulWidget` with one parent-owned
`AnimationController` and a deterministic phase enum:

```text
INITIAL → PLAYING → FINAL
```

Use a `Stack` with explicit row slots and a final overlay layer for the picked-
up participant. During the carry phase:

- calculate source/destination rectangles from the slot geometry;
- render the lifted card last for higher z-order;
- use a `PathMetric`/cubic path or a small `CustomPainter` for the curved
  above-stack trajectory;
- transform the card with a very small lift/scale increase and stronger
  `AppShadows.hardSmall`/`hardMedium` treatment;
- shift the other rows’ slot positions beneath it;
- drop into first place and use a short `Curves.easeOutBack`/tight settle,
  not a large rubber bounce;
- use `NuvoAvatar`, `RacePlacement`, `NuvoRaceLane`, and the existing row
  colors inside the animated local shell.

Do not directly animate `NuvoPodium`’s internal private `_Place` widgets, use
`AnimatedList` as the whole effect, slide the card offscreen, or make the
production race leaderboard reorder to support onboarding. Keep this animation
isolated from live race state.

## Auth handoff

The auth screen is `/welcome`, implemented by
[`lib/features/auth/presentation/welcome_auth_screen.dart`](../lib/features/auth/presentation/welcome_auth_screen.dart).

Available auth actions:

- Email button → `context.push('/auth/email')`.
- `EmailStartScreen` starts the email code and pushes `/auth/verify` with the
  email in `state.extra`.
- `EmailVerifyScreen` calls `AuthController.verifyEmailCode()`; navigation is
  then owned by the router guard.
- Apple and Google buttons call `AuthController.signInWithApple()` and
  `signInWithGoogle()`; navigation is also guard-driven.
- Reviewer/demo paths are handled in `EmailStartScreen` and
  `WelcomeAuthScreen`.

After auth state becomes authenticated, `NuvoApp` listens for the transition
and consumes any pending deep-link destination only when the returned user’s
`onboardingComplete` is true. `AuthGate` then handles the normal route.

For a new redesigned onboarding that ends at auth:

1. Route the final Sign up/Login actions to `/welcome`.
2. Do not implement alternate auth screens or token storage.
3. Do not mark account onboarding complete merely because the pre-auth story
   has been viewed; that field currently represents server/account setup.
4. Preserve the existing post-auth `/onboarding/profile` and member-pass path
   until the product explicitly decides whether those screens remain.
5. Test the incomplete-user case because the current `/arena` redirect branch
   does not force profile setup.

## Expected new onboarding story

The requested future narrative is intentionally narrower than the current six-
page builder:

```text
CINEMATIC OPEN
  → existing race-path drawing concept, redesigned finish marker
SCREEN 1: what Nuvo is
  → goals become races with friends
SCREEN 2: create the race
  → create, invite, compete to the goal
SCREEN 3: do the activity
  → embed the existing jumping-jack Rive preview
SCREEN 4: leaderboard
  → picked-up participant overtakes and settles into first
SCREEN 5: social loop
  → a friend passes you, giving you a reason to respond
FINAL
  → Sign up or Log in at /welcome
```

There is a separate tutorial/first-race coach flow after onboarding. The new
pre-auth story should explain what Nuvo is and why it is interesting, not walk
through every control. It should not add a permanent logo header, page dots,
or a button during the cinematic open unless the new product decision changes
that requirement.

## Animation architecture and lifecycle guidance

Current code already uses these appropriate primitives:

- `AnimationController` with `TickerProviderStateMixin` or
  `SingleTickerProviderStateMixin`;
- `AnimatedBuilder` for painter-driven frames;
- `TweenAnimationBuilder` for simple progress transitions;
- `AnimatedSwitcher` for state replacement;
- `AnimatedContainer`/`AnimatedSize` for compact selection and layout changes;
- `PageController` for onboarding pages;
- `TickerMode` to disable child animations on inactive PageView pages;
- `flutter_animate` for short fade/slide entrance treatments;
- `PressableScale` for tactile non-button rows.

The safest onboarding lifecycle is:

```text
page becomes active
  → reset local controller/state
  → play exactly once or loop only while that page is active
  → settle on FINAL state
page becomes inactive
  → TickerMode off
  → stop/reset or dispose page-local controller
route disposed
  → dispose controllers, timers, PageController, and Rive FileLoader
```

Prefer one controller owned by the onboarding parent per coordinated scene or
one controller owned by a stateful page for a self-contained visual. Do not
create controllers in `build()`, scatter free-running timers through child
widgets, or leave a Rive/leaderboard animation running after the page is gone.
Avoid network/backend dependencies for explanatory visuals.

Use `MediaQuery.disableAnimationsOf(context)` for the new pages. The existing
Rive preview already uses it and switches to a static representative pose; the
legacy welcome builder does not yet have equivalent reduced-motion handling.

## Responsive and accessibility constraints

The app is portrait-first: `main.dart` sets `DeviceOrientation.portraitUp`.
`NuvoResponsive` uses a 390px baseline, clamps layout scaling to 0.90–1.18,
recognizes compact width below 360px and large width at/above 600px, and bases
vertical density on usable height after safe-area padding. `NuvoTextScaleScope`
clamps app text scaling to 0.85–1.30.

On web, `NuvoApp._webPreviewBuilder` centers a maximum 430px phone column when
the viewport is wider than 600px; mobile-sized web viewports fill normally.

Implementation rules for the future onboarding:

- Use `SafeArea` for standalone onboarding pages.
- Use `context.rs(...)`/`NuvoResponsive` for visual sizes that need to scale;
  do not assume every device is exactly 390×844.
- Use `LayoutBuilder`/constraints for the cinematic canvas and visual slots.
- Keep the primary CTA at least the existing 56px full-size button height and
  preserve the button’s actual hit target on compact devices.
- Keep text and CTA in separate bounded regions so a large text scale cannot
  push the action offscreen.
- Treat short iPhones as a first-class layout: reduce visual slot height and
  vertical gaps before shrinking tap targets or body copy below readability.
- Do not add a second bottom navigation or shell inset; onboarding is outside
  `MainShell` and should own only its own SafeArea/CTA geometry.
- Landscape is not a supported primary orientation in the current entrypoint.
- Automated layout tests do not prove the cinematic path, Rive framing, or
  leaderboard motion. Those still require runtime visual inspection.

## Testing baseline and known technical debt

### Commands and current results

At the time of this handoff:

- Flutter: `3.44.9` stable.
- Dart: `3.12.2`.
- `flutter test test/layout_onboarding_screens_test.dart`: passed.
- `flutter test test/splash_screen_offline_test.dart`: passed.
- `flutter test test/router_offline_routing_test.dart test/auth_controller_offline_test.dart`: passed.
- `flutter test test/nuvo_race_path_test.dart`: passed.
- `flutter test test/rive_jumping_jack_preview_test.dart test/rive_pose_controller_test.dart test/rive_side_treadmill_preview_test.dart test/rive_raw_smoke_test.dart`: passed sequentially.
- `flutter analyze --no-fatal-infos`: currently exits non-zero with 84
  info/warning findings in the working tree. Most are style findings, but
  this is not a clean current analyzer baseline.

The protected baseline document
[`docs/BASELINE_BEFORE_PRODUCT_SKELETON.md`](BASELINE_BEFORE_PRODUCT_SKELETON.md)
records an older clean-ish state with four info findings in
`auth_controller.dart`, zero warnings, and a demonstrated physical iPhone
release build. The current working tree has moved beyond that baseline and is
dirty with unrelated changes, so a future agent must not claim the old four-
finding number is the current result.

### Relevant test files

- `test/layout_onboarding_screens_test.dart`: profile onboarding CTA visible
  on 390×844 and 375×667, and no small-viewport overflow.
- `test/splash_screen_offline_test.dart`: splash handoff to Arena, authenticated
  Arena, and unauthenticated `/welcome/intro`.
- `test/router_offline_routing_test.dart`: loading, unauthenticated, offline,
  and authenticated guard behavior.
- `test/rive_raw_smoke_test.dart`: real `RiveWidget` render smoke test.
- `test/rive_nuvo_stickman_inspection_test.dart`: front asset artboard/View
  Model/state machine/property contract.
- `test/rive_nuvo_stickman_property_probe_test.dart`: additional asset/property
  probing.
- `test/rive_pose_controller_test.dart`: initial writes and six-control
  jumping-jack writes.
- `test/rive_jumping_jack_preview_test.dart`: loop, open/closed phases, finite
  values, and root arcs.
- `test/rive_side_treadmill_preview_test.dart`: side asset contract and gait.
- `test/nuvo_race_path_test.dart`: progress clamping, semantics, deterministic
  seed, and variant rendering.

There is currently no focused widget test for the full
`WelcomeRaceBuilderScreen` six-page cinematic sequence, no visual golden for
the Rive embedded in onboarding, and no test for the requested picked-up-card
leaderboard motion. Add focused tests for those only when the redesign is
implemented.

### Build/device notes

The project’s stable manual target is a physical iPhone. Existing docs use
`flutter run` for a connected device and `flutter build ios --no-codesign`
for an unsigned iOS build. The iOS Simulator has a known Google ML Kit /
Apple Silicon architecture history; do not use simulator success as proof that
the camera verifier or Rive onboarding composition is valid. A real device
visual pass is required for Rive framing, path bounds, and leaderboard motion.

Do not run bare `flutter test` for an onboarding change: the repository has
heavy `test/motion_qa/` material. Use focused tests or the documented bounded
test set instead.

## Safe change boundaries

### SAFE TO REPLACE

- The legacy pre-auth page composition in
  `welcome_race_builder_screen.dart`.
- Onboarding-local custom painters/visuals if they are no longer needed by
  the new story.
- Onboarding copy, page sequencing, local Flutter animation choreography, and
  local layout composition.
- The legacy onboarding-specific finish marker, provided the path concept and
  current app semantics are preserved.

### REUSE / MODIFY CAREFULLY

- `_ImmersiveRacePainter`/`_RacePathPainter`: private today; extract only as a
  small, isolated reusable widget if the new cinematic needs it.
- `NuvoRacePath`: production race progress, not automatically the cinematic
  opening path.
- Shared theme/button/card/avatar/leaderboard primitives: use them rather than
  cloning styles, but avoid changing their global appearance for onboarding.
- `RiveMovementPreview`: embed as-is with a bounded slot and fallback.
- `RivePoseController`, data binding, calibrated values, side rig, and sequence
  architecture: do not rewrite to make onboarding work.
- `welcomeOnboardingStateProvider`: preserve or explicitly reset if the new
  auth handoff no longer uses race-builder selections.
- `AuthUser.onboardingComplete` and `/onboarding/complete`: decide persistence
  separately from cinematic page completion.

### DO NOT TOUCH CASUALLY

- `lib/app/router.dart` and `lib/features/auth/presentation/auth_gate.dart`.
- `AuthController`, `AuthRepository`, `AuthApi`, `SecureTokenStore`, and the
  auth/session lifecycle.
- `MainShell` and the production bottom navigation.
- `AiMotionProofScreen` and all verifier/camera/ML Kit code.
- `RivePoseController`, `SideRigPoseController`, and production Rive assets.
- `RaceRepository`, race API/backend contracts, race controllers, or live
  leaderboard behavior outside onboarding.
- First-race guide/account-state cancellation logic in
  `first_use_guide.dart`.

## Exact file map for the new agent

### ONBOARDING

`lib/features/auth/presentation/welcome_race_builder_screen.dart`

- Responsibility: active pre-auth six-page onboarding/demo UI, opening scene,
  current local leaderboard/proof visuals, page controller, CTA.
- Likely change: replace the page composition and onboarding-local visuals;
  retain explicit `/welcome` handoff and clean controller lifecycle.

`lib/features/auth/presentation/welcome_onboarding_state.dart`

- Responsibility: in-memory race-builder and fitness-goal selections.
- Likely change: only if the new story needs different transient state; do not
  create a second persistence model casually.

`lib/features/auth/presentation/welcome_auth_screen.dart`

- Responsibility: final pre-auth screen and provider buttons.
- Likely change: preserve auth actions/routes; visual adjustments only if the
  redesigned final screen intentionally changes the auth presentation.

`lib/features/onboarding/presentation/onboarding_screen.dart`

- Responsibility: authenticated profile/terms setup.
- Likely change: normally none for the pre-auth redesign.

`lib/features/onboarding/presentation/member_pass_screen.dart`

- Responsibility: authenticated member pass setup.
- Likely change: normally none for the pre-auth redesign; note completion call
  behavior separately.

### OPENING ANIMATION

`lib/features/auth/presentation/welcome_race_builder_screen.dart`

- Responsibility: `_ImmersiveRacePainter`, `_racePath`, `_drawNuvoFlag`,
  `_sceneController`, typed cinematic reveal.
- Likely change: isolate/reuse the path concept and redesign the finish marker;
  do not assume the private painter is a reusable API.

`lib/core/widgets/nuvo_race_path.dart`

- Responsibility: deterministic production race paths and progress markers.
- Likely change: likely reuse only for settled race visuals, not necessarily
  the opening cinematic.

### RIVE MOTION PREVIEW

`lib/features/races/presentation/widgets/rive_movement_preview.dart`

- Responsibility: working `RiveWidgetBuilder`/`RiveWidget` embedding, binding,
  animation lifecycle, framing, fallback.
- Likely change: no change required; embed `RiveMovementPreview` directly.

`lib/features/races/presentation/movement_preview/rive_pose_controller.dart`

- Responsibility: front View Model property handles and writes.
- Likely reuse: direct internal dependency only; do not duplicate.

`lib/features/races/presentation/movement_preview/jumping_jack_preview_sequence.dart`
and `jumping_jack_human_motion_profile.dart`

- Responsibility: measured jumping-jack normalized motion and 1,000ms loop.
- Likely reuse: direct through `RiveMovementPreview`; do not rewrite in the
  onboarding page.

`assets/animations/preverify/nuvo_stickman.riv`

- Responsibility: front-view Rive rig.
- Likely reuse: through the existing widget only.

### LEADERBOARD

`lib/core/widgets/nuvo_podium.dart`

- Responsibility: settled top-three production podium.
- Likely reuse: visual/style reference and final state, not direct animated
  internal layout.

`lib/core/widgets/nuvo_shared_components.dart`

- Responsibility: `NuvoLeaderboardRow`, `NuvoRaceLane`, shared row surfaces.
- Likely reuse: row contents/style inside a local onboarding animation shell.

`lib/core/widgets/nuvo_race_components.dart`

- Responsibility: `RacePlacement`, `RaceProgress`, race rows and aliases.
- Likely reuse: rank/progress semantics only; do not alter live components for
  onboarding choreography.

`lib/core/widgets/nuvo_avatar.dart`

- Responsibility: avatar identity/fallbacks.
- Likely reuse: direct.

### DESIGN SYSTEM

`docs/NUVO_DESIGN_SYSTEM_CONTEXT.md`

- Responsibility: current token/component audit and onboarding design contract.

`lib/core/theme/app_colors.dart`, `app_text_styles.dart`, `app_geometry.dart`,
`app_shadows.dart`, `nuvo_responsive.dart`

- Responsibility: colors, Manrope typography, spacing/radii/borders, offset
  shadows, responsive sizing/text scaling.

`lib/core/widgets/nuvo_button.dart`, `nuvo_card.dart`,
`nuvo_shared_components.dart`, `pressable_scale.dart`

- Responsibility: shared action/surface/tactile primitives.

### ROUTING / AUTH

`lib/main.dart`, `lib/app/app.dart`, `lib/app/router.dart`

- Responsibility: process entry, `NuvoApp`, router, route builders.
- Touch? No, unless the redesign intentionally changes the route graph and
  updates `docs/NAVIGATION_MAP.md` plus routing tests in the same scoped change.

`lib/features/auth/presentation/auth_gate.dart`

- Responsibility: auth/onboarding/offline redirects.
- Touch? No for a visual redesign. The incomplete-user `/arena` behavior is a
  known decision point, not something to fix implicitly.

`lib/features/auth/presentation/auth_controller.dart`,
`lib/features/auth/data/auth_repository.dart`,
`auth_api.dart`, `secure_token_store.dart`

- Responsibility: session/auth/profile/onboarding completion/token storage.
- Touch? No for the visual redesign.

### TESTS

- `test/layout_onboarding_screens_test.dart` — current post-auth profile layout.
- `test/splash_screen_offline_test.dart` — splash handoff cases.
- `test/router_offline_routing_test.dart` — redirect behavior.
- `test/rive_raw_smoke_test.dart` — actual Rive widget render.
- `test/rive_nuvo_stickman_inspection_test.dart` and
  `test/rive_nuvo_stickman_property_probe_test.dart` — asset contract.
- `test/rive_jumping_jack_preview_test.dart`,
  `test/rive_pose_controller_test.dart`, and
  `test/rive_side_treadmill_preview_test.dart` — motion preview contracts.
- `test/nuvo_race_path_test.dart` — production path contract.

Add future onboarding-specific tests beside these focused tests. Do not claim
animation correctness from unit tests alone; inspect the running app on a
physical iPhone at small, baseline, and tall viewport sizes.

