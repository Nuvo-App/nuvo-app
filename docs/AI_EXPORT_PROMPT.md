# Nuvo — AI Export Prompt

Give this prompt to any AI assistant before asking it to work on the Nuvo Flutter / Cloudflare Worker codebase. It covers the product, architecture, conventions, guardrails, and day-to-day workflow.

---

## 1. What Nuvo is

Nuvo turns real-life goals into leaderboard races with your crew.

Core product loop:

```
Set a finish line → pull in your crew → submit proof → move the leaderboard
```

- A **race** is a shared leaderboard with a finish line, participants, proof, progress, and a winner/completion state. It is **not** a challenge, event, or quest.
- **Proof** is how a participant moves on the leaderboard. Types are: AI Motion Proof, manual, photo, note, link, and daily check-in.
- **Crew** is the people in a race or the user's social network.
- **AI Motion Proof** uses the on-device camera + ML Kit pose detection to verify supported movements live. It must use real `motion_validators.dart` results. Do not fake, mock, or short-circuit verification.

Full product language, screen ownership, race formats, and banned terms are in `docs/NUVO_PRODUCT_MODEL.md`. Read it before any product or UI work.

---

## 2. Tech stack

- **Frontend:** Flutter 3.x, Dart SDK `^3.12.2`
- **State management:** `flutter_riverpod`
- **Routing:** `go_router` v14 with a `ShellRoute` for bottom nav
- **Networking:** plain `http` + `flutter_secure_storage` for tokens
- **Auth:** email OTP + optional Google sign-in
- **Pose / camera:** `camera` + `google_mlkit_pose_detection`
- **Design tokens:** `NuvoColors`, `AppTextStyles`, `AppGeometry` in `lib/core/theme/`
- **Backend:** Cloudflare Worker + D1 in `server/worker/`
- **Backend language:** TypeScript, checked with `tsc --noEmit`

Key packages:

```yaml
flutter_riverpod, go_router, google_fonts, flutter_animate,
shimmer, qr_flutter, share_plus, url_launcher, image_picker,
image_cropper, http, flutter_secure_storage, google_sign_in,
camera, google_mlkit_pose_detection, intl, uuid
```

---

## 3. Project layout

```
lib/
  app/               → router.dart, app.dart
  core/              → theme tokens, widgets, utilities
  data/              → old/orphaned models (avoid adding here)
  features/
    arena/           → next-move board
    auth/            → email OTP, auth gate, secure token store
    compete/         → start/join race
    onboarding/      → identity, member pass, add crew
    pass/            → member pass / QR (bottom nav "Crew" tab)
    profile/         → identity, race record, settings
    proof/           → standalone proof view
    race_detail/     → leaderboard room
    races/           → creation, invite, proof, AI motion, settings
    shell/           → main bottom nav shell
    splash/
    welcome/         → (orphan, not routed)
  main.dart

server/worker/
  src/               → routes, domain, types
  migrations/        → D1 SQL
  test/              → backend tests

docs/                → product model, app map, backend audit, this prompt
```

Screen-to-route map is in `docs/CURRENT_APP_MAP.md`.

---

## 4. Product language you must use

Use:
- `race`, `crew`, `proof`, `progress`, `leaderboard`, `start line`, `finish line`, `submit proof`, `pull in your crew`, `arena`, `member pass`, `AI Motion Proof`, `invite code`

Never use:
- `challenge`, `event`, `journey`, `unlock`, `discover`, `coming soon`, `needs setup`
- `betting`, `gambling`, `crypto`, `payment`, `payout`, `sponsor`, `investor`
- `SMS`, `Twilio`, `Firebase`, `Supabase`

If you see these in UI copy, replace them or flag them for removal.

---

## 5. Guardrails — do not touch without explicit approval

These files/areas are high-risk and can break the demo, session, or backend:

- `lib/features/auth/data/auth_api.dart`, `auth_repository.dart`, `auth_controller.dart`, `auth_gate.dart`, `secure_token_store.dart`
- `lib/features/races/ai/motion_validators.dart`
- `lib/features/races/ai/pose_detector_service.dart`, `camera_image_converter.dart`
- `lib/features/races/presentation/ai_motion_proof_screen.dart`
- `lib/features/races/data/race_api.dart` (backend contract)
- `lib/features/races/data/race_repository.dart` (token injection)
- `lib/features/races/presentation/race_controller.dart` (shared state provider)
- `ios/Podfile`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist`
- `pubspec.yaml`, `pubspec.lock` (do not add/upgrade packages)
- `server/worker/` (backend schema + D1)

Read `docs/BASELINE_BEFORE_PRODUCT_SKELETON.md` for the list of currently working and known-broken areas.

---

## 6. Safe cleanup work (pre-approved)

- Replace "coming soon" strings with neutral copy or remove dead tiles.
- Delete confirmed-orphaned Dart files (verify zero imports with `grep`).
- Replace inline `Color(0x...)` values with `NuvoColors` tokens.
- Add curly braces to the 4 `if` statements in `auth_controller.dart`.
- Deduplicate `_kApiBase` into a shared constants file.

---

## 7. Workflow for every task

1. **Read first.** Before product or UI changes, read:
   - `docs/NUVO_PRODUCT_MODEL.md`
   - `docs/BASELINE_BEFORE_PRODUCT_SKELETON.md`
   - `AGENTS.md`
2. **Declare the task.** For any broad edit (more than 2 files or any UI/logic change), state:
   - Files to read
   - Files to edit
   - Behavior changes
   - What will NOT change
   - Risk level (low / medium / high)
   Wait for explicit approval for medium/high risk before editing.
3. **Make small, scoped changes.** Do not redesign the full app in one pass. Do not add screens, routes, or APIs unless explicitly asked.
4. **Verify.** After any Flutter change:
   ```bash
   flutter analyze --no-fatal-infos
   ```
   After any backend change:
   ```bash
   cd server/worker && npm run typecheck
   ```
5. **Run targeted tests.** Relevant test suites:
   ```bash
   flutter test test/pose_calibration_test.dart
   flutter test test/custom_pose_sequence_builder_test.dart
   flutter test test/custom_pose_sequence_runtime_test.dart
   ```
6. **Save learned info.** If you discover build/test commands, conventions, or user preferences that are not documented, append them to `AGENTS.md` or create one in the current directory.
7. **Git.** Do not commit or push unless explicitly asked. If you do commit, never update git config, never force-push, and do not include secrets.

---

## 8. How to build and run

```bash
# Get dependencies
flutter pub get

