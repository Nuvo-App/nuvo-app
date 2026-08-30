# Nuvo UI Refinement and Camera-AI Migration Plan

Status: planning document — no runtime behavior is changed by this file.

Owner: Nuvo product and engineering team

Last reviewed: 2026-08-24

## 1. The decision in one page

Nuvo should not replace its current camera verifier with one general-purpose AI
model. “Verify anything with a camera” is not a single technical capability.
Different proof claims need different evidence:

| Proof claim | Best first tool | Final decision-maker |
|---|---|---|
| Repetitions, holds, body position | On-device pose landmarks | Nuvo movement validator |
| Presence or position of a physical object | On-device object detector/tracker | Nuvo object rule |
| Text, labels, QR codes, numbers | On-device OCR/barcode reader | Nuvo extraction + rule check |
| A custom item or movement | A versioned custom on-device model | Nuvo rule engine plus review fallback |
| Ambiguous scene explanation | Cloud multimodal model, if consented | Human review or explicit policy; never blind auto-approval |

The product should migrate from a “pose screen” to a stable **proof evidence
platform**. The user-facing UI should remain simple: tell the person what to
show, show whether the camera can read it, show what is being counted or
checked, and clearly separate verified, needs review, and not verified.

The current ML Kit pipeline remains the first production implementation. A
MediaPipe/LiteRT or native Vision migration should only replace one evidence
producer at a time after it beats the current baseline on a held-out test set.

## 2. Non-negotiable product principles

1. AI output is evidence, not truth. A model may say what it sees; Nuvo decides
   whether that satisfies the race’s proof requirement.
2. No silent success. A failed, uncertain, missing, or unsupported result must
   remain visibly non-verified.
3. No “universal verifier” prompt. The proof definition must specify the
   observable claim, required evidence, thresholds, duration, and failure
   behavior before a model is selected.
4. On-device first for live movement. This protects latency, privacy, and
   reliability. Cloud review is an escalation path, not the live counter.
5. Every verifier is versioned. Store the verifier type, model/runtime version,
   rule version, evidence summary, and decision reason with a proof.
6. UI never exposes debug internals to ordinary users. Debug values belong in
   developer tooling, QA fixtures, or an opt-in diagnostics surface.
7. A primary action is obvious on every screen. Remove controls that do nothing
   or duplicate another route.
8. UI polish and AI correctness are separate release gates. A beautiful camera
   screen cannot compensate for a verifier that has not been evaluated.

## 3. What Nuvo has today

The existing movement path is:

```text
camera
  -> camera image conversion
  -> google_mlkit_pose_detection
  -> landmark smoothing
  -> movement validator / custom-pose runtime
  -> NuvoVerifyOutput
  -> proof payload
  -> Worker review and scoring
```

Relevant ownership:

- `lib/features/races/presentation/ai_motion_proof_screen.dart` owns the live
  camera experience and lifecycle.
- `lib/features/races/ai/pose_detector_service.dart` owns the ML Kit bridge.
- `lib/features/races/ai/camera_image_converter.dart` owns platform frame
  conversion.
- `lib/features/races/ai/pose_landmark_smoother.dart` owns temporal smoothing.
- `lib/features/races/ai/motion_validators.dart` owns movement semantics,
  thresholds, confidence, states, and failure reasons.
- `lib/features/races/ai/custom_pose/` owns calibrated custom movement specs and
  runtime behavior.
- `lib/features/races/presentation/widgets/movement_demo.dart` is instructional
  UI only. It must never be treated as verification logic.

Do not move verifier behavior into widgets. Do not change proof API fields or
server scoring behavior as part of a visual refinement.

## 4. UI refinement dialogue

### Product: What should the user understand in five seconds?

**Answer:** “I am submitting proof for this race. The camera needs to see my
whole body or the requested item. When the check is complete, Nuvo will tell me
exactly what was verified.”

