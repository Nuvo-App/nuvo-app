# PostHog product analytics

Product analytics for the Nuvo app. Anonymous by design: no email, name,
user id, photos, or free text ever leaves the device through this pipeline.
The implementation lives in `lib/core/analytics/` — `analytics.dart` is the
facade every call site uses; `posthog_sink_io.dart` is the only file that
touches the SDK.

## Configure (compile-time only)

Configuration is `--dart-define` only. No key lives in source, tests, docs,
or commits.

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

- **Distinct id**: a random UUID generated on first launch, persisted locally
  (`nuvo_analytics.json` in app documents; `localStorage` on the web preview).
  It is never derived from the account and is the only identity PostHog sees.
- **Events**: the fixed set below. Every event name is `snake_case`; every
  property key is enforced by a wrapper-level allowlist — anything else is
  silently dropped before it can reach the SDK (`test/analytics_test.dart`
  asserts the allowlist covers the whole vocabulary).
- **Opt-out**: Settings → APP → "Help improve Nuvo". Default ON; it takes
  effect immediately (the SDK is told to stop capture, and the wrapper drops
  events regardless) and persists across launches. Starting with the opt-out
  already recorded means nothing can queue before the flag is read.
- **Off by absence**: an empty `POSTHOG_API_KEY` (the default for every local
  dev build) leaves the whole pipeline inert — no SDK init, no events.

## Event table

| Event | Properties | Fired when |
|---|---|---|
| `app_opened` | — | Cold launch, once per process (app shell init). |
| `signup_started` | — | Any sign-up entry action: "Create account", Continue with Apple/Google in sign-up mode, or email submit under sign-up intent (may fire twice per attempt — once per action). |
| `signup_completed` | — | Auth resolves authenticated while the sign-up intent is set. |
| `onboarding_step_viewed` | `step`: `profile` \| `motion_consent` \| `story_p0..7` \| `notifications` | Each onboarding screen/page renders. |
| `onboarding_completed` | — | `completeOnboarding()` succeeds (server flag flips). |
| `onboarding_skipped` | `step`: page left | Story "Skip" (step = page skipped from) or notifications "Maybe later". |
| `race_create_started` | — | The race composer opens. |
| `race_created` | `format`, `movement_kind`: `preset` \| `custom` \| `goal`, `has_finish_line`, `attempt_duration_s?` | A race create call succeeds; props mirror the sent payload. |
| `race_joined` | `via`: `code` \| `invite` \| `open` \| `notification` | A join succeeds — code screen, invite link, open-race card/detail, or inbox accept. |
| `proof_started` | `method`: `camera` \| `photo` | The AI Motion verifier is entered, or photo evidence is attached in the manual sheet. |
| `proof_submitted` | `format`, `verified` | A proof lands — `verified` is the verdict via the canonical proof-status mapping (pending/review ⇒ `verified: false`). |
| `proof_rejected` | `reason_code`: `ai_failed` \| `rejected` \| `failed` \| `unknown` \| `http_<status>` \| `error` | A submit resolves with a failed verdict, or the submit call throws. |
| `attempt_started` | — | A best-single / timed attempt opens server-side (explicit start only — silent proof binds don't count). |
| `attempt_cancelled` | — | An open attempt is released with no proof bound. |
| `race_finished_viewed` | `place`: viewer's final rank, `0` when not on the board | First time a completed race's final standings render on race detail (load or live refresh). |
| `friend_added` | — | A friend link forms — instant connect or request accepted (a sent request does not count). |
| `crew_joined` | — | Joining a named crew succeeds (code entry or squad invite accept). |
| `notification_permission` | `granted` | The OS notification prompt resolves inside `requestPermissionInContext()`. |

## Privacy notes

- **Session replay is OFF** — never enabled in `PostHogConfig`, and no
  `PosthogObserver`/`PosthogWidget`/`screen()` calls exist, so there is no
  screen-name or text autocapture either.
- **No autocapture of screen text** — nothing reads the widget tree; events
  fire only from the named seams.
- **No PII, no free text** — the property allowlist is a closed set of 11
  keys (`step`, `format`, `movement_kind`, `has_finish_line`,
  `attempt_duration_s`, `via`, `method`, `verified`, `reason_code`, `place`,
  `granted`). Values are booleans, ints, or fixed vocabulary strings.
  `reason_code` never carries an exception message — only status codes.
- **Person records stay anonymous** — `identify` passes only the install
  UUID, with no user properties attached.
- **Proof media, notes, race titles, names, emails, and user ids are never
  attached to any event** — call sites emit enums and counts only.

## Testing

```bash
flutter test test/analytics_test.dart
```

Covers: no-op without a key, opt-out gating (including a persisted opt-out
at start), the property allowlist across every event helper, and toggle/id
persistence round-trips. Widget tests can override `analyticsProvider` with
`FakeNuvoAnalytics` to record events without the SDK.