# Analyze
flutter analyze --no-fatal-infos

# Run tests
flutter test

# Run on an iOS simulator or device
flutter run

# Release build on a physical iPhone
flutter run --release

# Backend typecheck
cd server/worker && npm run typecheck
```

If a build breaks, you can recover the last known working state with:

```bash
git checkout demo-working-before-product-skeleton
```

---

## 9. Code conventions

- Use `NuvoColors.*`, `AppTextStyles.*`, and `AppGeometry.*` for UI. Do not hardcode `Color(0x...)` values.
- Use `NuvoPrimaryButton`, `NuvoOutlineButton`, `NuvoBackButton` from `core/widgets/nuvo_button.dart`.
- Keep UI copy in Nuvo product language.
- Keep debug UI behind `kDebugMode` checks.
- Do not add or remove comments unless asked. Write compact, idiomatic Dart.
- Prefer ` Riverpod ` controllers for shared state; do not over-provide.
- Go router routes live in `lib/app/router.dart`.
- Models are in `lib/features/<feature>/data/<feature>_models.dart` or `domain/`.
- Avoid new files unless required; prefer editing existing files.

---

## 10. Common pitfalls

- **"Releasemode is not supported by iPhone 17 Pro"** — release mode only works on a physical device, not on the iOS 26.2 simulator.
- **Camera build warnings about arm64 / GoogleMLKit** — these are known and non-blocking for physical device builds. Do not try to fix by editing iOS project files.
- **Golden test failures** — `test/arena/arena_screen_golden_test.dart` needs `test/fonts/Manrope-VariableFont_wght.ttf`. This is a known missing asset; do not create it unless the task is golden tests.
- **Do not fake AI Motion Proof confidence.** It must come from `motion_validators.dart` / `CustomPoseSequenceRuntime`.

---

## 11. How to explore the code

The repo has a `codegraph` knowledge graph. For "how does X work?" or architecture questions, prefer `codegraph_explore` with the relevant symbols. For specific symbol source, use `codegraph_node`. For impact analysis, use `codegraph_impact`.

When `codegraph` is unavailable, use `grep` and `find_file_by_name` to locate symbols, and `read` to inspect specific files.

---

## 12. Feature in progress: Teach Nuvo (custom movement)

Nuvo is adding a consumer-friendly flow for teaching the app a new custom body movement. The current work is captured in `docs/TEACH_MOVEMENT_UX_RESULT.md`.

### Files

- `lib/features/races/presentation/custom_pose/teach_movement_screen.dart` — the new UI.
- `lib/features/races/ai/custom_pose/pose_calibration_flow.dart` — the `SingleSessionTeachingCapture` state machine.
- `lib/features/races/ai/custom_pose/custom_pose_sequence_builder.dart` — builds the verifier spec from captured demonstrations.
- `lib/features/races/ai/custom_pose/custom_pose_sequence_runtime.dart` — runtime that verifies the custom movement during races.
- `test/pose_calibration_test.dart` — tests for the new flow.

### User flow

1. User enters a movement name.
2. User sees one camera screen and taps **Start teaching**.
3. 3-second countdown.
4. App silently captures a stable starting pose.
5. User performs the movement repeatedly, pausing in the starting position between reps.
6. App automatically captures 2–3 usable examples using departure/return-to-start similarity.
7. App calls `CustomPoseSequenceBuilder` automatically and shows **Learning your movement…**.
8. On success, the screen shows **Movement learned** and the user can **Test movement** or create a race.

### Architecture rules

- Reuse `PoseNormalizer`, `StablePoseCapture`, `PoseDemonstrationCapture`, `CustomPoseSequenceBuilder`, `CustomPoseVerifierSpec`, `CustomPoseSequenceRuntime`.
- Do **not** replace the verifier architecture, create a second camera screen, change the backend, or add GPT/object detection.
- Bad examples (too short, missing frames, inconsistent, etc.) are silently discarded. The user sees friendly copy like **"Do that one more time."**
- Internal builder error codes (`inconsistent_demonstrations`, `low_feature_coverage`, `no_active_features`, `ambiguous_completion_strategy`, etc.) are translated to friendly messages in production. Raw codes only appear behind `kDebugMode`.
- Similarity thresholds for rep segmentation are `_departureThreshold = 0.86` and `_returnThreshold = 0.90`.

---

## 13. When in doubt

- Read `AGENTS.md`.
- Read `docs/NUVO_PRODUCT_MODEL.md`.
- Read `docs/BASELINE_BEFORE_PRODUCT_SKELETON.md`.
- Read `docs/TEACH_MOVEMENT_UX_RESULT.md` for the latest Teach Nuvo status.
- Ask the user for explicit approval before touching anything in the "do not touch" list.
