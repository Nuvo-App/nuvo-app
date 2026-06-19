# CODEBASE MAP — Nuvo Flutter App
Generated: Phase 1 mapping. Do not implement until Phase 2 is approved.

---

## 1. Current Project Structure Summary

```
nuvo/
├── lib/
│   ├── main.dart                          # Entry point
│   ├── app/
│   │   ├── app.dart                       # NuvoApp (MaterialApp.router)
│   │   └── router.dart                    # GoRouter config (all routes)
│   ├── core/
│   │   ├── constants/
│   │   │   └── asset_paths.dart           # AssetPaths.nuvoLogo
│   │   ├── models/
│   │   │   └── user_profile.dart          # Richer UserProfile (id, phone, wins...)
│   │   ├── theme/
│   │   │   ├── app_colors.dart            # NuvoColors + AppColors
│   │   │   ├── app_gradients.dart         # AppGradients (brand/dream/victory/hot)
│   │   │   ├── app_shadows.dart           # AppShadows
│   │   │   ├── app_text_styles.dart       # AppTextStyles (Inter font only)
│   │   │   └── app_theme.dart             # AppTheme.light() (single theme)
│   │   └── widgets/
│   │       ├── animations.dart
│   │       ├── arena_card.dart            # StackedRaceCard
│   │       ├── bottom_nav.dart            # NuvoBottomNav (custom pill)
│   │       ├── dream_background.dart
│   │       ├── fade_slide_in.dart
│   │       ├── friend_card.dart           # FriendCard
│   │       ├── glass_container.dart
│   │       ├── gradient_button.dart
│   │       ├── member_pass_card.dart      # MemberPassCard (dark navy QR card)
│   │       ├── nuvo_button.dart           # NuvoPrimaryButton, NuvoOutlineButton
│   │       ├── nuvo_card.dart
│   │       ├── nuvo_chip.dart
│   │       ├── nuvo_dark_card.dart
│   │       ├── nuvo_page.dart
│   │       ├── nuvo_progress_bar.dart
│   │       ├── otp_input.dart             # OtpInput (6-cell row)
│   │       ├── pressable_scale.dart       # PressableScale tap widget
│   │       ├── progress_player_row.dart
│   │       └── proof_scanner_card.dart
│   ├── data/
│   │   ├── mock_data.dart                 # currentUser, friends, races, raceIdeas
│   │   └── models/
│   │       ├── friend.dart                # Friend
│   │       ├── race.dart                  # Race, RacePlayer
│   │       └── user_profile.dart          # Simpler UserProfile (name, username, memberId)
│   └── features/
│       ├── arena/presentation/arena_screen.dart
│       ├── auth/presentation/
│       │   ├── phone_auth_screen.dart     # UI only — no real SMS
│       │   └── otp_screen.dart            # UI only — no real verification
│       ├── compete/presentation/compete_screen.dart
│       ├── onboarding/presentation/
│       │   ├── add_crew_screen.dart
│       │   ├── create_identity_screen.dart
│       │   ├── first_race_screen.dart
│       │   ├── member_pass_screen.dart    # Shows MemberPassCard from mock currentUser
│       │   ├── onboarding_screen.dart     # "Build your profile" step
│       │   └── secure_account_screen.dart # Placeholder — links to browser URL
│       ├── pass/presentation/pass_screen.dart
│       ├── profile/presentation/profile_screen.dart
│       ├── proof/presentation/proof_screen.dart
│       ├── race_detail/presentation/race_detail_screen.dart
│       ├── shell/presentation/main_shell.dart
│       ├── splash/presentation/splash_screen.dart
│       └── welcome/presentation/welcome_screen.dart
├── assets/
│   ├── branding/trans.png                 # White Nuvo logo (dark bg only)
│   └── images/
├── ios/Runner/                            # Standard Flutter iOS runner
├── pubspec.yaml
└── (no server/ folder exists yet)
```

---