The screen should not ask a user to understand landmarks, FPS, confidence
percentages, model names, frame drops, or validator states.

### Design: What is the camera flow?

1. **Proof brief** — movement/object, target, and what the camera needs to see.
2. **Camera setup** — live preview with a simple framing guide.
3. **Readiness** — one clear state: “Move back”, “Improve lighting”, “Show your
   whole body”, or “Ready”.
4. **Verification** — count, hold timer, or evidence status; no competing
   controls.
5. **Result** — verified, needs review, or try again, with a reason and one
   primary next action.

### Design: What should the user see while the model works?

- A stable camera preview, not a rapidly changing debug overlay.
- A single progress indicator tied to the proof target.
- Short coaching copy that describes an action the user can take.
- A compact “What Nuvo is checking” disclosure for trust and accessibility.
- A persistent exit/back action that does not destroy an in-progress proof
  without confirmation.

### Design: What does every state need?

| State | User copy | Primary action |
|---|---|---|
| Camera loading | “Starting camera…” | None or Cancel |
| Permission denied | “Camera access is needed for this proof.” | Open settings / Use another proof |
| No body/item found | “Move the camera so your full body/item is visible.” | Adjust camera |
| Poor framing | “Move back so your whole body fits inside the guide.” | Adjust camera |
| Poor light | “Add more light and keep the camera steady.” | Adjust camera |
| Ready | “Ready” | Start |
| Verifying | “Keep going — 6 of 10” | Stop / Cancel |
| Completed | “Proof verified” | Submit proof |
| Uncertain | “Nuvo could not verify this clearly.” | Try again / Use another proof |
| Unsupported | “This proof type is not available yet.” | Choose another proof |
| Error | “Something went wrong. Your proof was not submitted.” | Retry |

### Design: What should disappear?

Remove or hide from normal users:

- raw confidence values;
- validator state names;
- debug landmark coordinates;
- model/runtime names;
- internal failure codes;
- technical frame-processing language;
- duplicate Start/Submit/Retry actions;
- controls that look interactive but do not change state.

These can remain behind a developer-only diagnostics flag and test fixtures.

## 5. UI refinement workstream

### Phase UI-0 — Inventory before editing

Create a screen inventory for Arena, Compete, Crew, Profile, Race Detail, Submit
Proof, and AI Motion Proof. For each screen record:

- the question the screen answers;
- its one primary action;
- loading, empty, error, success, and disabled states;
- shared components used;
- any route or API dependency;
- visual defects and user confusion;
- whether a control actually works.

Do not redesign the whole app in a single pass. Choose one screen, fix its
hierarchy and states, then move to the next.

### Phase UI-1 — Establish the visual contract

Use the existing `lib/core/theme/` and `lib/core/widgets/` tokens as the source
of truth. Before adding a component, search for an existing equivalent.

The contract should define:

- color roles, not ad hoc colors;
- typography roles;
- spacing scale;
- corner and elevation rules;
- primary/secondary/destructive button behavior;
- cards, rows, sheets, banners, and empty states;
- focus, pressed, disabled, error, and loading states;
- minimum touch targets and small-screen behavior;
- accessibility labels and contrast requirements.

### Phase UI-2 — Refine the camera proof surface

Keep the camera page focused on one task. Put advanced details behind an
optional diagnostics entry that is unavailable in production builds unless
explicitly enabled.

Use a design review checklist:

- Can a first-time user start without instructions from a developer?
- Is the camera framing guide understandable without text alone?
- Can the user recover from every failure state?
- Does the screen work on a small phone without clipped controls?
- Is the current count/time readable in motion?
- Does the result explain why it passed or did not pass?
- Does leaving the screen avoid accidental proof loss?

### Phase UI-3 — Visual regression

Add golden or screenshot coverage for each major state at at least:

- small Android/iPhone-sized viewport;
- large phone viewport;
- tablet or narrow landscape viewport;
- accessibility text scale where supported.

