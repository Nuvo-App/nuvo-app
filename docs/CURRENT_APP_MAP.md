# Current App Map

Captured in read-only mode on the `nuvo-next/product-skeleton` branch.
No app code was edited while building this map.

This document is a snapshot. It will become stale as the app evolves.
Verify specific details against the actual source files before relying on them.

---

## Current screens

### Auth / Launch

| Screen | File | Route | Notes |
|---|---|---|---|
| Splash | `lib/features/splash/presentation/splash_screen.dart` | `/splash` | Initial loading screen while auth restores |
| Welcome / Auth gate | `lib/features/auth/presentation/welcome_auth_screen.dart` | `/welcome` | Email CTA + disabled Google row + signup/login toggle + marketing preview card |
| Email start | `lib/features/auth/presentation/email_start_screen.dart` | `/auth/email` | Email entry form |
| Email verify | `lib/features/auth/presentation/email_verify_screen.dart` | `/auth/verify` | OTP code entry |

### Onboarding

| Screen | File | Route | Notes |
|---|---|---|---|
| Create identity | `lib/features/onboarding/presentation/create_identity_screen.dart` | `/onboarding/create-identity` | Username + full name |
| Secure account | `lib/features/onboarding/presentation/secure_account_screen.dart` | `/onboarding/secure-account` | Profile privacy toggle |
| Profile | `lib/features/onboarding/presentation/onboarding_screen.dart` | `/onboarding/profile` | Profile setup |
| Member pass | `lib/features/onboarding/presentation/member_pass_screen.dart` | `/onboarding/member-pass` | Shows QR member pass during onboarding |
| Add crew | `lib/features/onboarding/presentation/add_crew_screen.dart` | `/onboarding/add-crew` | Has 4 "coming soon" labels (QR scan, direct links, contact invites, crew search) |
| First race | `lib/features/onboarding/presentation/first_race_screen.dart` | `/onboarding/first-race` | Prompts to create first race |

### Main app (bottom nav / shell)

| Screen | File | Route | Nav label | Nav icon |
|---|---|---|---|---|
| Arena | `lib/features/arena/presentation/arena_screen.dart` | `/arena` | Arena | grid_view_rounded |
| Pass (member pass) | `lib/features/pass/presentation/pass_screen.dart` | `/pass` | **Crew** ⚠️ | group_rounded |
| Compete | `lib/features/compete/presentation/compete_screen.dart` | `/compete` | Compete | add_circle_rounded |
| Profile | `lib/features/profile/presentation/profile_screen.dart` | `/profile` | Profile | person_rounded |

**⚠️ Nav mismatch:** The second tab has the label "Crew" and shows a crew icon
but routes to `/pass` (the member pass / QR screen). The actual `PassScreen`
shows the member pass card and QR code. There is no standalone Crew tab — crew
management happens inside the invite screens. This is confusing but working.

### Race flows (standalone / push)

| Screen | File | Route | Notes |
|---|---|---|---|
| Create race | `lib/features/races/presentation/create_race_screen.dart` | `/races/new` | Full race creation form with AI activity picker |
| Join race by code | `lib/features/races/presentation/join_race_screen.dart` | `/races/join` | Code input |
| Race detail | `lib/features/race_detail/presentation/race_detail_screen.dart` | `/race/:id` | Leaderboard + proof rows + owner management |
| Race settings | `lib/features/races/presentation/race_settings_screen.dart` | `/race/:id/settings` AND `/race/:id/edit` | ⚠️ Both routes lead to the same screen |
| Invite crew | `lib/features/races/presentation/invite_crew_screen.dart` | `/race/:id/invite` | User search + invite code + share |
| Submit proof | `lib/features/races/presentation/submit_proof_screen.dart` | `/race/:id/proof` | AI motion entry card or manual form |
| AI Motion Proof | `lib/features/races/presentation/ai_motion_proof_screen.dart` | `/race/:id/proof/ai-motion` | Live camera + pose detection |
| Proof review | `lib/features/races/presentation/proof_review_screen.dart` | `/race/:id/proofs/:proofId` | Owner reviews a specific proof |

