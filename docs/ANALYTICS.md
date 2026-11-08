# Product analytics & crash reporting

PostHog product analytics for the Nuvo app, plus Crashlytics for crashes.
Analytics is anonymous by design: no email, name, username, user id, token,
camera frame, pose landmark, or free text ever leaves the device through
this pipeline. The implementation lives in `lib/core/analytics/` —
`analytics_service.dart` is the facade every call site uses;
`posthog_sink_io.dart` is the only file that touches the SDK.

## Configure (compile-time only)

Configuration is `--dart-define` only. No key lives in source, tests, docs,
or commits — and not in the iOS plist or Android manifest either.

```bash
flutter run \
  --dart-define=POSTHOG_API_KEY=<POSTHOG_API_KEY> \
  --dart-define=POSTHOG_HOST=https://us.i.posthog.com
```

| Define | Required | Default |
|---|---|---|
| `POSTHOG_API_KEY` | No | _(empty)_ — analytics is a complete no-op: the SDK never starts and every event is dropped. |
| `POSTHOG_HOST` | No | `https://us.i.posthog.com` |

Release builds take the same flags:

```bash
flutter build ipa \
  --dart-define=POSTHOG_API_KEY=<POSTHOG_API_KEY> \
  --dart-define=POSTHOG_HOST=https://us.i.posthog.com
```

## What is sent, and when

- **Consent first**: `AnalyticsService.init` resolves the persisted opt-in
  flag before the sink starts, and `track` drops events until init finished.
  The analytics consent is the Settings toggle below — kept separate from
  `terms_accepted_at`, `age_attested_at`, and `motion_training_consent`,
  which stay server-side and are never read here.
- **Distinct id**: a random UUID generated on first launch, persisted in
  `flutter_secure_storage` under `anon_id` (localStorage on the web
  preview). Never derived from the account; `identify` passes only that
  UUID with no user properties.
- **Events**: the fixed `allowedEvents` set below. `track` also enforces
  the `allowedProperties` allowlist — unknown event names and property
  keys are dropped before they can reach the SDK
  (`test/analytics_test.dart` asserts both lists).
- **Small volume**: `api_error` is capped at 5 per session; no per-rep or
  per-frame events exist anywhere.
- **Opt-out**: Settings → APP → "Help improve Nuvo (usage analytics)".
  Default ON; takes effect immediately (SDK `disable()`/`enable()` plus a
  wrapper-level drop) and persists across launches. No IDFA is read.
- **Off by absence**: an empty `POSTHOG_API_KEY` leaves the pipeline inert —
  no SDK init, no events, no network.

## Replay, screens, and autocapture

- **Session replay is OFF** — never enabled in `PostHogConfig`, and
  `com.posthog.posthog.AUTO_INIT` is `false` in `ios/Runner/Info.plist` and
  `android/app/src/main/AndroidManifest.xml`, so the plugin's plist/meta-data
  auto-init path can never run: the Dart config is the only setup path.
- **No screen/text autocapture** — no `PosthogObserver`, no `PosthogWidget`,
  no `screen()` autocapture. `AnalyticsService.screen()` is the only screen
  event and it is manual; `captureApplicationLifecycleEvents` is false.

## Event table

Onboarding steps are indexed: `0` profile, `1` motion_consent, `2..9` story
pages (`story_p0..7`), `10` notifications.

