# Data Processor / Service Inventory

Census of every external service that receives Nuvo user data, verified against `server/worker/src/`, `pubspec.yaml`, website source, and wrangler config. "Processor" = data leaves Nuvo infrastructure to them. On-device SDKs that never transmit to the vendor are listed separately.

## Active processors

| Service | Data sent | Purpose | Where in code | Prod/Dev | In Privacy Policy? | Deletion considerations |
|---|---|---|---|---|---|---|
| **Cloudflare** (Workers + D1 + R2) | All backend data: accounts, auth, profiles, races, proofs, photos, motion artifacts, notifications, device tokens, reports | API hosting, database, object storage | `server/worker/` entire Worker; `wrangler.toml` D1 `nuvo_db`, R2 bucket | Both (env `dev`/`prod`) | YES (§7) | Covered by Worker deletion code — D1 deletes + `r2.delete` calls |
| **Resend** (`api.resend.com`) | Recipient email address (+ sign-in code content) | Delivers one-time sign-in codes and account emails | `server/worker/src/lib/resend.ts` `sendVerificationCode`; secrets `RESEND_API_KEY`, `RESEND_FROM_EMAIL` | Both | YES (§7) | None — Resend sees the address transiently; our copy of codes is purged ≤24h |
| **Apple — Sign in with Apple** | Apple `sub` identifier, email (or private relay), name if provided | Authentication | `lib/` `sign_in_with_apple` package → `POST /auth/apple` → token verify `appleid.apple.com` | Both | YES (§3.1, §7) | `auth_identities` row deleted on account deletion; user can also revoke Nuvo in Apple ID settings |
| **Apple — APNs** | Push payloads + device tokens (via FCM relay) | Push delivery | `firebase_messaging` → FCM → APNs; tokens in `device_tokens` | Both (requires portal capability + APNs key) | YES (§3.4, §7) | `device_tokens` rows deleted on logout/delete |
| **Google — Sign In** | Google `sub`, email, verified-email flag, name, avatar URL | Authentication | `google_sign_in` package → `POST /auth/google` → Google token verify | Both | YES (§3.1, §7) | `auth_identities` row deleted on account deletion |
| **Google — FCM** (`firebase_core`/`firebase_messaging`) | Device push token, push payloads, app-instance metadata | Push delivery | `lib/` `firebase_messaging`, `GoogleService-Info.plist`, `device_api.dart` registers tokens with Worker | Both — `GoogleService-Info.plist` present, service live | YES (§3.4, §7) | `device_tokens` deleted on logout/delete; unregister called client-side |
| **Google — Apps Script** (website only) | Waitlist name + email, feedback submissions | Website waitlist/feedback forms | `nuvo site` waitlist + feedback + NC State signup functions → `script.google.com` exec URL | Website | YES (§7) | Website data, not app account data; waitlist rows are Google Sheet–side — manual cleanup if needed |

## On-device SDKs — NOT processors (no data leaves device to vendor)

| SDK | Use | Why not a processor |
|---|---|---|
| `google_mlkit_pose_detection` + `camera` | On-device pose landmark extraction for AI Motion Proof | Inference is on-device; frames never leave the phone via ML Kit |
| `onnxruntime` | On-device model inference (custom pose teaching) | Local inference only |
| `flutter_secure_storage` | Keychain storage for tokens | Local storage only |
| `rive`, `flutter_animate`, `shimmer`, `cached_network_image`, `google_fonts` | UI/animation/image caching/fonts | `cached_network_image`/`google_fonts` make network fetches for assets only — note: fonts are bundled per google_fonts config; verify no runtime font fetch leaks device info at submission |

## Removed / dormant

- No Twilio/SMS path exists.
- No analytics SDK (no Amplitude/Mixpanel/Sentry) — confirmed in `pubspec.yaml`.
- No crash reporter — no Crashlytics/Sentry.
- Wikimedia image URL on the NC State site section is a static asset fetch, not a processor.

## Founder/attorney notes

- FCM + APNs relay means push payloads transit Google and Apple — disclosure covers this.
- Resend DPA: confirm a data-processing agreement is in place for production email (routine; flag for ops checklist).
- Google Apps Script waitlist lives outside the app's data lifecycle — if waitlist entries should be deletable on request, that's a manual Sheet process today.
