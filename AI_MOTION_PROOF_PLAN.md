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