The test should catch clipped camera controls, unreadable contrast, overlay
collisions, and incorrect primary actions, not just widget existence.

## 6. Camera-AI options

### Option A — Keep ML Kit as the baseline

ML Kit provides real-time pose tracking with 33 landmarks and on-device
processing. It supports base and accurate models, and the app supplies the
semantic classification and repetition rules. This matches Nuvo’s current
architecture and minimizes migration risk.

Use it for:

- supported exercise repetitions;
- holds such as planks;
- basic full-body framing;
- first release of object and OCR proof where the ML Kit APIs fit.

Tradeoffs:

- pose detection itself does not know whether a movement is a valid push-up or
  whether a race target was satisfied;
- single-person and framing limitations must be surfaced in UI;
- the pose API is beta and the model's z coordinate is not metric 3D depth;
- new proof types still require Nuvo-owned rules and test data.

### Option B — MediaPipe Tasks + LiteRT

MediaPipe Tasks provides explicit image, video, and live-stream modes for pose
and object detection. LiteRT is the current on-device model runtime direction
for custom models. This is the strongest long-term path when Nuvo needs custom
movements, object-specific detectors, segmentation, or a shared model runtime.

Use it when:

- ML Kit cannot represent a required observation;
- a custom model has a measured advantage on Nuvo's test set;
- the same model behavior must be shared across Android and iOS through a
  controlled native bridge;
- the team is ready to own model assets, metadata, versioning, and native
  lifecycle code.

Tradeoffs:

- likely requires native platform integration or a carefully maintained Flutter
  plugin;
- live-stream callbacks can drop frames, so timestamps, backpressure, and
  lifecycle must be designed explicitly;
- model packaging and performance QA become Nuvo responsibilities.

### Option C — Apple Vision on iOS plus ML Kit on Android

Apple Vision provides native 2D body pose, 3D body pose on newer Apple systems,
object recognition with Core ML, text recognition, and image segmentation.
This can deliver strong iOS capabilities, especially for depth-aware experiences
on compatible hardware.

Tradeoffs:

- platform behavior diverges;
- iOS-only 3D or depth features cannot be treated as universally available;
- two model stacks increase QA, calibration, and support burden;
- a platform advantage must be reflected in proof policy, not hidden from users.

### Option D — Cloud multimodal model as an assistant

Cloud video-capable models can receive sampled image frames and describe scenes.
This is useful for explanation, moderation queues, OCR fallback, and ambiguous
evidence. It is not a good live repetition counter or sole authority for a
proof that changes a leaderboard.

Risks:

- latency, connectivity, and cost;
- privacy and consent for camera images;
- nondeterministic answers;
- no guarantee that a natural-language answer is a valid measurement;
- prompt/model changes can alter decisions.

If used, send a bounded evidence package and require structured output such as:

```json
{
  "observation": "string",
  "claim": "string",
  "evidence": ["string"],
  "decision": "verified|needs_review|not_verified",
  "reason": "string",
  "model_version": "string"
}
```

The backend must treat this as a review suggestion unless the proof policy
explicitly allows automated approval for that claim.

### Recommendation

Use a hybrid, staged architecture:

1. ML Kit remains the movement baseline.
2. Add an internal evidence abstraction around all camera observations.
3. Add object and OCR evidence producers only for explicitly defined proof
   types.
4. Evaluate MediaPipe/LiteRT as a replacement candidate for one weak movement
   or one custom object proof at a time.
5. Add cloud multimodal review only for bounded, consented ambiguity—not for
   automatic leaderboard truth.
6. Add Apple Vision capabilities only when a product requirement justifies
   platform divergence.

## 7. Target architecture

Do not make UI widgets call model-specific APIs directly. Introduce these
conceptual boundaries incrementally:

