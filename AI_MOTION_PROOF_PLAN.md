# AI Motion Proof Plan

## Goal
- Live iPhone camera proof.
- On-device pose detection.
- Jumping jack rep counting.
- No video upload in v1.
- Submit verified result to existing proof system.

## Existing App Integration Points
- Existing submit proof screen: `lib/features/races/presentation/submit_proof_screen.dart` currently posts manual proof through `RaceController.submitProof`.
- Existing race repository/controller: `RaceController`, `RaceRepository`, and `RaceApi` already return a refreshed `Race` after proof submission.
- Existing backend proof endpoint: `POST /races/:id/proof` in `server/worker/src/routes/races.ts`.
- Existing D1 proof fields: `proof_type`, `note`, `value`, `verification_status`, `verification_summary`, `reviewed_by`, `reviewed_at`, `created_at`; AI motion v1 adds result metadata fields without storing video.

## New Flutter Files
- `lib/features/races/data/ai_motion_models.dart` for Nuvo-owned activity, status, result, and pose frame models.
- `lib/features/races/ai/pose_detector_service.dart` for camera frame to ML Kit pose to Nuvo pose frame conversion.
- `lib/features/races/ai/jumping_jack_counter.dart` for the closed to open to closed rep state machine.
- `lib/features/races/ai/push_up_counter.dart` as a non-primary experimental scaffold.
- `lib/features/races/presentation/ai_motion_proof_screen.dart` for setup, camera, recording, processing, result, and submit states.

## Backend Changes
- Extend `POST /races/:id/proof` to accept `proofType: ai_motion`.
- Store AI activity, detected value, target value, confidence, validator version, frame counts, and duration.
- Only update progress automatically when the AI verification status is `ai_verified`.
- Preserve existing manual proof behavior and owner review behavior.
- Add a safe additive D1 migration for proof metadata columns.

## iPhone Requirements
- Use `camera` for portrait iPhone camera preview and image stream.
- Use `google_mlkit_pose_detection` for on-device pose detection.
- Add `NSCameraUsageDescription` with Nuvo motion proof copy.
- Keep microphone permission out of v1.
- Keep camera and pose detector disposal explicit so the camera stops when leaving the screen.

## Detection Logic
- Primary supported activity: 10 jumping jacks.
- Normalize pose landmarks into `NuvoPoseFrame` before counting.
- Require critical wrist, shoulder, hip, and ankle points.
- Count only stable `closed -> open -> closed` transitions.
- Confidence is based on valid frame ratio, target completion, and invalid frame rate.

## Failure States
- Camera permission denied.
- No camera available.
- Camera initialization or stream failure.
- Pose detector failure.
- Full body not visible or missing critical landmarks.
- Too few valid pose frames.
- Target not reached.
- Backend submit failure.
- User exits while camera or processing is active.

## Known Limitations
- No stored video proof yet.
- No server-side AI verification yet.
- Jumping jack detection requires full body visible.
- Push-up detection is scaffolded only and is not part of the primary v1 demo flow.

## Live Demo UX Update - 2026-06-19
- AI Motion Proof is treated as production-ready only for 10 jumping jacks in the UI.
- Compete and onboarding now route users toward a real 10 Jumping Jacks AI Motion Proof race.
- Submit Proof gates the working AI path to supported AI races and keeps manual proof primary for unsupported activities.
- The camera screen now includes a setup card, target/detected status, full-body guide overlay, body visibility copy, and bottom SafeArea CTAs.
- The camera preview is fitted with natural aspect-ratio handling instead of fill-style stretching.
- The screen no longer says `Ready` before body visibility is actually observed during recording.
- Raw debug metrics are removed from the user-facing AI Motion Proof UI.
- Physical iPhone release QA is still required for camera crop, CTA clipping, and actual demo-room setup distance.

## Camera UI Polish Update - 2026-06-19

- Replaced ListView body with SafeArea Column + Expanded — camera stage now fills available vertical space dynamically instead of being fixed at 268dp.
- Back button moved to top-left inline with title in a compact Row header — no longer floats centered above a stacked title block.
- Header is now compact: back button left | "AI Motion Proof" titleLarge + "Verify 10 jumping jacks live." bodySmall subtitle right — saves ~24dp of vertical space.
- Camera stage height is now responsive (Expanded fills remaining space after header and optional setup card), eliminating the dead blank gap between camera and CTA on all iPhone sizes.
- Recording HUD updated: shows "Target reached — tap Done" when `_counter.detectedReps >= 10`, otherwise "Detected: X / 10".
- Top-left camera pill updated: shows green "10 / 10" at target, red "Recording" during recording, blue "Target: 10 reps" in setup/ready.
- Visibility pill (top-right) updated: "Frame body" (ready), "Tracking" (recording + body visible), "Full body needed" (recording + not visible), "Target reached" (recording + target hit).
- _statusPanel() removed. Replaced by compact _statusHint() — smaller card (10dp vertical padding), shown only for cameraReady / error / processing states. Hidden during recording (in-camera HUD covers it) and setup (setup card covers it).
- Result panels (Verified / Try again) now use Center + mainAxisSize.min Column — fill the Expanded stage gracefully on all screen sizes instead of being a small top-aligned card.
- AI detection logic, counter thresholds, pose detector, frame handler, and all backend submit logic are unchanged.
## Demo Social + AI Update - 2026-06-19

- Typed race parsing now detects Jumping Jacks, Squats, High Knees, Arm Raises, and Plank Hold.
- AI Motion Proof now uses a validator registry instead of a hardcoded jumping-jack-only screen.
- Push-ups remain unsupported/manual.
- Proof payloads include activity type and validator metadata.

## Demo Social + AI Checklist
- [x] User can type "10 squats"
- [x] User can type "20 high knees"
- [x] User can type "10 arm raises"
- [x] User can type "20 second plank"
- [x] Supported movements show AI Motion Proof available
- [x] Unsupported movements stay manual
- [x] Quick starts use the same parser
- [x] Jumping jacks still routes through AI Motion Proof
- [x] No fake AI for unsupported movements
- [x] AI proof screen labels match selected movement
- [x] Proof submits with correct activity type
- [ ] Physical movement detection validated on device
