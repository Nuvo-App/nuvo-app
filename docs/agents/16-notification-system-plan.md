# Nuvo Notification System — Product + Technical Plan

> **SUPERSEDED by [19-social-platform-contract.md](19-social-platform-contract.md).** Kept for design rationale only; where it disagrees with doc 19, doc 19 wins.

Status: **SUPERSEDED by [19-social-platform-contract.md](19-social-platform-contract.md)** — kept for design rationale. Original note: PLAN ONLY. Reviewed with
[15-crew-system-plan.md](15-crew-system-plan.md) and
[17-qr-sharing-plan.md](17-qr-sharing-plan.md).

---

## 0. Principles

- **Every notification deep-links somewhere useful.** No dead taps.
- **Transactional beats engagement.** Ship "proof accepted", "someone passed
  you", "you were invited" first. Streak nudges / re-engagement later, behind a
  preference, rate-limited hard.
- **The app already has the data.** Most notifications are a side effect of a
  Worker route that already runs (proof submit, race join, crew accept). Add an
  emit call there, not a separate pipeline.
- Nuvo voice: short, second person, specific. "Riley passed you in Squat
  Sprint." not "You have a new race update."

---

## 1. Categories

| Key | Trigger (Worker route) | Deep link | Push? | Type |
|---|---|---|---|---|
| `invited_to_race` | `POST /races/:id/participants`, `/members` | `/race/:id` (preview) | yes | transactional |
| `race_starting` | scheduled: `start_at` reached | `/race/:id` | yes | transactional |
| `passed_by_racer` | `POST /races/:id/proof` when `peoplePassed > 0` (notify the passed) | `/race/:id` | yes | transactional |
| `you_passed` | same, notify the submitter | `/race/:id` | no (in-app toast already) | — |
| `race_completed` | proof submission that completes the race | `/race/:id` | yes | transactional |
| `proof_accepted` | manual proof auto/marked accepted | `/race/:id` | opt | transactional |
| `proof_needs_review` | proof → `needs_review` (owner) | `/race/:id/review` | yes | transactional |
| `finish_line_close` | proof leaves you within N% of goal | `/race/:id` | opt | engagement |
| `crew_request` | `POST /crew` on a private profile | `/pass` (requests) | yes | transactional |
| `crew_request_accepted` | `POST /crew/requests/:id/accept` | `/profile/:userId` | opt | transactional |
| `crew_member_joined` | a connection joins a race you're in | `/race/:id` | opt | engagement |
| `squad_invitation` *(later)* | squad invite | `/squad/:id` | yes | transactional |

Anything not transactional is **default-off** for push, on for in-app.

---

## 2. Storage

```
notifications(
  id, user_id,
  category TEXT,
  title TEXT, body TEXT,
  deep_link TEXT,              -- app route, e.g. /race/abc
  entity_type TEXT, entity_id TEXT,   -- for de-dupe + bulk read
  actor_id TEXT,               -- who caused it (for the avatar)
  read_at TEXT,
  created_at TEXT
)
-- index (user_id, created_at DESC), (user_id, read_at) partial
```

De-dupe: `passed_by_racer` for the same (race, actor, target) within 10 min
updates the existing row instead of stacking. `finish_line_close` fires once
per race per user.

Retention: hard-delete `read` rows older than 30 days, unread older than 90.

---

## 3. Emit path

`emitNotification(db, { userId, category, ... })` — one helper, called inline
from the route that caused it. It:
1. checks the recipient's preference for the category (§5) — skip if off,
2. checks category rate limit (§6),
3. inserts the row,
4. if push-eligible and the user has a device token, enqueues a push (§4).

Batching: a route that passes several people (`recomputeRanks` moves multiple
ranks) calls `emitNotification` per affected user in the same request; the
Worker's `c.executionCtx.waitUntil()` keeps the response fast.

Scheduled ones (`race_starting`) — a Cloudflare **Cron Trigger** on the Worker
runs every minute: `SELECT races WHERE start_at BETWEEN now-60s AND now AND
NOT notified` → emit + mark.

---

## 4. Push provider

- **iOS: APNs**, via `apns2`-style HTTP/2 from the Worker, OR Firebase Cloud
  Messaging (one SDK, Android-ready). **Recommend FCM** — one integration,
  Nuvo will want Android.
- Device token registration: `POST /devices` `{ token, platform, appVersion }`
  on launch + on token refresh; `DELETE /devices/:token` on sign-out.
  Store `device_tokens(user_id, token, platform, created_at, last_seen_at)`.
- Client: `firebase_messaging` (or `flutter_local_notifications` +
  `apns`), permission prompt **deferred** to the first moment it's relevant
  (after creating/joining the first race), never on launch.
- Payload carries `deep_link`; a tap routes via `go_router` (`context.go`).
  Cold-start: stash the link, consume after auth gate resolves.
- Delivery is best-effort; the in-app list (§7) is the source of truth.

---

## 5. User preferences

`notification_preferences(user_id, category, in_app INT, push INT)` — default
from the table in §1 (transactional push on, engagement push off, all in-app
on). A Profile → Notifications screen: grouped toggles (Races / Crew /
Reminders), each with in-app + push. `emitNotification` reads this first.

Global "pause all push" switch (e.g. 8h / until tomorrow) for do-not-disturb.

---

## 6. Rate limits

Per user per category, sliding window:
- `passed_by_racer`: max 1 / 10 min / race (de-dupe row).
- `finish_line_close`: 1 / race / user, ever.
- `crew_member_joined`: max 3 / day.
- engagement categories: max 1 / user / day total.
- transactional: no cap (they're all user-initiated events).

Enforced in `emitNotification` via a `notification_rate(user_id, category,
window_start, count)` counter or a `created_at` lookback query.

---

## 7. In-app notification centre

- `NotificationController` / `notificationControllerProvider` — follows
  [18-data-freshness-contract.md](18-data-freshness-contract.md).
  `NotificationState { items, unreadCount, loading, refreshing, error }`.
  `revalidate()` on app resume + when the bell is opened. Push receipt (§4)
  calls `notificationController.markStale()`.
- Bell icon with unread badge in the app bar / a nav slot. Tapping an item
  marks it read (`POST /notifications/:id/read`) and deep-links.
  "Mark all read" → `POST /notifications/read-all`.
- Empty state: "You're all caught up." (per contract §6).
- Each row: actor avatar, title, relative time, unread dot.

---

## 8. Endpoints

| Route | |
|---|---|
| `GET /notifications?cursor=` | list, newest first, `unreadCount` |
| `POST /notifications/:id/read` | |
| `POST /notifications/read-all` | |
| `GET /notification-preferences` / `PATCH /notification-preferences` | |
| `POST /devices` / `DELETE /devices/:token` | push token registration |

---

## 9. Build order

1. `notifications` table + `emitNotification` + `GET /notifications` + read.
2. Wire the 5 transactional categories into their existing routes.
3. In-app notification centre + bell badge + `NotificationController`.
4. Preferences table + screen.
5. FCM: device tokens, permission prompt, push send from `emitNotification`,
   deep-link routing.
6. Cron trigger for `race_starting`.
7. Engagement categories + rate limiting, last.

---

## 10. Cross-references

- Crew events (`crew_request`, `crew_request_accepted`, `crew_member_joined`,
  `squad_*`): [15-crew-system-plan.md](15-crew-system-plan.md).
- Deep-link format & cold-start handling shared with universal links:
  [17-qr-sharing-plan.md](17-qr-sharing-plan.md) §4.
- `NotificationController` is a standard freshness domain:
  [18-data-freshness-contract.md](18-data-freshness-contract.md).
