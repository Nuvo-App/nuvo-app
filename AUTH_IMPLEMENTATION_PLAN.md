# AUTH IMPLEMENTATION PLAN — Nuvo
Phase 1 output. Do not implement until approved.

---

## 1. Recommended Implementation Plan (Small and Surgical)

**Approach:** Phone number → OTP → Cloudflare Worker backend → JWT stored in Flutter secure storage → Riverpod auth state → router redirect guard.

No Firebase. No Supabase. No third-party auth SDK. Custom Cloudflare Worker only.

**Steps in order:**
1. Stand up Cloudflare Worker with `/auth/send-otp` and `/auth/verify-otp` endpoints
2. Add `flutter_secure_storage` and `http` (or `dio`) packages to `pubspec.yaml`
3. Create `AuthState` sealed class and `AuthRepository` (HTTP calls to Worker)
4. Create `authProvider` (Riverpod `StateNotifierProvider` or `AsyncNotifierProvider`)
5. Wire up `router.dart` redirect guard based on auth state
6. Connect `PhoneAuthScreen` → real `/auth/send-otp` call
7. Connect `OtpScreen` → real `/auth/verify-otp` call → save JWT → push to onboarding
8. Replace `SecureAccountScreen` browser-redirect placeholder with in-app phone auth flow
9. Create `CreateIdentityScreen` → pass name/username forward through onboarding (ephemeral state)
10. Replace `mock_data.currentUser` with real user from auth provider across profile/pass/member-pass screens
11. Update iOS bundle ID from `com.example.nuvo` to production value

---

## 2. Where the Cloudflare Worker Backend Should Go

**New directory at project root:**
```
server/
├── src/
│   └── index.ts          # Worker entry — /auth/send-otp, /auth/verify-otp, /users/:id
├── wrangler.toml          # Worker config (name, routes, KV bindings)
├── package.json
└── tsconfig.json
```

The Worker handles:
- Generating and storing OTP codes (Cloudflare KV with TTL)
- Sending SMS via a provider (Twilio or similar — to be decided)
- Issuing signed JWTs on successful verification
- Storing user profiles in Cloudflare D1 (SQLite) or KV

The Worker is the only backend. Flutter calls it directly over HTTPS.

---

## 3. Where Flutter Auth Files Should Go

```
lib/features/auth/
├── application/
│   └── auth_provider.dart              # Riverpod provider — exposes AuthState
├── data/
│   └── auth_repository.dart            # HTTP calls to Cloudflare Worker endpoints
└── domain/
    └── auth_state.dart                 # sealed class: unauthenticated | loading | authenticated(UserProfile)

lib/core/models/user_profile.dart       # Already exists — canonical model (id, phone, name, username, wins...)
lib/core/services/
    └── secure_storage_service.dart     # Wrapper for flutter_secure_storage (JWT read/write/delete)
```

No changes to `lib/data/models/user_profile.dart` — that model gets deprecated and callers migrate to `lib/core/models/user_profile.dart`.

---

## 4. Which Existing Screens Should Be Reused

| Screen | File | Reuse plan |
|---|---|---|
| PhoneAuthScreen | [lib/features/auth/presentation/phone_auth_screen.dart](lib/features/auth/presentation/phone_auth_screen.dart) | Keep UI as-is — wire `NuvoPrimaryButton.onPressed` to `authProvider.sendOtp(phone)` |
| OtpScreen | [lib/features/auth/presentation/otp_screen.dart](lib/features/auth/presentation/otp_screen.dart) | Keep UI as-is — wire verify button to `authProvider.verifyOtp(code)` |
| CreateIdentityScreen | [lib/features/onboarding/presentation/create_identity_screen.dart](lib/features/onboarding/presentation/create_identity_screen.dart) | Keep UI as-is — pass name/username to next screen via ephemeral provider or extra params |
| OnboardingScreen (profile) | [lib/features/onboarding/presentation/onboarding_screen.dart](lib/features/onboarding/presentation/onboarding_screen.dart) | Keep UI — remove hardcoded "AK" initials, read from ephemeral state |
| MemberPassScreen (onboarding) | [lib/features/onboarding/presentation/member_pass_screen.dart](lib/features/onboarding/presentation/member_pass_screen.dart) | Keep UI — replace `currentUser` with real user from `authProvider` |
| PassScreen | [lib/features/pass/presentation/pass_screen.dart](lib/features/pass/presentation/pass_screen.dart) | Keep UI — replace `currentUser` with real user from `authProvider` |
| ProfileScreen | [lib/features/profile/presentation/profile_screen.dart](lib/features/profile/presentation/profile_screen.dart) | Keep UI — replace `currentUser` and hardcoded stats with real data |

---

## 5. Which New Screens Are Needed

No new screens are required for auth. The existing phone/OTP screens cover the full auth flow.

The only screen that needs to change role is `SecureAccountScreen` — currently a dead-end that opens a browser. In Phase 2 it becomes the transition point from identity creation into actual auth. Options:

- **Option A (simpler):** Remove `SecureAccountScreen` entirely; after `CreateIdentityScreen` → go directly to `/auth/phone`.
- **Option B (preserve step):** Keep `SecureAccountScreen` but replace the browser-open CTA with `context.go('/auth/phone')`. The "demo mode" path can remain for development.

Option A is recommended — fewer screens, cleaner flow.

---

## 6. How Auth Should Connect to Onboarding

