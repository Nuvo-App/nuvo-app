# iOS Permission & Entitlement Audit

Source: `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj`, client usage in `lib/`.

## Purpose strings (Info.plist)

| Key | Current string | Why required | When requested | Actually used? |
|---|---|---|---|---|
| `NSCameraUsageDescription` | "Nuvo uses the camera so AI Motion Proof can verify your movement live and to take proof and profile photos. Camera video is not uploaded." | Live pose extraction for AI Motion Proof (frames processed on-device via ML Kit / ONNX); `image_picker` camera capture for proof + profile photos | On first use of AI Motion Proof or camera capture | YES — `camera`, `image_picker` |
| `NSPhotoLibraryUsageDescription` | "Nuvo uses your photo library so you can set a profile photo and attach proof photos to races." | `image_picker` gallery selection for profile + proof photos | On first gallery pick | YES — `submit_proof_screen.dart`, profile avatar flow |
| `NSPhotoLibraryAddUsageDescription` | **REMOVED** this pass | Nothing writes images to the photo library (no save-to-gallery code, no plugin) | — | NO — removed; unused purpose strings get flagged at review |

### Changes this pass

- Camera string rewritten: old copy said "record moves" which implied video recording; actual pipeline extracts pose landmarks on-device and does not upload camera video.
- Photo-library string expanded: proof photos can be picked from the gallery, not just profile photos.
- `NSPhotoLibraryAddUsageDescription` deleted — no code path saves to the library.
- No microphone key exists — correct; nothing records audio.

## Entitlements (Runner.entitlements)

| Key | Status | Notes |
|---|---|---|
| `com.apple.developer.applesignin` = Default | KEEP | Sign in with Apple is live (`sign_in_with_apple`, `POST /auth/apple`). |
| `com.apple.developer.associated-domains` = `applinks:nuvo-api.getnuvoapp.workers.dev` | KEEP | Universal links for invite URLs `/j/<token>`. Verify the `apple-app-site-association` file is served at that host before submission; `nuvo://` custom scheme works as fallback. |
| `aps-environment` | **REMOVED** this pass | Was hardcoded `development`, which would force sandbox APNs in App Store builds. The provisioning profile supplies `development`/`production` per signing type. Requires the Push Notifications capability enabled on App ID `net.getnuvo.app` — portal-side setup, not in this file. |

## Config-level flags

- `ITSAppUsesNonExemptEncryption = false` — KEEP. Only platform TLS/HTTPS + standard encryption primitives are used (motion artifact encryption uses standard crypto under a server-held master key). If encryption implementation changes, re-review export compliance.

## Third-party SDK manifests

Firebase, Google Sign-In, ML Kit, camera, image_picker, onnxruntime, rive, flutter_secure_storage ship `PrivacyInfo.xcprivacy` in their packages. Confirm they are present in the archive at submission (Xcode privacy report) — not something this repo controls.