| Event | Properties | Fired when |
|---|---|---|
| `onboarding_started` | — | The profile screen (first onboarding step) renders. |
| `onboarding_step_viewed` | `step_index`, `step_name` | A step/page actually renders (the notifications primer only when it shows). |
| `onboarding_step_completed` | `step_index`, `step_name`, `ms_on_step` | A step is finished — save/choose, page advance, enable or maybe-later. |
| `onboarding_abandoned` | `step_index`, `step_name` | The story "Skip" compresses the flow. |
| `onboarding_completed` | — | `completeOnboarding()` succeeds (server flag flips). |
| `signup_started` | `method`: `apple` \| `google` \| `email` | Any sign-up entry action (CTA taps or direct email submit under sign-up intent — may fire twice per attempt). |
| `signup_completed` | `method` | Auth resolves authenticated while the sign-up intent is set. |
| `signup_failed` | `method`, `reason`: `cancelled` \| `error` \| `http_<status>` | The sign-up attempt errors or is cancelled (sign-in failures don't count). |
| `race_create_started` | — | The race composer opens. |
| `race_create_completed` | `race_type` (backend format), `ms` | A race create call succeeds. |
| `race_create_failed` | `race_type`, `ms`, `error`: `http_<status>` \| `error` | The create call throws. |
| `race_invite_sent` | — | An invite code is created in the invite sheet. |
| `race_joined` | — | A join succeeds — `RaceController.joinRace`/`joinRaceByCode` (code, open card, detail, inbox) plus the invite-accept seam. |
| `race_join_failed` | `reason`: `http_<status>` \| `error` | The controller join call throws. |
| `race_started` | — | An attempt window opens for the user (camera attempt start — silent proof binds don't count). |
| `race_completed` | — | A submit returns `raceCompleted` — the user's race finished. |
| `race_abandoned` | — | An open attempt is released with no proof bound. |
| `proof_started` | `activity_id` (movement enum or `unknown`) | AI Motion entry point or photo evidence attached. |
| `camera_ready` | `ms` | The AI Motion preview reaches its live ready state — `ms` is screen-open to first `cameraReady`, once per open (lens flips/resumes don't refire). |
| `calibration_failed` | `reason` | An AI Motion take finishes unverified — `reason` is the verifier's internal failure enum (`missing_landmarks`, `pushup_framing_too_close`, `hold_broken`, `shot_not_confirmed`, `no_verified_repetitions`, `target_not_met`, remote/object diagnostics, `unknown`). |
| `proof_result` | `outcome`: `verified` \| `needs_review` \| `pending` \| `rejected` \| `submit_failed`; `failure_reason` (status code); `detected_value` bucket `0` \| `1-9` \| `10-49` \| `50-99` \| `100+`; `duration_s` | Every submit lands or throws — all four controller proof paths. |
| `push_registered` | — | The device token sync lands on the server. |
| `push_register_failed` | `reason`: `denied` \| `error` | Permission denied or the token sync reports failure. |
| `notif_opened` | `type` (payload `destType` enum) | A push tap routes a destination. |
| `screen_loaded` | `screen`, `ms` | First frame on the 5 key screens: `compete`, `arena`, `race_detail`, `activity`, `settings`. |
| `api_error` | `route` (logical tag), `status` | `ApiException` at controller submit/join seams. Max 5/session. |

### Camera funnel call sites

All three camera events are wired in
`lib/features/races/presentation/ai_motion_proof_screen_io.dart` and the
`RaceController` submit seams it calls:

- `cameraReady(ms:)` — inside `_initializeCamera`, on the success path that
  first sets `AiMotionProofStatus.cameraReady`. Guarded by
  `_cameraReadyTracked` so it fires once per screen open; `ms` is measured
  from `_screenOpenedAt` (set at State init). Lens flips, lifecycle resumes,
  and Record-again re-entries don't re-emit.
- `calibrationFailed(reason:)` — inside `_finishRecording`, at each of the
  three `aiFailed` transitions (object composition, custom pose, and
  preset/remote branches). The reason is the verifier's internal failure
  enum — `_objectUpdate?.diagnostic ?? 'shot_not_confirmed'` for basketball,
  `acceptedResult.finalFailureReason ?? _runtime.failedRuleReason` for
  custom, `_runtime.failedRuleReason` for preset/remote — with `unknown`
  when the runtime recorded none. Never a user-facing message.
- `proof_result` — lands via `_emitProofOutcome` / `_emitProofFailure` on
  the four controller submit paths (`submitProof`, `submitAiMotionProof`,
  `submitObjectCompositionProof`, `submitCustomPoseProof`), once per landed
  or thrown submit. The camera file deliberately never emits it — doing so
  would double-fire. `race_started` likewise stays on `startAttempt`;
  `_ensureOpenAttempt`'s silent binds don't count.

## Crash reporting (Crashlytics)

`firebase_crashlytics` is wired in `main.dart`, guarded the same way
`PushService` guards: `Firebase.initializeApp()` throws when
`GoogleService-Info.plist`/`google-services.json` isn't in the build, so
crash capture simply never starts on builds without Firebase config — the
app keeps running fine. **Never commit the Firebase plist/json files.**

- `FlutterError.onError` → `recordFlutterFatalError`
- `PlatformDispatcher.instance.onError` → `recordError(fatal: true)`

**iOS dSYM upload**: for readable iOS stack traces, add an Xcode
"Run Script" build phase invoking the Crashlytics dSYM uploader
(`${PODS_ROOT}/FirebaseCrashlytics/upload-symbols`), or rely on the
firebase_crashlytics plugin's CocoaPods script — App Store/TestFlight
symbols can also be uploaded manually via `firebase crashlytics:symbols:upload`.
Documented so the release step isn't lost — no build phase is committed here
since `ios/Runner.xcodeproj` is a no-touch file.

## Privacy notes

- No PII, no free text — property keys are a closed set of 17
  (`step_index`, `step_name`, `ms_on_step`, `method`, `reason`,
  `race_type`, `ms`, `error`, `activity_id`, `outcome`, `failure_reason`,
  `detected_value`, `duration_s`, `type`, `screen`, `route`, `status`).
  Values are enums, ints, or booleans; `detected_value` is bucketed;
  `reason`/`failure_reason`/`error` carry status codes, never messages.
- Person records stay anonymous — `identify` passes only `anon_id`, no
  properties.
- `reset()` rotates the anonymous UUID (fresh identity) without touching
  the opt-in choice.

## App Store privacy label answers

| Question | Answer |
|---|---|
| Data collected? | Yes — Device ID (anonymous UUID), Product Interaction (allow-listed events), Crash Data. All **not linked** to identity, all **not used for tracking**. |
| Device ID | Collected for analytics, not linked to identity, not tracking. |
| Product Interaction | Collected for analytics, not linked, not tracking. |
| Crash Data | Collected for app functionality (diagnostics), not linked, not tracking. |
| Tracking (ATT)? | **No** — nothing is shared for cross-app tracking; no IDFA. |
| Required-reason APIs | UserDefaults (CA92.1), FileTimestamp (C617.1), SystemBootTime (35F9.1) — already declared in `PrivacyInfo.xcprivacy`. |

(Existing app data — email, name, photos, fitness — keeps its current
answers; this table covers only what analytics/crash adds.)

## How to turn it off

- **User**: Settings → APP → "Help improve Nuvo (usage analytics)" → off.
  Immediate, persisted, also disables the SDK queue.
- **Build**: omit `POSTHOG_API_KEY` — the SDK never starts.
- **Code**: `AnalyticsService.disabled()` / provider override in tests.

## Testing

```bash
flutter test test/analytics_test.dart
```

Covers: no-op without a key, consent gating (off stops capture, persisted
off starts opted out), the event + property allowlists (including forged
props), `api_error` session cap, `reset` id rotation, and store
persistence/corruption. Widget tests override `analyticsProvider` with
`FakeAnalyticsService`.
