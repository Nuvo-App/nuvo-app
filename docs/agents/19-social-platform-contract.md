# Nuvo Social Platform — Architecture Contract

Status: **ACTIVE — implementation in progress.** This document is the single
source of truth for how race sharing, QR codes, deep/universal links, crew
connections, notifications, push, invites, privacy/blocking and cross-app
freshness fit together as *one* infrastructure.

Supersedes the planning-only design in
[15-crew-system-plan.md](15-crew-system-plan.md),
[16-notification-system-plan.md](16-notification-system-plan.md),
[17-qr-sharing-plan.md](17-qr-sharing-plan.md) — those stay as background
rationale; where they disagree with this doc, **this doc wins**. Builds on the
mandatory [18-data-freshness-contract.md](18-data-freshness-contract.md).

---

## 0. The seven primitives

```
IDENTITY        users + profiles + member_passes            (existing)
RELATIONSHIP    crew_connections + blocked_users            (existing, extended)
INVITE          invites + invite_uses                       (new — 0014)
DESTINATION     NuvoDestination (client) / dest_* (server)  (new)
EVENT           domain events emitted inline from routes    (new — phase E)
NOTIFICATION    notifications + notification_preferences    (new — 0014)
FRESHNESS       the stale-while-revalidate contract (doc 18)
```

QR, universal links, the share sheet and push are **input mechanisms**, not
routing models. Every one resolves to a `NuvoDestination` and is handed to the
one deep-link router.

---

## 1. NuvoDestination — one canonical destination

`lib/features/social/domain/nuvo_destination.dart`. A sealed class:
`RaceDestination` · `ProfileDestination` · `CrewDestination` ·
`InviteDestination` · `NotificationsDestination`.

- `NuvoDestination.tryParse(Uri)` — universal link (`https://<host>/j/<token>`),
  custom scheme (`nuvo://j/<token>`, `nuvo://app/race/:id`), or an in-app path.
  Returns `null` for anything that isn't a Nuvo link — **the QR scanner and the
  link handler must never open a `null`.**
- `NuvoDestination.fromDescriptor(Map)` — from a server-provided
  `{type, id|token, context}`. The backend NEVER sends a raw route string;
  `destination.location` is the ONLY place a destination becomes a go_router
  path. This keeps mobile navigation decoupled from the backend.

Entry sources that all funnel through this: QR scan · universal link · custom
scheme · push-notification tap · in-app notification tap · shared URL ·
cold-start pending route.

## 2. One deep-link router

`DeepLinkController` (`lib/features/social/application/deep_link_controller.dart`)
is the **only** link listener in the app. `NuvoApp` calls `.start(router)` once,
post-first-frame, which:

1. subscribes to `AppLinks().uriLinkStream` (warm) and reads
   `getInitialLink()` (cold start),
2. `NuvoDestination.tryParse` → `handleDestination`,
3. if the destination needs auth and there's no session → stash it and
   `router.go('/welcome')`; otherwise `router.go(destination.location)`.

`handleDestination(dest, authed:)` is also the push-tap entry point (phase F).

## 3. Auth cold-start — pending destination

`PendingDestinationStore` (`flutter_secure_storage`, survives a cold start).
Flow: link → not signed in → `store.put(dest)` → sign-in → **`NuvoApp`'s
`ref.listen(authControllerProvider)`** sees the transition to
`authenticated` + `onboardingComplete` → `store.consume()` → `router.go(...)`.
The user never rescans. `/invite/:token` also stashes on its "Sign in to join"
button, so a logged-out preview → sign-in → auto-return works.

## 4. Universal link + invite URL

```
https://nuvo-api.getnuvoapp.workers.dev/j/<token>          (current)
nuvo://j/<token>                                            (custom scheme, works today)
```

- The link **host is the Worker's own origin.** A prettier host
  (`get.nuvo.app`) is a DNS + `wrangler.toml` `route` change that touches
  nothing else — the token, routes, AASA and client parser are all
  host-agnostic.