### Other

| Screen | File | Route | Notes |
|---|---|---|---|
| Proof detail | `lib/features/proof/presentation/proof_screen.dart` | `/proof/:id` | Standalone proof view |
| Edit profile | `lib/features/profile/presentation/edit_profile_screen.dart` | `/profile/edit` | Edit full name + username |

---

## Current route / navigation structure

**Router:** `go_router` v14 with a `ShellRoute` for the main bottom-nav shell.
**Provider:** `routerProvider` in `lib/app/router.dart`.
**Auth guard:** `RouterNotifier` in `lib/features/auth/presentation/auth_gate.dart`.

### Route guard logic (auth_gate.dart)

```
/splash → always passes through
unauthenticated + protected route → redirect to /welcome
authenticated + onboardingComplete=true + auth/onboarding route → redirect to /arena
authenticated + onboardingComplete=false + pre-onboarding route → redirect to /onboarding/create-identity
```

Protected routes: `/arena`, `/pass`, `/compete`, `/profile`, `/race/`, `/races/`, `/proof/`

### Shell routes (bottom nav)

```
/arena    → ArenaScreen
/pass     → PassScreen
/compete  → CompeteScreen
/profile  → ProfileScreen
```

### Duplicate routes

`/race/:id/settings` and `/race/:id/edit` both instantiate `RaceSettingsScreen`.
One is dead. See [router.dart:172-184](../lib/app/router.dart).

---

## Current major feature folders

```
lib/
  app/                          → app.dart, router.dart
  core/
    constants/                  → asset_paths.dart
    models/                     → user_profile.dart  ⚠️ (duplicate — old)
    navigation/                 → nuvo_navigation.dart (NuvoBackButton, safePopOrGo)
    theme/                      → app_colors.dart, app_gradients.dart, app_shadows.dart,
                                   app_text_styles.dart, app_theme.dart
    widgets/                    → shared UI components (see below)
  data/
    models/                     → friend.dart, race.dart, user_profile.dart  ⚠️ (all old/orphaned)
  features/
    arena/presentation/         → arena_screen.dart
    auth/
      data/                     → auth_api.dart, auth_models.dart, auth_repository.dart, secure_token_store.dart
      presentation/             → auth_controller.dart, auth_gate.dart, email_start_screen.dart,
                                   email_verify_screen.dart, welcome_auth_screen.dart
                                   + orphans: apple_placeholder_button.dart, otp_screen.dart, phone_auth_screen.dart
    compete/presentation/       → compete_screen.dart
    onboarding/presentation/    → add_crew_screen.dart, create_identity_screen.dart, first_race_screen.dart,
                                   member_pass_screen.dart, onboarding_screen.dart, secure_account_screen.dart
    pass/presentation/          → pass_screen.dart
    profile/presentation/       → edit_profile_screen.dart, profile_screen.dart
    proof/presentation/         → proof_screen.dart
    race_detail/presentation/   → race_detail_screen.dart
    races/
      ai/                       → camera_image_converter.dart, motion_validators.dart, pose_detector_service.dart
                                   + orphans: jumping_jack_counter.dart, push_up_counter.dart
      data/                     → ai_motion_models.dart, race_api.dart, race_models.dart, race_repository.dart
      domain/                   → motion_activity.dart, motion_activity_catalog.dart
      presentation/             → ai_motion_proof_screen.dart, create_race_screen.dart, invite_crew_screen.dart,
                                   join_race_screen.dart, proof_review_screen.dart, race_controller.dart,
                                   race_settings_screen.dart, submit_proof_screen.dart
    shell/presentation/         → main_shell.dart
    splash/presentation/        → splash_screen.dart
    welcome/presentation/       → welcome_screen.dart  ⚠️ (orphan — not routed)
  main.dart
```

---

## Current backend caller files