```text
CameraSource
  -> FrameScheduler
  -> EvidenceProducer
       - PoseEvidenceProducer
       - ObjectEvidenceProducer
       - TextEvidenceProducer
       - BarcodeEvidenceProducer
       - CloudReviewEvidenceProducer (optional)
  -> EvidenceNormalizer
  -> ProofPolicy / Verifier
  -> VerificationDecision
  -> ProofSubmission
```

The stable domain object should contain:

- proof ID and race ID;
- claim type and policy version;
- evidence type;
- observed values and time window;
- quality/readiness signals;
- decision: verified, needs review, not verified, or failed;
- human-readable reason;
- model/runtime version;
- privacy/consent and retention metadata;
- optional evidence reference, never uncontrolled raw camera retention.

The Worker remains the authority for accepted proof state and leaderboard
effects. Client-side verification is a candidate decision and UX signal; it
must not silently grant progress if the backend contract says otherwise.

## 8. Definition of “verify anything”

Before implementing a new proof, write a one-page proof specification:

1. What exact claim is being verified?
2. What can the camera actually observe?
3. What is the minimum acceptable framing and lighting?
4. What evidence producer is used?
5. What temporal window is required?
6. What thresholds and hysteresis prevent flicker?
7. What false-positive risk is acceptable?
8. What false-negative recovery is offered?
9. What happens when the result is uncertain?
10. Is automated approval allowed, or is review required?
11. What data is stored and for how long?
12. How will the claim be evaluated on real and hard-negative examples?

If those questions cannot be answered, the proof is not ready to add to Nuvo.

## 9. Evaluation and release gates

### Deterministic gates

- `flutter analyze --no-fatal-infos` passes with no new findings.
- All existing motion, custom-pose, and proof round-trip tests pass.
- Camera lifecycle tests cover permission, pause/resume, rotation, disposal,
  dropped frames, and re-entry.
- Every proof output has a valid decision, reason, policy version, and runtime
  version.
- A failed or uncertain verification cannot produce a verified leaderboard
  update.
- Worker contract and integration tests pass.

### Evidence quality gates

Build a versioned dataset for each verifier with:

- clean positives;
- partial-body and poor-framing examples;
- different lighting, clothing, body sizes, camera positions, and backgrounds;
- mirrored and rotated views;
- dropped-frame and jitter simulations;
- hard negatives that look similar but should fail;
- real-user samples with consent.

Report separately:

- false-positive rate;
- false-negative rate;
- readiness accuracy;
- median and p95 latency;
- battery/thermal cost;
- crash/error rate;
- human-review agreement;
- performance by device class and platform.

Do not collapse all of this into one confidence number. A verifier should not
ship if its false-positive rate is unacceptable even when average accuracy is
high.

### Human review gates

For each new verifier, humans review a stratified sample of accepted,
rejected, and uncertain cases. Reviewers should answer:

- Was the claim actually visible?
- Was the decision fair and repeatable?
- Did the UI give the user a reasonable way to recover?
- Would a teacher or crew member understand the result?

## 10. Migration sequence

### M0 — Freeze and baseline

- Freeze current movement semantics.
- Capture current latency, accuracy, failure reasons, battery impact, and crash
  behavior.
- Inventory UI states and duplicate components.
- Do not upgrade dependencies or rewrite the camera screen during this phase.

### M1 — UI foundation

- Fix the camera proof information hierarchy.
- Standardize loading, readiness, verifying, success, uncertainty, and error
  states.
- Add screenshot coverage for small devices.
- Keep the existing ML Kit runtime unchanged.

### M2 — Evidence contract

- Add versioned domain types for evidence and decisions in a scoped data/domain
  change.
- Keep the current pose validator behind the new boundary.
- Add logging that records policy/runtime versions without recording raw frames
  by default.

### M3 — Expand modalities one at a time

- Implement object proof only for one concrete object claim.
- Implement OCR/barcode proof only for one concrete text claim.
- Add policy-specific tests and a human review queue for uncertainty.

### M4 — Candidate runtime migration

