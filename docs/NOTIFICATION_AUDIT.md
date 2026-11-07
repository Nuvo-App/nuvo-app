# Notification system audit (2026-11-07)

Verified = proven by a test in this repo or by a live read-only call. Nothing here was
verified on a real iPhone, and nothing was deployed.

## Pipeline

```
event (route / cron)
  → notifyEvent / notifyRaceEvents / notifyLifecycleTransitions     (domain/notificationPolicy.ts)
  → who is told, eligibility (blocks), preferences, budget, dedupe   → inbox row (notifications table)
  → sendPushDetailed                                                 (domain/push.ts)
      device_tokens lookup → FCM OAuth (service account) → FCM v1 messages:send, one request per device
  → FCM → APNs → iPhone
tap → PushService (FCM onMessageOpenedApp / getInitialMessage) → NuvoDestination → router
```

## Live evidence (read-only)

| check | result |
|---|---|
| FCM secrets on the live Worker | present (`pushConfigured: true`) |
| active users / users with a device token | 41 / **0** |
| `/internal/push/status` (new) | 404 — the live Worker is an older build; the new diagnostics need a deploy |

So the Worker can send; **no phone has ever registered a token**, which is why nothing arrives.
(`push-status` after deploy also reports credential validity, the Firebase project match, and disabled-token counts.)

## Event → delivery map

| Trigger | Implemented? | Backend sends? | Token available? | Test result | Fix needed |
|---|---|---|---|---|---|
| Race invitation (creator adds you, rematch roster, squad race) | Yes — `race_invited` → `race_invite`, high | Yes (push + inbox) | **No (0 of 41)** | PASS e2e on real SQLite schema: inbox row, FCM request to the recipient's device only, correct `destType/destId/notificationId`; also no-device, pref-off, dormant, blocked | Token registration (fixed in code) + entitlement (fixed) + deploy + device test |
| Someone joins your race | Yes — `race_member_joined` → creator | Yes; first join of the day pushes, later joins roll into one inbox row; engagement budget 1/hr, 4/day | No | PASS e2e (creator notified, joiner not) | Same as above |
| A friend challenging you | **No separate concept** | n/a | n/a | n/a | The closest is a race invitation. Decide whether "challenge" needs its own event |
| Leaderboard change / someone overtook you | Yes — `passed_on_leaderboard` | Yes, deliberately throttled: only podium or crew, 30-min pair cooldown, 2 per race per hour, lead-trade roll-up, budget | No | PASS unit (policy tests); not e2e | None for logic; most overtakes are intentionally inbox-only |
| Race starting (at start line) | Yes — `race_started` → `race_starting` | Yes, by cron `*/5` or lazily on read | No | PASS unit | Depends on the cron being deployed |
| Race starting in 30 min | Yes — job `race_starting_soon` | Yes, only when the race has a `start_at` | No | PASS unit (schedule, relevance, send) | None |
| Race ending / expiring soon | **Not implemented** | — | — | — | New job kind if wanted |
| Race result / winner | Yes — `race_finished` → `race_completed` (winner copy) | Yes | No | PASS unit | None |
| Friend request | Yes — `crew_request` | Yes | No | PASS e2e (requested person pushed, requester not) | None |
| Friend request accepted / connected | Yes | **Inbox only by design** (push default off) | n/a | PASS e2e (no push) | Product call |
| Proof verified / rejected / vetoed | Yes — `proof_accepted/rejected` | Yes | No | PASS unit | None |
| Proof disputed | Yes | Inbox only by design | n/a | PASS unit | None |
| Reaction on your activity | Yes | Inbox only by design | n/a | PASS unit | None |
| Reminder for an unfinished race / streak / daily check-in | **Not implemented** (the only job kind is `race_starting_soon`) | — | — | — | New feature |
| Admin broadcast | Yes (admin only, dry run by default) | Yes | — | PASS (existing) | Not used for testing |

Lifecycle matrix (all **Not yet tested on a real device**):

