# Google OAuth Fix Plan

_Created: 2026-06-19_

---

## Current Bundle ID

| Item | Value |
|---|---|
| Flutter/Xcode bundle ID | `com.example.nuvo` (placeholder — set in `ios/Runner.xcodeproj/project.pbxproj`) |
| Info.plist `GIDClientID` | `626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4.apps.googleusercontent.com` |
| Info.plist `CFBundleURLSchemes` | `com.googleusercontent.apps.626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4` |
| `google_sign_in` package version | `^6.2.2` (in `pubspec.yaml` — not removed) |
| Backend `/auth/google` payload | `{ "idToken": "<Google iOS ID token string>" }` |
| Backend audience check | `info.aud !== expectedClientId` where `expectedClientId = c.env.GOOGLE_IOS_CLIENT_ID` |
| Worker secret expected | `GOOGLE_IOS_CLIENT_ID` — must be set via `wrangler secret put` |

---

## Problems Found

1. **Bundle ID mismatch risk** — The iOS bundle ID is the placeholder `com.example.nuvo`. Google Cloud Console iOS OAuth client `626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4` must be explicitly registered for this exact bundle ID. If it was registered for a different ID (e.g., `com.nuvo.app`), the `google_sign_in` SDK will reject sign-in at the iOS level before any backend call is made.

2. **Missing Cloudflare Worker secret** — `GOOGLE_IOS_CLIENT_ID` is not in `wrangler.toml` (not a `[vars]` entry) and must be set as a Worker secret via Wrangler CLI. Until set, the backend's `/auth/google` will fail the audience check for every token.

3. **Welcome screen Google code removed** — The prior session removed `google_sign_in` import, `GoogleSignIn()` instance, `_googleLoading`, `_googleError`, and `_signInWithGoogle()` from `welcome_auth_screen.dart`. This session restores them behind a `const _kGoogleEnabled = false` flag.

---

## External Setup Needed

### 1. Google Cloud Console

1. Go to [https://console.cloud.google.com](https://console.cloud.google.com) → select the Nuvo project
2. Navigate to **APIs & Services → Credentials**
3. Find or create an **OAuth 2.0 Client ID** with:
   - **Application type**: iOS
   - **Bundle ID**: `com.example.nuvo` ← must match exactly what's in Xcode
4. Copy the **iOS client ID** — it should be `626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4.apps.googleusercontent.com`
5. If the client was originally registered for a different bundle ID, either:
   - Create a new iOS client for `com.example.nuvo`, OR
   - Update the bundle ID in Xcode to match the registered client (and update `Info.plist` accordingly)

> **Fastest path for demo**: Create an iOS OAuth client in Google Cloud Console for bundle ID `com.example.nuvo`. The client ID number prefix `626823797899` suggests a project was already set up — just verify the iOS client exists for `com.example.nuvo`.

### 2. Cloudflare Worker Secret

Run in the `server/worker` directory:

```bash
cd server/worker
wrangler secret put GOOGLE_IOS_CLIENT_ID
```

When prompted, enter:
```
626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4.apps.googleusercontent.com
```

This is the value the backend uses for the `aud` (audience) check when verifying Google ID tokens.

### 3. Flutter Info.plist (already correct — verify only)

- `GIDClientID` = `626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4.apps.googleusercontent.com` ✅
- `CFBundleURLSchemes` = `com.googleusercontent.apps.626823797899-smfp1r0s99h2gaa9ov72cjchu0kesuq4` ✅

Both values are already correct in `ios/Runner/Info.plist`.

---

## Code Changes Needed

1. **Restore Google sign-in code in `welcome_auth_screen.dart`** — Done in this session behind `const _kGoogleEnabled = false`. Full code (imports, state, `_signInWithGoogle()`, conditional UI) is restored. Flip to `true` to enable.

2. **Flip the enable flag** — In `welcome_auth_screen.dart`:
   ```dart
   // Change this line:
   const _kGoogleEnabled = false;
   // To:
   const _kGoogleEnabled = true;
   ```

3. **No other code changes required** — `AuthApi.signInWithGoogle()`, `AuthRepository.signInWithGoogle()`, `AuthController.signInWithGoogle()`, and the backend `POST /auth/google` route are all fully implemented and correct.

---

## Test Plan

1. Complete both external setup steps above (Google Cloud Console + Cloudflare Worker secret)
2. Change `_kGoogleEnabled = true` in `welcome_auth_screen.dart`
3. Run `flutter run --release` on physical iPhone with bundle ID `com.example.nuvo`
4. Tap **Continue with Google** on the welcome screen
5. Verify native Google account picker opens
6. Select an account
7. Verify app receives ID token (no crash, no "sign-in failed" toast)
8. Verify backend `/auth/google` accepts the token (no 401)
9. Verify app navigates to Arena after successful sign-in
10. Verify sign-out works and re-entering via Google works

---

## Current Status

**Disabled** — showing non-interactive "Google sign-in — needs setup" row on welcome screen.

The `_kGoogleEnabled = false` constant in `welcome_auth_screen.dart` gates the interactive button. All code is in place. Only the two external steps (Google Cloud Console + Cloudflare Worker secret) are blocking.