- Benchmark MediaPipe/LiteRT against ML Kit on one movement or object.
- Do not switch production by model preference; switch only if the candidate
  meets the evidence gates and has an equal or safer failure path.
- Keep a rollback flag or server-selected policy version.

### M5 — Controlled cloud escalation

- Add explicit consent and a privacy notice before sending camera evidence off
  device.
- Sample only the minimum frames needed.
- Use structured responses and record model version.
- Route ambiguous results to review unless the proof policy explicitly permits
  automation.

### M6 — Production rollout

- Release to internal testers first.
- Roll out by proof type, not by replacing every verifier at once.
- Monitor decision distributions, retries, latency, crashes, appeals, and
  human-review disagreement.
- Roll back a single policy/model version without rolling back the whole app.

## 11. What future agents must not do

- Do not replace ML Kit, add MediaPipe, add LiteRT, or add a cloud model just
  because it sounds more advanced.
- Do not edit `motion_validators.dart`, the camera bridge, native files, the
  Worker, or dependencies during a UI-only task.
- Do not change thresholds without a fixture-backed evaluation report.
- Do not use `movement_demo.dart` as evidence or copy its animation logic into
  the verifier.
- Do not store raw camera frames by default.
- Do not expose model confidence as if it were proof truth.
- Do not make a cloud model's prose response directly alter a leaderboard.
- Do not add a new custom component before searching `lib/core/widgets/` and
  `lib/core/theme/` for an existing primitive.
- Do not merge a camera UI that has no loading, permission, uncertain, retry,
  and error states.

## 12. Required pre-release dialogue

Before a migration PR is approved, the author must answer:

**Product:** What exact proof claim is changing?

**UI:** What does the user see in loading, ready, verifying, verified,
uncertain, denied, and error states?

**Model:** What observations does the model produce, and what does it not know?

**Policy:** Which Nuvo-owned rule converts observations into a decision?

**Data:** What is stored, for what purpose, and for how long?

**Safety:** What prevents false positives from awarding progress?

**Evaluation:** Which positive, negative, device, lighting, framing, and
drop-frame fixtures were run?

**Rollback:** How can this proof type return to the previous runtime without a
full app rollback?

**Release:** Which focused and full checks passed, and what remains unverified?

If any answer is “we will figure it out after release,” the migration is not
ready.

## 13. Source notes

The recommendation is based on these current primary documentation sources:

- [Google ML Kit pose detection](https://developers.google.com/ml-kit/vision/pose-detection)
- [ML Kit pose detection on Android](https://developers.google.com/ml-kit/vision/pose-detection/android)
- [ML Kit pose classification and repetition](https://developers.google.com/ml-kit/vision/pose-detection/classifying-poses?authuser=2)
- [ML Kit object detection and tracking](https://developers.google.com/ml-kit/vision/object-detection?authuser=2)
- [MediaPipe Pose Landmarker on Android](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/android?authuser=2)
- [MediaPipe Pose Landmarker on iOS](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios)
- [MediaPipe Object Detector](https://ai.google.dev/edge/api/mediapipe/python/mp/tasks/vision/ObjectDetector)
- [Apple Vision framework](https://developer.apple.com/documentation/vision)
- [Apple 2D human body pose](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images)
- [Apple 3D human body pose](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)
- [Apple text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images?changes=_1)
- [Gemini Live API video input](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket)

## 14. Known limitations and open decisions

- No research source can establish Nuvo's acceptable false-positive rate; that is
  a product and fairness decision requiring real-user review.
- The current repo does not yet have a universal evidence abstraction; this
  document defines the target boundary, not an implemented API.
- MediaPipe/LiteRT migration cost and Flutter bridge details need a spike on
  supported Android/iOS versions before dependency changes are approved.
- Cloud camera evidence requires a privacy, consent, retention, and cost review
  before implementation.
- “Verify anything” must be narrowed into a prioritized proof catalog. Start
  with movement, object presence, and text/QR claims; do not promise arbitrary
  scene truth.
