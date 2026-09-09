# Turning on push (phase F completion)

Everything is wired — the code paths, the worker sender, the client
`PushService`, the permission UX, the tap routing. Push is **dormant** until the
credentials below exist. None of this needs a code change; it is account setup.

## 1. Firebase project
1. Create a Firebase project (or reuse one). Add an **iOS app** with bundle id
   `net.getnuvo.app` and an **Android app** with package `net.getnuvo.app`.
2. Download **`GoogleService-Info.plist`** → `ios/Runner/GoogleService-Info.plist`
   (add it to the Runner target in Xcode).
3. Download **`google-services.json`** → `android/app/google-services.json`, and
   apply the `com.google.gms.google-services` Gradle plugin (standard Firebase
   Android steps).
4. `PushService` calls `Firebase.initializeApp()` — once the plist is in the
   bundle it stops throwing and `isAvailable` becomes true. No code change.

## 2. APNs (iOS)
1. Apple Developer portal → Keys → create an **APNs Auth Key** (`.p8`).
2. Firebase → Project settings → Cloud Messaging → upload the `.p8` with its
   Key ID + your Team ID (`W62869AF7L`).
3. Apple Developer portal → App ID `net.getnuvo.app` → enable the
   **Push Notifications** capability. (`aps-environment` is already in
   `ios/Runner/Runner.entitlements`.)

## 3. Worker secrets
The worker's FCM sender (`server/worker/src/domain/push.ts`) is off until BOTH
are set:

```
cd server/worker
wrangler secret put FCM_PROJECT_ID        # the Firebase project id
wrangler secret put FCM_SERVICE_ACCOUNT   # the full service-account JSON
                                          # (Firebase → Project settings →
                                          #  Service accounts → Generate key)
wrangler deploy
```

`pushConfigured(env)` then returns true and `sendPush` starts delivering.
Nothing else changes — `safeEmit` already calls it off the response path.

## 4. Verify
- Fresh install → join a race via an invite → the OS permission prompt appears
  (contextual, not on launch).
- `device_tokens` gets a row for the user.
- Have someone else submit proof that passes you (or accept your crew request);
  a push arrives; tapping it opens the right screen via the same
  `NuvoDestination` router the in-app inbox uses.
- A stale token → FCM 404/UNREGISTERED → the worker sets `disabled_at`.

## Remaining (not push, but same portal visit)
- Apple portal → App ID → enable **Associated Domains** (for universal links;
  `applinks:nuvo-api.getnuvoapp.workers.dev` is already in the entitlements).
- Android: put the **release keystore's SHA-256** into the worker's
  `androidAssetLinks()` (`server/worker/src/lib/wellKnown.ts`) and redeploy.
- Replace the App Store id placeholder in `lib/wellKnown.ts` +
  `ios/Runner/Info.plist` (`apple-itunes-app` is on the web fallback).