- Served by the Worker:
  - `GET /.well-known/apple-app-site-association` — `appID`
    `W62869AF7L.net.getnuvo.app`, paths `["/j/*"]`.
  - `GET /.well-known/assetlinks.json` — Android; **`sha256_cert_fingerprints`
    is empty until the release keystore fingerprint is added** (the one
    remaining Android step).
  - `GET /j/:token` — branded web fallback: preview headline + "Open in Nuvo"
    (`nuvo://`) + App Store button. A device with the app installed never sees
    this (the OS intercepts the universal link).

### iOS portal step (not doable from code)
`ios/Runner/Runner.entitlements` declares
`com.apple.developer.associated-domains = ["applinks:nuvo-api.getnuvoapp.workers.dev"]`.
A **signed** build needs the "Associated Domains" capability enabled for App ID
`net.getnuvo.app` in the Apple Developer portal. Custom-scheme links work
without it.

## 5. Token design (decision)

`invites.token` is a **43-char random lookup token** (43 bytes →
`crypto.getRandomValues`, base64url alphabet, ~258 bits). NOT a signed blob.

Rationale: a DB-backed row is exactly what we want — revocation (`revoked_at`),
expiry (`expires_at`), usage caps (`max_uses`/`use_count`) and an audit trail
(`invite_uses`) are all first-class. A signed/stateless token trades all of
that away to avoid one indexed lookup. The token is not derived from any
internal id, so it leaks nothing; `looksLikeInviteToken()` gates the shape
before any DB hit (enumeration guard).

## 6. Invite model

`invites(id, token, kind, actor_user_id, target_type, target_id, max_uses,
use_count, expires_at, revoked_at, metadata, created_at)` +
`invite_uses(invite_id, user_id)` for idempotent acceptance.

`kind` ∈ `race_join` | `crew_connect` | `squad_join` *(501 for now)*.
`targetTypeForKind`: race → `race`, crew → `user`, squad → `squad`.

`inviteAvailability(row, now)` (pure, `lib/invites.ts`) →
`active | expired | revoked | used | not_found`. Precedence:
revoked > expired > used. HTTP: `not_found` → 404, everything else → 410.

## 7. Worker routes

| Route | Auth | Notes |
|---|---|---|
| `POST /invites` `{kind, targetId?, maxUses?, expiresInSeconds?}` | required | authorize (race creator / self for crew); reuse a live invite for the same (actor,target,kind); rate-limit 20/user/hr; races also mint/return the legacy `race_invites.invite_code` |
| `GET /invites/:token` | optional | safe preview, works logged-out; `resolveRaceMemberVisibility` for the creator; blocking → generic 410; explicit `status` on 404/410 |
| `POST /invites/:token/accept` | required | idempotent — race: `ensureMember`+`ensureProgress` (`domain/raceMembership.ts`); crew: public→`active`, private→`pending`; block checks; records `invite_uses` |
| `DELETE /invites/:token` | required (creator) | sets `revoked_at` |

`GET /j/:token` (public) — the web fallback page.

## 8. Crew connection lifecycle

`crew_connections.status` ∈ `active | pending | declined | removed`
(+ nullable `requested_by`, `updated_at` from 0014). Legacy rows (no
`requested_by`) are treated as `active`.

- Public profile + connect → `active` immediately (both directional rows).
- Private profile + connect → `pending` request the target accepts
  (`crew_request` notification, phase E).
- **Blocking wins over everything** — enforced by `isBlocked` in the accept
  path and by `resolveRaceMemberVisibility` (the single identity policy; QR has
  no separate privacy rules). Co-race identity stays independent of crew.

Full crew UI (requests inbox, public profile screen, freshness controller) —
**phase D**.

## 9. Notifications (phase E)

`notifications(id, user_id, category, actor_user_id, title, body, dest_type,
dest_id, dest_context, entity_type, entity_id, dedupe_key, read_at,
created_at)`. `dest_*` is a **structured destination**, never a route string.
`(user_id, dedupe_key)` is UNIQUE → one logical event = one row (idempotency).