| File | What it calls | Auth required |
|---|---|---|
| `lib/features/auth/data/auth_api.dart` | `/auth/email/start`, `/auth/email/verify`, `/auth/google`, `/auth/refresh`, `/auth/logout`, `/auth/me`, `/auth/account` (DELETE), `/profile`, `/profile/username/check`, `/onboarding/complete`, `/pass/me` | Optional (none for start/verify) |
| `lib/features/races/data/race_api.dart` | `/races` (GET/POST), `/races/:id` (GET/PATCH), `/races/:id/proof`, `/races/:id/archive`, `/races/:id/cancel`, `/races/:id/leave`, `/races/:id/join`, `/races/:id/participants`, `/races/:id/invite-code`, `/races/join-code`, `/races/:id/proofs/:proofId`, `/crew` (GET), `/crew/add`, `/crew/:userId` (DELETE), `/users/search` | All calls require Bearer token |

**Base URL:** `https://nuvo-api.getnuvoapp.workers.dev`
(compile-time injectable via `--dart-define=NUVO_API_BASE_URL=...`)

**⚠️ Duplicate:** `_kApiBase` is defined in both `auth_api.dart:7` and
`race_api.dart:8`. If the URL changes, both files must be updated.

---

## Current state / controller / provider files

| File | Provider name | What it manages |
|---|---|---|
| `lib/features/auth/presentation/auth_controller.dart` | `authControllerProvider` (StateNotifier) | Auth state: loading/authenticated/unauthenticated, current user, session restore, login, logout |
| `lib/features/auth/presentation/auth_controller.dart` | `authRepositoryProvider` | AuthRepository instance |
| `lib/features/auth/presentation/auth_controller.dart` | `authApiProvider` | AuthApi instance |
| `lib/features/auth/presentation/auth_controller.dart` | `secureTokenStoreProvider` | SecureTokenStore instance |
| `lib/features/auth/presentation/auth_gate.dart` | `routerNotifierProvider` | GoRouter redirect logic, listens to authControllerProvider |
| `lib/features/races/presentation/race_controller.dart` | `raceControllerProvider` (StateNotifier) | All races list, create/update/delete/join/leave race, submit proof, crew operations |
| `lib/features/races/presentation/race_controller.dart` | `raceRepositoryProvider` | RaceRepository instance |
| `lib/app/router.dart` | `routerProvider` | GoRouter instance |

**Note:** `raceControllerProvider` automatically calls `loadRaces()` on
construction and when auth transitions from unauthenticated → authenticated.
It clears races on logout. This provider is consumed by Arena, Compete, Profile,
Race Detail, Submit Proof, AI Motion Proof, and Invite Crew.

---

## Current risky files

These files are dangerous to casually edit. Changes here have broken the demo
before or could break it.

| File | Risk | Why |
|---|---|---|
| `lib/features/auth/data/auth_api.dart` | High | Live auth endpoints, token handling |
| `lib/features/auth/data/auth_repository.dart` | High | Token refresh, session restore chain |
| `lib/features/auth/presentation/auth_controller.dart` | High | Session state machine, logout |
| `lib/features/auth/presentation/auth_gate.dart` | High | Route guard — wrong redirect = infinite loop or locked-out users |
| `lib/features/auth/data/secure_token_store.dart` | High | iOS Keychain read/write |
| `lib/features/races/data/race_api.dart` | High | All backend race endpoints — field names match D1 schema |
| `lib/features/races/data/race_repository.dart` | High | Token injection and error propagation for all race operations |
| `lib/features/races/presentation/race_controller.dart` | High | Shared state provider — all race screens depend on it |
| `lib/features/races/ai/motion_validators.dart` | High | Core AI verification math — do not fake, do not tweak thresholds |
| `lib/features/races/presentation/ai_motion_proof_screen.dart` | High | Camera lifecycle — wrong dispose order = hardware leak on iPhone |
| `lib/features/races/ai/pose_detector_service.dart` | High | ML Kit bridge |
| `lib/features/races/ai/camera_image_converter.dart` | High | iOS BGRA8888 / Android NV21 pixel conversion |
| `ios/Podfile` | High | iOS build configuration |
| `ios/Runner.xcodeproj/project.pbxproj` | High | Xcode project — corruption breaks all iOS builds |
| `ios/Runner/Info.plist` | High | App permissions |
| `pubspec.yaml` / `pubspec.lock` | High | Dependency changes can silently break ML Kit + camera + secure storage |
| `server/worker/` | High | Backend logic + D1 schema — changes must be coordinated with deployment |

