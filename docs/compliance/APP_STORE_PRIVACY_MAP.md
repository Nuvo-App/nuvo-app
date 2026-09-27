# App Store Connect — Privacy Answer Sheet

Scope: Nuvo iOS app (`net.getnuvo.app`). Source of truth: current Worker + Flutter implementation, migrations 0036–0038, `ios/Runner/PrivacyInfo.xcprivacy`. Use this sheet when filling App Store Connect's App Privacy form by hand. **Do not submit automatically.**

## Tracking

- **Does Nuvo track users?** **No.**
- No advertising SDKs, no IDFA usage, no data shared with data brokers, no cross-app/site linking for advertising or measurement. `NSPrivacyTracking = false` in the privacy manifest.

## Collected data — App Store Connect categories

| ASC category | Collected? | Linked to user? | Used for tracking? | Purposes | Maps to |
|---|---|---|---|---|---|
| **Contact Info → Email Address** | YES | Yes | No | App Functionality; Account Management (in ASC: "App Functionality" covers authentication; select Developer Communications only if we email users product messages — we send sign-in codes, which is App Functionality) | `users.primary_email`, `auth_identities`, `email_codes` |
| **Contact Info → Name** | YES | Yes | No | App Functionality | `profiles.full_name` |
| **Identifiers → User ID** | YES | Yes | No | App Functionality | `users.id`, Apple `sub`, Google `sub` |
| **Identifiers → Device ID** | YES | Yes | No | App Functionality | `device_tokens` (push token registration) |
| **User Content → Photos or Videos** | YES | Yes | No | App Functionality | Profile photos + proof photos (`media_objects`, R2) |
| **User Content → Other User Content** | YES | Yes | No | App Functionality | Race text, move notes, reactions, reports, profile username |
| **Health & Fitness → Fitness and Exercise** | YES | Yes | No | App Functionality; Analytics | Pose landmarks (motion-point data, consent-gated) + race activity data |
| **Usage Data → Product Interaction** | YES | Yes | No | App Functionality; Analytics | Screen/feature use, verification metadata |

## Categories NOT collected (answer "No")

- Contact Info → Phone Number, Physical Address, Other Contact Info
- Health & Fitness → Health (no health records)
- Financial Info (no payments, no IAP)
- Location (precise or coarse — never requested; photo EXIF is stripped on upload)
- Sensitive Info
- Contacts (no address-book access)
- User Content → Emails or Text Messages, Gameplay Content (no), Audio Data (no audio upload), Customer Support content (email support is outside the app — optional; answer Yes to "Customer Support" content only if ASC forces it — email correspondence happens outside the app)
- Browsing History, Search History
- Identifiers → nothing beyond User ID / Device ID
- Usage Data → Advertising Data
- Diagnostics → Crash Data, Performance Data (no crash/analytics SDK)
- Other Data → only if ASC requires a catch-all — motion consent flags/version/timestamps are covered under Product Interaction / Other User Content; do not add "Other Data Types" unless a reviewer asks.

## Linked vs not-linked reasoning

Everything server-side is keyed to `users.id`, so all collected categories are **linked** — there is no anonymous collection path. Do not mark anything unlinked.

## Optional/consent-gated nuance

- **Photos** and **Fitness and Exercise (pose landmarks)** are optional features, but ASC asks about data the app *can* collect — answer Yes for both.
- Pose landmarks only flow when the user opts in via "Help improve Nuvo" AND has passed the age-eligibility confirmation. ASC has no "consent-gated" flag; the nutrition label still says Collected.
- Purpose detail for the free-text "Data used for other purposes" section if asked: *Motion-point data is used only to improve and train Nuvo's own motion-verification models. It is encrypted, pseudonymized (no email/name/username inside artifacts), purged after ~90 days, and never sold or shared for advertising.*

## Privacy manifest (`PrivacyInfo.xcprivacy`) result

Matches this sheet: 8 collected types (email, user ID, name, photos/videos, fitness, other user content, device ID, product interaction), all linked, none tracking. Required-reason APIs declared: UserDefaults (CA92.1), FileTimestamp (C617.1), SystemBootTime (35F9.1) — the categories Flutter/plugins actually touch. Third-party SDKs (Firebase, Google Sign-In, ML Kit, camera, image_picker, onnxruntime, rive, flutter_secure_storage) ship their own manifests via their packages; confirm presence at archive time.

## Required policy URLs

- Privacy policy: `https://getnuvo.net/privacy`
- Privacy choices / account deletion: `https://getnuvo.net/delete-account`
- Terms: `https://getnuvo.net/terms`