`emitNotification(db, {...})` — called inline from the route that caused the
event (proof submit, race join, crew accept). Reads
`notification_preferences(user_id, category, in_app, push)` first; absent row =
category default (transactional push on, engagement off, all in-app on).

V1 categories: `race_invite`, `race_joined`, `race_starting`, `race_completed`,
`passed_on_leaderboard`, `proof_accepted`, `proof_rejected`, `crew_request`,
`crew_request_accepted`. Transactional first; engagement/reminders are a later
policy layer.

## 10. Push (phase F)

`device_tokens(user_id, token, platform, app_version, last_seen_at,
disabled_at)`. Provider: **FCM** (one SDK, Android-ready) over APNs. Permission
prompt is **contextual** (after first race join / first crew request), never on
launch. Push payload carries the structured descriptor → same
`DeepLinkController.handleDestination` → same router.

## 11. Freshness integration

New domains (`CrewController`, `NotificationController`) are standard doc-18
notifiers. Mutations write through + `onMutated`:
- invite-accept (race) → `RaceController.refreshJoinedRace(id)` folds fresh
  detail into the canonical list, non-silent → Arena/Compete update now.
- crew connect → `CrewController.onMutated` →
  `RaceController.markParticipantsStale()` (a new connection can reveal a
  co-racer's identity).

Never a second cache system.

## 12. Future: Squads

`squad_join` invite kind + `SquadDestination` slot exist. Adding squads =
a new kind + a new destination case + the existing signed link + the existing
QR renderer. **No** separate link/QR/notification platform. Not built now; no
squad tables or UI.

## 13. Future-Claude contract

- "notify when someone finishes my race" → new category + `emitNotification`
  call in the completion route + a `dest` descriptor + a preference default +
  a test. No new Firebase call site.
- "a QR for X" → new invite kind → existing `/invites` → existing QR renderer →
  new `NuvoDestination` case. No new QR backend.

---

## Implementation status

| Phase | Scope | State |
|---|---|---|
| A | migration, invite model+routes, token, AASA/fallback, `NuvoDestination`, pending-through-auth, `/invite/:token` | **done** (worker deployed `7b7bd807`) |
| B | race Share sheet (QR + copy + share + code), race-detail + invite-crew wiring | **done** (`RaceShareSheet`, `showRaceShareSheet`) |
| C | QR scanner + profile QR + camera-permission UX | todo |
| D | crew requests inbox, public profile screen, `CrewController` | todo |
| E | notifications table, `emitNotification`, inbox, `NotificationController` | todo |
| F | FCM device tokens, permission UX, push send, tap routing | todo |
| G | AASA verify on device, Android assetlinks fingerprint, web-fallback polish | partial (files shipped; portal + fingerprint pending) |
| H | preferences screen, rate-limit hardening, diagnostics, beta surface | todo |

### External dependencies the remaining phases need (cannot be done from code)
- **Phase F (push):** a Firebase project + `GoogleService-Info.plist` (iOS) +
  `google-services.json` (Android) + an APNs auth key (`.p8`) uploaded to
  Firebase. The Worker also needs an FCM server credential
  (`wrangler secret put FCM_SERVICE_ACCOUNT`). Until these exist, notifications
  work fully in-app; push is dark.
- **Phase G (iOS universal links):** "Associated Domains" capability toggled for
  App ID `net.getnuvo.app` in the Apple Developer portal.
- **Phase G (Android App Links):** the release keystore's SHA-256 in
  `assetlinks.json`.
- **App icon:** the source `.icon` project needs Apple's Icon Composer / a
  proper export pipeline on the build machine.

### Known gaps (Phase A)
- Live HTTP verification of the deployed endpoints was blocked by the build
  environment's egress; migration + tables verified via the D1 API, worker
  unit tests green. Manual curl checks listed in the phase report.
- `ProfileDestination` lands on `/pass` until the phase-D public profile screen.
- `routes/races.ts` keeps private copies of `ensureMember`/`ensureProgress`;
  `domain/raceMembership.ts` is the shared version the invite path uses.
  Consolidating races.ts onto it is a safe follow-up.
- App Store id placeholder in `lib/wellKnown.ts` / the fallback page.