## 2. App Entry Point

**File:** [lib/main.dart](lib/main.dart)

```
main()
  └── ProviderScope
        └── NuvoApp (ConsumerWidget)
              └── MaterialApp.router
                    ├── theme: AppTheme.light()
                    └── routerConfig: appRouter
```

- `WidgetsFlutterBinding.ensureInitialized()` called
- Orientation locked to portrait-up via `SystemChrome`
- `ProviderScope` wraps the whole app (Riverpod ready)
- No Firebase, Supabase, or any platform init beyond orientation

---

## 3. Router / Navigation Setup

**File:** [lib/app/router.dart](lib/app/router.dart)

- Package: `go_router ^14.6.2`
- `initialLocation: '/splash'`
- No auth redirect guard yet (no `redirect:` callback)
- No `refreshListenable` (no auth state listener)

| Route | Screen | Notes |
|---|---|---|
| `/splash` | SplashScreen | 1.7s timer → `/welcome` |
| `/welcome` | WelcomeScreen | Entry; CTAs → onboarding or `/auth/phone` |
| `/onboarding/create-identity` | CreateIdentityScreen | Step 1 |
| `/onboarding/secure-account` | SecureAccountScreen | Step 2 — auth placeholder |
| `/onboarding/profile` | OnboardingScreen | Step 3 |
| `/onboarding/member-pass` | OnboardingMemberPassScreen | Step 4 |
| `/onboarding/add-crew` | AddCrewScreen | Step 5 |
| `/onboarding/first-race` | FirstRaceScreen | Step 6 |
| `/auth/phone` | PhoneAuthScreen | Returning user path |
| `/auth/otp` | OtpScreen | OTP entry (UI only) |
| `/arena` | ArenaScreen | Shell tab 0 |
| `/pass` | PassScreen | Shell tab 1 |
| `/compete` | CompeteScreen | Shell tab 2 |
| `/profile` | ProfileScreen | Shell tab 3 |
| `/race/:id` | RaceDetailScreen | Detail — parameterised |
| `/proof/:id` | ProofScreen | Detail — parameterised |

Shell tabs wrapped in `ShellRoute` → `MainShell`.

---

## 4. Theme / Design System Files

**Directory:** [lib/core/theme/](lib/core/theme/)

| File | Purpose |
|---|---|
| [app_colors.dart](lib/core/theme/app_colors.dart) | `NuvoColors` (raw hex) + `AppColors` (semantic aliases) |
| [app_text_styles.dart](lib/core/theme/app_text_styles.dart) | `AppTextStyles` — Inter only, 12 named styles |
| [app_theme.dart](lib/core/theme/app_theme.dart) | `AppTheme.light()` — single Material3 theme; `AppTheme.dark()` is an alias for light |
| [app_shadows.dart](lib/core/theme/app_shadows.dart) | `AppShadows.card`, `.brandGlow`, `.victoryGlow`, `.hotGlow` |
| [app_gradients.dart](lib/core/theme/app_gradients.dart) | `AppGradients.brand/dream/victory/hot/cardAmbient/topScrim` |

Key palette values:
- Page bg: `#F6F8FF` (icy white)
- Navy: `#07152B` (primary text + outlines)
- Blue (CTA): `#075BFF`
- Border: `#DCE5F2`
- Success/mint: `#16C784`

---

## 5. Existing Reusable Widgets

**Directory:** [lib/core/widgets/](lib/core/widgets/)