| State | What the code does |
|---|---|
| Foreground | `onMessage` marks inbox/races/arena stale; iOS shows **no banner** (no foreground presentation options are set — by design in the code comments) |
| Background | FCM `notification` payload is displayed by iOS itself; tap → `onMessageOpenedApp` → destination |
| Terminated | Displayed by iOS; tap → `getInitialMessage` → destination |
| Tap routing | Unit tested: warm signed-in, signed-out (stashed), cold start (router not ready), account switch, bad payload |

## Defects found and fixed

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 1 | **No `aps-environment` entitlement** — iOS never issues an APNs token, so no FCM token, so nothing registers | `Runner.entitlements` omitted it "on purpose"; 0 tokens live | Added `aps-environment` (Xcode swaps to production for App Store builds) — `617ff02` |
| 2 | Signed-in users never synced their token: sign-in ran before Firebase finished starting, so `onSignedIn` was a silent no-op, and `onTokenRefresh` only fires when the token changes | `push_service.dart` (`if (!_available) return`) | Sync after start and on every resume; `onSignedIn` waits for start |
| 3 | `getToken` throws `apns-token-not-set` early and was never retried | catch-and-ignore | Backoff retry in `PushTokenSync` |
| 4 | Registration failures were invisible: `DeviceApi.register` ignored the HTTP status, so a 401/5xx = never registered, never retried | code | Returns success; retried; only marked synced after the server accepts |
| 5 | FCM rejections were swallowed — no log, no reason | `sendPush` ignored non-OK except disable | `sendPushDetailed` + one `[push]` log line per send with the outcome |
| 6 | Silent when the recipient has no token | `return 0` with no log | `outcome=no_devices` logged |
| 7 | Any `INVALID_ARGUMENT` disabled the device token (a payload problem would kill every healthy token) | `/INVALID_ARGUMENT/` regex | Only UNREGISTERED / 404 / "registration token" errors disable |
| 8 | `notificationId` was missing from some pushes | `safeEmit`, `deliverNotificationPushes` | Passed through |

## Log vocabulary (Cloudflare `wrangler tail nuvo-api`, search `[push]`)

`outcome=no_devices` recipient has no token · `dormant` FCM not configured · `auth_failed` credentials rejected ·
`rejected` FCM refused (see `failures=status/CODE`; `SENDER_ID_MISMATCH` = token from a different Firebase project,
`THIRD_PARTY_AUTH_ERROR` = APNs key missing in Firebase) · `partial` · `sent` FCM accepted (arrival on the phone is not confirmed).
"Event not triggered" = no `[push]` line and no inbox row for that user.

## Manual actions (yours)

1. **Deploy the Worker** (new diagnostics + logging): `cd server/worker && npx wrangler deploy`.
2. **Xcode**: target Runner → Signing & Capabilities → confirm **Push Notifications** is present (it needs the App ID capability, which you enabled).
3. **Firebase**: upload the APNs Auth Key (.p8, Key ID, Team ID `W62869AF7L`) under Cloud Messaging; make sure `ios/Runner/GoogleService-Info.plist` is from the **same** project as `FCM_PROJECT_ID` (compare `PROJECT_ID` in the plist with `credentials.fcmProjectId` from `push-status`).
4. `git pull origin motion-ota-tuning`, build **release** to a phone, sign in, accept the notification prompt (onboarding, or after inviting someone).
5. `./scripts/nuvo-ops.sh push-status --email <you>` → expect `activeDevices: 1`, `credentials.tokenExchange: ok`, `projectsMatch: true`.
6. `./scripts/nuvo-ops.sh push-test --email <you>` (dry run) then `--send` → a real notification on your phone. Then invite your main account to a race from a second account.

## Remaining for production-ready

- Real-device verification of every row above (nothing here proves delivery to a phone).
- Decide on: foreground banners, a distinct "challenge" event, race-ending and unfinished-race reminders.
- `UIBackgroundModes: remote-notification` is not in `Info.plist` (a no-touch file). It is not needed for visible alerts; it is needed for silent/data pushes.
- Android has no `google-services.json` in the repo; Android push is untested.