Proposed flow after auth:

```
/welcome
  ├── "Get started" → /onboarding/create-identity
  │     └── Continue → /auth/phone  (enter phone)
  │           └── Send code → /auth/otp  (verify)
  │                 └── Verified (new user) → /onboarding/profile
  │                       └── Continue → /onboarding/member-pass
  │                             └── Continue → /onboarding/add-crew
  │                                   └── Continue → /onboarding/first-race
  │                                         └── Done → /arena
  └── "I already have an account" → /auth/phone
        └── Verified (returning user) → /arena  (skip onboarding)
```

Router redirect logic:
- `authProvider` exposes `AuthState` (unauthenticated | authenticated)
- `router.dart` adds `redirect:` callback: unauthenticated users trying to access `/arena`, `/pass`, `/compete`, `/profile` are redirected to `/welcome`
- `refreshListenable` wired to auth state stream so router reacts on login/logout

Onboarding completion flag:
- After first-race screen, mark `onboardingComplete = true` in secure storage
- Router redirect checks both auth state AND onboarding flag to decide where to land

---

## 7. Package Additions Needed

```yaml
# Add to pubspec.yaml dependencies:
flutter_secure_storage: ^9.x       # JWT persistence (iOS Keychain, Android EncryptedSharedPrefs)
http: ^1.x                         # HTTP calls to Cloudflare Worker (or dio if preferred)
```

No other packages needed. All auth UI is already built with existing widgets.

**Do not add:**
- firebase_auth
- supabase_flutter
- amplify_auth_cognito
- Any other auth SDK

---

## 8. Risk List

| Risk | Severity | Note |
|---|---|---|
| Duplicate `UserProfile` model | Medium | `lib/data/models/user_profile.dart` and `lib/core/models/user_profile.dart` have different shapes. `MemberPassCard` depends on the simpler one. Must consolidate before wiring real user state. |
| `mock_data.currentUser` is used in 5+ screens | Medium | All need migrating to `authProvider` watch. Easy but must be done together to avoid partial state. |
| iOS bundle ID is `com.example.nuvo` | High | Must change to a real ID before TestFlight or push notifications. Requires Apple Developer account. |
| SMS provider not chosen | Medium | Cloudflare Worker needs Twilio (or equivalent) API key for OTP sending. Needs decision before backend work starts. |
| No `NSUserNotificationsUsageDescription` in Info.plist | Low | Not needed for SMS auth, but needed if push notifications are added later. |
| OTP screens have no input validation | Low | Both `PhoneAuthScreen` and `OtpScreen` currently navigate forward without any validation. Add basic validation when wiring real calls. |
| `SecureAccountScreen` has a hardcoded URL | Low | `https://nuvothrive.netlify.app` — remove or replace in Phase 2. |
| Onboarding data not persisted across steps | Low | Name/username entered in `CreateIdentityScreen` is not passed to `OnboardingScreen`. Need ephemeral Riverpod provider or go_router `extra` params to carry this forward. |
| No error handling in auth screens | Low | No error states exist in the current UI. Need to add error display to phone/OTP screens when real calls fail. |

---

## 9. Questions / Blockers

**Blocking before Phase 2 can start:**

1. **SMS provider decision** — Which service sends the OTP SMS? (Twilio is the standard; others: MessageBird, Vonage, AWS SNS.) Need an API key and account before the Worker can send real codes.

2. **Production bundle ID** — What should `CFBundleIdentifier` be? (`com.nuvo.app`? Something else?) Must be set before any iOS build that needs push or TestFlight.

**Not blocking (can decide during Phase 2):**

3. JWT expiry policy — How long should sessions last? (Suggested: 30-day refresh token, 1-hour access token.)

4. User data storage backend — Cloudflare KV (simple) vs D1 (relational, better for races/crew). Recommend D1 given the relational nature of races + crew.

5. Should `SecureAccountScreen` be removed or repurposed? (Recommendation: remove it, as noted in section 5.)

---

## Google Sign-In Status — 2026-06-19

**Current status: Code restored, gated by `const _kGoogleEnabled = false` in `welcome_auth_screen.dart`.**
**UI: Non-interactive "needs setup" row shown on welcome screen.**

All Flutter code layers are in place:
- `WelcomeAuthScreen` is `ConsumerStatefulWidget` with `GoogleSignIn()`, `_signInWithGoogle()`, loading/error states
- `AuthController.signInWithGoogle()` ✅
- `AuthRepository.signInWithGoogle()` ✅
- `AuthApi.signInWithGoogle()` ✅
- Server `POST /auth/google` ✅

To re-enable Google sign-in (two external steps + one line of code):
1. **Google Cloud Console** — Verify or create an iOS OAuth client for bundle ID `com.example.nuvo` (see `GOOGLE_OAUTH_FIX_PLAN.md`)
2. **Cloudflare Worker secret** — `wrangler secret put GOOGLE_IOS_CLIENT_ID` with value `626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4.apps.googleusercontent.com`
3. **Flutter** — Change `const _kGoogleEnabled = false;` → `const _kGoogleEnabled = true;` in `welcome_auth_screen.dart`

The `ios/Runner/Info.plist` `GIDClientID` and `CFBundleURLSchemes` are already correct and do not need changes.

See `GOOGLE_OAUTH_FIX_PLAN.md` for full diagnosis, test plan, and exact setup instructions.