| Widget | File | Description |
|---|---|---|
| `NuvoPrimaryButton` | [nuvo_button.dart](lib/core/widgets/nuvo_button.dart) | Blue pill CTA with optional icon + loading state |
| `NuvoOutlineButton` | [nuvo_button.dart](lib/core/widgets/nuvo_button.dart) | Navy outline variant |
| `NuvoBottomNav` | [bottom_nav.dart](lib/core/widgets/bottom_nav.dart) | Custom rounded pill nav bar |
| `MemberPassCard` | [member_pass_card.dart](lib/core/widgets/member_pass_card.dart) | Dark navy card with QR code (qr_flutter) |
| `StackedRaceCard` | [arena_card.dart](lib/core/widgets/arena_card.dart) | Race preview card |
| `FriendCard` | [friend_card.dart](lib/core/widgets/friend_card.dart) | Crew member row |
| `OtpInput` | [otp_input.dart](lib/core/widgets/otp_input.dart) | 6-cell OTP row with auto-focus |
| `PressableScale` | [pressable_scale.dart](lib/core/widgets/pressable_scale.dart) | Tap scale feedback wrapper |
| `FadeSlideIn` | [fade_slide_in.dart](lib/core/widgets/fade_slide_in.dart) | Entry animation |
| `NuvoProgressBar` | [nuvo_progress_bar.dart](lib/core/widgets/nuvo_progress_bar.dart) | Progress bar |
| `NuvoCard/DarkCard` | [nuvo_card.dart](lib/core/widgets/nuvo_card.dart) / [nuvo_dark_card.dart](lib/core/widgets/nuvo_dark_card.dart) | Base card containers |
| `NuvoChip` | [nuvo_chip.dart](lib/core/widgets/nuvo_chip.dart) | Tag/badge chip |
| `GlassContainer` | [glass_container.dart](lib/core/widgets/glass_container.dart) | Glassmorphism variant |
| `GradientButton` | [gradient_button.dart](lib/core/widgets/gradient_button.dart) | Gradient CTA |
| `DreamBackground` | [dream_background.dart](lib/core/widgets/dream_background.dart) | Page bg pattern |
| `ProgressPlayerRow` | [progress_player_row.dart](lib/core/widgets/progress_player_row.dart) | Race leaderboard row |
| `ProofScannerCard` | [proof_scanner_card.dart](lib/core/widgets/proof_scanner_card.dart) | Proof submission card |

---

## 6. Existing Onboarding Screens

**Directory:** [lib/features/onboarding/presentation/](lib/features/onboarding/presentation/)

| Step | File | Route | Status |
|---|---|---|---|
| 1 | [create_identity_screen.dart](lib/features/onboarding/presentation/create_identity_screen.dart) | `/onboarding/create-identity` | UI complete — live avatar, name + username fields |
| 2 | [secure_account_screen.dart](lib/features/onboarding/presentation/secure_account_screen.dart) | `/onboarding/secure-account` | **Auth placeholder** — opens `nuvothrive.netlify.app` in browser or skips in demo mode |
| 3 | [onboarding_screen.dart](lib/features/onboarding/presentation/onboarding_screen.dart) | `/onboarding/profile` | UI complete — hardcoded "AK" initials, no state passed in |
| 4 | [member_pass_screen.dart](lib/features/onboarding/presentation/member_pass_screen.dart) | `/onboarding/member-pass` | Uses `currentUser` mock data |
| 5 | [add_crew_screen.dart](lib/features/onboarding/presentation/add_crew_screen.dart) | `/onboarding/add-crew` | UI (not inspected in depth) |
| 6 | [first_race_screen.dart](lib/features/onboarding/presentation/first_race_screen.dart) | `/onboarding/first-race` | UI (not inspected in depth) |

Step progress indicator shows 5 segments. Step 2 is where auth needs to hook in.

---

## 7. Existing Pass / Member Pass Screens

- **Onboarding pass:** [lib/features/onboarding/presentation/member_pass_screen.dart](lib/features/onboarding/presentation/member_pass_screen.dart)
  - Shows `MemberPassCard(profile: currentUser)` (mock data)
  - Share via `share_plus`
  - Navigates to `/onboarding/add-crew`

- **Main pass tab:** [lib/features/pass/presentation/pass_screen.dart](lib/features/pass/presentation/pass_screen.dart)
  - Shows compact `MemberPassCard` + search field + crew list
  - All data from `mock_data.dart`