---

## Current dead / prototype UI areas

These are user-visible prototype leaks that must be cleaned up in the product
skeleton pass. Do not leave them in production.

| Location | String / behavior | User impact |
|---|---|---|
| `welcome_auth_screen.dart:576` | `"Google sign-in — needs setup"` | All users see this on the auth screen — looks broken |
| `add_crew_screen.dart:129` | `"Crew search is coming soon."` | Shown during onboarding |
| `add_crew_screen.dart:138` | `"QR scanning coming soon."` | Shown during onboarding |
| `add_crew_screen.dart:154` | `"QR scanning coming soon."` | Shown during onboarding |
| `add_crew_screen.dart:166` | `"Direct race links are coming soon."` | Shown during onboarding |
| `add_crew_screen.dart:178` | `"Contact invites are coming soon."` | Shown during onboarding |
| `profile_screen.dart:169` | `"Privacy settings are coming soon."` | Privacy tile opens this |
| `race_settings_screen.dart:321` | `"photo/video proof coming soon"` | Visible in proof method selector |
| `race_settings_screen.dart:333` | `"AI review coming soon"` | Visible in review mode selector |
| `submit_proof_screen.dart:535` | `"AI Motion Proof is coming soon for this movement."` | Shown in `_DisabledAiCard` |
| `create_race_screen.dart:316` | `"AI Motion Proof is coming soon for this movement."` | Shown in activity picker |
| `proof_screen.dart:39` | `"Manual proof is active for this race. AI proof check is coming soon."` | Shown in proof screen |
| `race_detail_screen.dart:29` | `"AI Motion Proof coming soon"` | Shown as proof method label |
| Arena notifications bell | Static sheet: `"No race updates yet."` | Bell icon looks interactive but permanently shows placeholder |
| Profile notifications tile | Same static sheet | Tap does nothing real |
| Profile privacy tile | Same static sheet | Tap does nothing real |

---

## Current duplicated concepts

| Duplicate | Files | Impact |
|---|---|---|
| `_kApiBase` constant | `auth_api.dart:7`, `race_api.dart:8` | Must be changed in two places if URL changes |
| `/race/:id/settings` and `/race/:id/edit` routes | `router.dart:172-184` | Both go to `RaceSettingsScreen` — one is dead |
| Old model files | `lib/data/models/race.dart`, `lib/data/models/user_profile.dart`, `lib/core/models/user_profile.dart` | Active models are in `lib/features/races/data/race_models.dart` and `lib/features/auth/data/auth_models.dart` |
| Hard-offset shadow style | Repeated ~20 times across screens | Slightly different offsets (2,3 / 3,4 / 4,5 / 5,6) — not harmful but inconsistent |
| Danger color `Color(0xFFE5484D)` | Used inline in 8+ files | Should be a `NuvoColors` token |

---

## Confirmed orphaned files (zero imports in active code)

These files exist in the repo but are never imported by any active screen or
widget. They are safe to delete but must be grep-confirmed before deletion.