- **Card widget:** [lib/core/widgets/member_pass_card.dart](lib/core/widgets/member_pass_card.dart)
  - Props: `profile: UserProfile`, `compact: bool`
  - Uses `lib/data/models/user_profile.dart` shape (`name`, `username`, `memberId`)
  - Logo: `AssetPaths.nuvoLogo` (trans.png on dark navy bg — correct)
  - QR data: `profile.memberId`

---

## 8. Existing Profile Screen

**File:** [lib/features/profile/presentation/profile_screen.dart](lib/features/profile/presentation/profile_screen.dart)

- Hardcoded to `currentUser` from `lib/data/mock_data.dart`
- Hardcoded avatar initials `'AK'`
- Static stats grid (wins, active races, streak, proofs submitted) — not from model
- Achievements row — hardcoded strings
- Settings rows: Edit profile, Notifications, Privacy, Sign out — all non-functional
- "Replay onboarding demo" button → `/welcome`
- No Riverpod consumer; no real user state

---

## 9. Existing Mock Data / Models

**Mock data:** [lib/data/mock_data.dart](lib/data/mock_data.dart)
- `currentUser: UserProfile` (name: 'Akshay', username: '@AKSHAY', memberId: 'NUVO-AKSHAY-4821')
- `friends: List<Friend>` — 5 hardcoded friends
- `races: List<Race>` — 3 hardcoded races
- `raceIdeas: List<String>` — 6 race title suggestions

**IMPORTANT — Duplicate UserProfile models exist:**

| File | Fields |
|---|---|
| [lib/data/models/user_profile.dart](lib/data/models/user_profile.dart) | `name`, `username`, `memberId` — simple, used by mock_data + MemberPassCard |
| [lib/core/models/user_profile.dart](lib/core/models/user_profile.dart) | `id`, `name`, `username`, `phone`, `wins`, `losses`, `streakDays`, `badges` — richer, `avatarInitials` getter |

The richer `core/models/user_profile.dart` appears to be the intended future model. The `data/models/user_profile.dart` is the current live one used everywhere. This divergence must be resolved in Phase 2.

---

## 10. Current Bottom Nav Implementation

**File:** [lib/core/widgets/bottom_nav.dart](lib/core/widgets/bottom_nav.dart)

Custom widget `NuvoBottomNav`:
- Floating rounded pill container (white bg, navy border 1.4px, navy drop shadow)
- 4 items: Arena (grid icon), Pass (badge icon), Compete (add_circle icon), Profile (person icon)
- Selected state: icy blue bg pill, blue icon/text, scale 1.04
- Unselected: transparent bg, muted color

**Shell:** [lib/features/shell/presentation/main_shell.dart](lib/features/shell/presentation/main_shell.dart)
- `ShellRoute` pattern in go_router
- Path array `['/arena', '/pass', '/compete', '/profile']`
- Index derived from current URI path via `_indexFor()`

---

## 11. Current iOS Bundle / Config Notes

**File:** [ios/Runner/Info.plist](ios/Runner/Info.plist)

- Display name: `Nuvo`
- Bundle name: `nuvo`
- Bundle ID: **`com.example.nuvo`** — must be changed before App Store / TestFlight
- Supports portrait + landscape (landscape left/right listed) — but Flutter locks to portrait-up in `main.dart`
- `UIApplicationSupportsMultipleScenes: false`
- SceneDelegate pattern (Swift)
- No push notification entitlements in plist yet
- No `NSCameraUsageDescription` or `NSPhotoLibraryUsageDescription` (needed for profile photo in future)
- No `NSUserNotificationsUsageDescription`
- App launcher icon configured via `flutter_launcher_icons` → `assets/branding/aura_goat.png`

---

## 12. Backend / Server Folder

**Phase 2 complete.** `server/worker/` now exists.

```
server/
  worker/
    src/
      index.ts              # Hono app, CORS, route mounts, /health
      types.ts              # AppEnv, all D1 row interfaces
      routes/
        auth.ts             # /auth/* (email, google, refresh, logout, me, account)
        profile.ts          # /profile/me, /profile, /profile/username/check
        pass.ts             # /pass/me
      lib/
        crypto.ts           # generateId, generateOtp, hashValue, generateRefreshToken, generateMemberId
        jwt.ts              # signJwt, verifyJwt, requireAuth middleware
        google.ts           # verifyGoogleIdToken (tokeninfo endpoint)
        resend.ts           # sendVerificationCode (Resend API)
        response.ts         # ALLOWED_WEB_ORIGINS, SHARE_BASE_URL constants
        validation.ts       # normalizeEmail, isValidEmail, normalizeUsername, isValidUsername
    migrations/
      0001_initial.sql      # All 7 tables + 13 indexes (applied locally ✅)
    package.json
    tsconfig.json
    wrangler.toml           # Worker name: nuvo-api, D1 binding: DB
    .dev.vars.example
    .gitignore
    README.md
```

Worker name: `nuvo-api`  
D1 binding: `DB` → `nuvo_db`  
Auth methods: email OTP (Resend) + Google Sign-In  
Token stack: HMAC-SHA256 JWT (15 min) + refresh token (30 days, hash-stored)

---

## 13. Exact Files Likely Needed for Auth

### New files to create:
```
lib/features/auth/
├── application/
│   └── auth_provider.dart              # Riverpod provider(s) for auth state
├── data/
│   └── auth_repository.dart            # HTTP calls to Cloudflare Worker
└── domain/
    └── auth_state.dart                 # AuthState enum/sealed class

lib/core/models/user_profile.dart       # Already exists — this is the target model
server/                                 # Cloudflare Worker (new directory)
    └── src/
        └── index.ts (or .js)
```

### Existing files to modify:
```
lib/app/router.dart                     # Add redirect guard + refreshListenable
lib/features/auth/presentation/phone_auth_screen.dart   # Wire up real SMS call
lib/features/auth/presentation/otp_screen.dart          # Wire up real OTP verify
lib/features/onboarding/presentation/secure_account_screen.dart  # Replace browser redirect
lib/features/onboarding/presentation/create_identity_screen.dart # Pass data forward
lib/features/onboarding/presentation/onboarding_screen.dart      # Remove hardcoded "AK"
lib/features/onboarding/presentation/member_pass_screen.dart     # Use real user state
lib/features/pass/presentation/pass_screen.dart                  # Use real user state
lib/features/profile/presentation/profile_screen.dart            # Use real user state
lib/data/mock_data.dart                 # currentUser must be replaced with real state
lib/data/models/user_profile.dart       # Consolidate into core/models/user_profile.dart
```

---

## 14. Exact Files That Should NOT Be Touched

```
# Design system — do not alter
lib/core/theme/app_colors.dart
lib/core/theme/app_text_styles.dart
lib/core/theme/app_shadows.dart
lib/core/theme/app_gradients.dart
lib/core/theme/app_theme.dart

# Reusable widgets — do not break APIs
lib/core/widgets/bottom_nav.dart
lib/core/widgets/member_pass_card.dart
lib/core/widgets/nuvo_button.dart
lib/core/widgets/otp_input.dart
lib/core/widgets/pressable_scale.dart
lib/core/widgets/arena_card.dart
lib/core/widgets/friend_card.dart

# These screens are done and should stay as-is
lib/features/splash/presentation/splash_screen.dart
lib/features/welcome/presentation/welcome_screen.dart
lib/features/shell/presentation/main_shell.dart
lib/features/arena/presentation/arena_screen.dart
lib/features/compete/presentation/compete_screen.dart

# Assets
assets/branding/trans.png
assets/images/

# iOS config (except bundle ID update)
ios/Runner/Info.plist
ios/Runner/AppDelegate.swift
```