| File | Why orphaned |
|---|---|
| `lib/features/auth/presentation/phone_auth_screen.dart` | Old SMS auth — banned technology |
| `lib/features/auth/presentation/otp_screen.dart` | Replaced by `email_verify_screen.dart` |
| `lib/features/welcome/presentation/welcome_screen.dart` | Second welcome screen not wired to router |
| `lib/core/widgets/dream_background.dart` | Visual component with no consumers |
| `lib/core/widgets/friend_card.dart` | Card component with no consumers |
| `lib/core/widgets/glass_container.dart` | Glass effect widget with no consumers |
| `lib/core/widgets/gradient_button.dart` | Old button, replaced by `nuvo_button.dart` |
| `lib/core/widgets/nuvo_card.dart` | Card wrapper with no consumers |
| `lib/core/widgets/nuvo_dark_card.dart` | Dark card variant with no consumers |
| `lib/core/widgets/nuvo_chip.dart` | Chip widget with no consumers |
| `lib/core/widgets/arena_card.dart` | Only references `progress_player_row.dart` (also orphaned) |
| `lib/core/widgets/proof_scanner_card.dart` | No consumers |
| `lib/core/widgets/nuvo_page.dart` | Page wrapper with no consumers |
| `lib/core/widgets/animations.dart` | Animation helpers with no consumers |
| `lib/core/widgets/fade_slide_in.dart` | Animation widget with no consumers |
| `lib/core/widgets/progress_player_row.dart` | Only imported by `arena_card.dart` (orphaned) |
| `lib/features/auth/presentation/apple_placeholder_button.dart` | Apple sign-in never implemented |
| `lib/features/races/ai/jumping_jack_counter.dart` | Superseded by `motion_validators.dart` |
| `lib/features/races/ai/push_up_counter.dart` | Explicit placeholder — version string `'nuvo-ai-motion-v1-push-up-placeholder'` |
| `lib/data/models/friend.dart` | Old data model — active model is in features |
| `lib/data/models/race.dart` | Old data model — active model is in features |
| `lib/data/models/user_profile.dart` | Old data model — active model is in features |
| `lib/core/models/user_profile.dart` | Old data model — active model is in features |

---

## Files that should not be touched casually

(See also `docs/BASELINE_BEFORE_PRODUCT_SKELETON.md` → Do-not-touch areas)

Any file in:
- `lib/features/auth/data/`
- `lib/features/auth/presentation/auth_controller.dart`
- `lib/features/auth/presentation/auth_gate.dart`
- `lib/features/auth/data/secure_token_store.dart`
- `lib/features/races/ai/motion_validators.dart`
- `lib/features/races/ai/pose_detector_service.dart`
- `lib/features/races/ai/camera_image_converter.dart`
- `lib/features/races/presentation/ai_motion_proof_screen.dart`
- `lib/features/races/data/race_api.dart`
- `lib/features/races/data/race_repository.dart`
- `lib/features/races/presentation/race_controller.dart`
- `ios/`
- `server/worker/`
- `pubspec.yaml`
- `pubspec.lock`

---

## Uncertain findings

The following were noted during mapping and should be verified before any
related work:

1. **Nav label vs. route mismatch:** `bottom_nav.dart` labels tab index 1 as
   "Crew" with a group icon, but `main_shell.dart` routes it to `/pass`
   (the PassScreen / member pass QR). There is no dedicated Crew tab in the
   current app. Crew management happens inside the invite flow. Clarify whether
   the tab is intended to be "Crew" (social) or "Pass" (identity) — the current
   behavior is the pass screen.

2. **Old model files in `lib/data/models/` and `lib/core/models/`:** These
   appear to be early versions of data models. They were not imported by any
   active code at the time of this map, but grep them individually before
   deleting to be safe.

3. **`proof_screen.dart` at `/proof/:id`:** This standalone proof view is
   routed but it is unclear from the current codebase which user action
   navigates to it. Race detail only navigates to `/race/:id/proofs/:proofId`
   (the `ProofReviewScreen`), not to `/proof/:id`. This route may be a dead end.

4. **5-second polling timer in `race_detail_screen.dart`:** A `Timer.periodic`
   fires every 5 seconds to call `_silentRefresh`. On a long-lived session with
   multiple races open, this could generate significant traffic. This is
   functional but worth monitoring for the demo.
