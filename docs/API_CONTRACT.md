# Nuvo API Contract (Simplified Backend)

This document describes the HTTP API contract for the Nuvo backend after the simplified schema redesign. The contract is **backwards compatible** with the existing Flutter app.

---

## 1. Authentication

All routes except `/auth/*` and `/profile/photo/upload` require a valid access token in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

Tokens are short-lived JWTs issued by `POST /auth/token`.

---

## 2. Auth routes

### POST /auth/email/send-code

Request body:

```json
{
  "email": "user@nuvo.app"
}
```

Response:

```json
{
  "ok": true,
  "email": "user@nuvo.app"
}
```

### POST /auth/email/verify-code

Request body:

```json
{
  "email": "user@nuvo.app",
  "code": "123456"
}
```

Response:

```json
{
  "ok": true,
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 900
}
```

### POST /auth/google

Request body:

```json
{
  "idToken": "...",
  "platform": "ios"
}
```

Response: same as `POST /auth/email/verify-code`.

### POST /auth/token

Refresh access token.

Request body:

```json
{
  "refreshToken": "..."
}
```

Response:

```json
{
  "ok": true,
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 900
}
```

### POST /auth/logout

Invalidates the current refresh token.

Response:

```json
{
  "ok": true
}
```

### DELETE /auth/account

Deletes the current user and all related rows.

Response:

```json
{
  "ok": true
}
```

---

## 3. Profile routes

### GET /profile/me

Response:

```json
{
  "fullName": "Alex Demo",
  "username": "alexdemo",
  "profilePhotoUrl": "https://...",
  "avatarUrl": "https://...",
  "privateProfile": false,
  "onboardingComplete": true,
  "bio": "climbs things",
  "favoriteMovementKey": "push_ups",
  "activityMapShared": true,
  "raceInvitesFrom": "everyone"
}
```

v13 fields (all additive, `null` when unset):

- `bio` — free-text bio, up to 80 chars.
- `favoriteMovementKey` — the member's favorite movement key, up to 40 chars.
- `activityMapShared` — whether the member shares their activity map with other members (default `true`).
- `raceInvitesFrom` — `"everyone"` (default) or `"friends"`. When `"friends"`, only a connected friend may add this member to a race; other add attempts return `403`.

### POST /profile

Update profile fields. Any subset of fields may be provided.

Request body:

```json
{
  "fullName": "Alex Demo",
  "username": "alexdemo",
  "privateProfile": false,
  "avatarUrl": "https://.../profile/photo/object/...",
  "bio": "climbs things",
  "favoriteMovementKey": "push_ups",
  "activityMapShared": true,
  "raceInvitesFrom": "friends"
}
```

v13 validation:

- `bio` — string (trimmed server-side) or `null` to clear; >80 chars → `400`.
- `favoriteMovementKey` — string or `null` to clear; >40 chars → `400`.
- `activityMapShared` — must be a boolean; anything else → `400`.
- `raceInvitesFrom` — `"everyone"` or `"friends"` only; anything else → `400`.

Response: updated profile object (same shape as `GET /profile/me`).

### POST /profile/photo/upload-url

Request body:

```json
{
  "fileName": "photo.jpg",
  "contentType": "image/jpeg"
}
```

Response:

```json
{
  "uploadUrl": "https://.../profile/photo/upload?token=...",
  "publicUrl": "https://.../profile/photo/object/profile-avatars/...",
  "key": "profile-avatars/{userId}/{timestamp}.jpg"
}
```

### PUT /profile/photo/upload

Unsigned upload endpoint called with the signed `token` from `upload-url`.

Response:

```json
{
  "ok": true,
  "key": "profile-avatars/...",
  "publicUrl": "https://..."
}
```

### POST /profile/username/check

Request body:

```json
{
  "username": "newuser"
}
```

Response:

```json
{
  "available": true
}
```

---

## 4. Race routes

### GET /races

List races the current user created or joined.

Response:

```json
{
  "ok": true,
  "races": [
    {
      "id": "race-uuid",
      "creatorId": "user-uuid",
      "title": "Push-Up Showdown",
      "description": "First to 100 push-ups.",
      "status": "active",
      "raceType": "first_to_target",
      "verificationType": "movecheck",
      "movementType": "pushups",
      "targetValue": 100,
      "targetUnit": "reps",
      "startLineAt": "2026-07-01T00:00:00Z",
      "finishLineAt": null,
      "visibility": "crew_only",
      "inviteCode": null,
      "rules": "Use MoveCheck.",
      "viewerContext": {
        "isMember": true,
        "status": "active",
        "score": 42,
        "rank": 2,
        "previousRank": 3,
        "isLeading": false,
        "isTied": false,
        "isFinished": false
      },
      "participants": [...],
      "recentProofs": [...],
      "finalStandings": [
        {
          "userId": "user-uuid",
          "displayName": "Alex Demo",
          "profilePhotoUrl": "https://...",
          "rank": 1,
          "scoreValue": 100,
          "completedAt": "2026-07-08T00:00:00Z"
        }
      ]
    }
  ]
}
```

Race-row notes:

- `viewerContext.previousRank` is the rank the viewer held before their most
  recent proof (`move_logs.previous_rank` of their latest non-removed move in
  that race). It is `null` when the viewer has never submitted proof or is not
  a member — use it for the rank-trend arrows on list rows.
- `finalStandings` is populated only for finished races (find the viewer's
  entry by `userId` for their final place — the trophy shelf). It is `[]` for
  live races.
- `inviteCode` is insider data: it is `null` for viewers who are neither the
  creator nor an active member.

### GET /races/open

Joinable races created by or containing the viewer's active friends that the
viewer has never joined — the "Join a race" cards on Compete.

A race is listed when all of the following hold:

- not deleted, stored status `active`, and `finishLineAt` not in the past
- the viewer is not the creator and has no member row (a past `left` or
  `removed` membership also hides it)
- at least one active racer is the viewer's active friend, and that friend
  link is not blocked in either direction
- the viewer is not blocked with the creator in either direction
- `visibility` is `crew_only`, or `public_demo` with `publicJoinEnabled` —
  i.e. a scope `POST /races/:id/join` can actually enter

Ordered newest first, limited to 20. Rows have the exact same shape as
`GET /races` rows (`viewerContext.isMember` is `false`, `inviteCode` is
`null`). Supports conditional GET via `ETag` / `If-None-Match`.

Response:

```json
{
  "ok": true,
  "races": [ { "...": "same race object shape as GET /races" } ]
}
```

### GET /races/activities

The activity catalog — which movements can back a race. Public (no auth);
served with `ETag` + `Cache-Control: public, max-age=300`.

Response:

```json
{
  "ok": true,
  "catalogVersion": "...",
  "etag": "...",
  "count": 2,
  "supported": ["push_ups", "squats"],
  "activities": [
    {
      "id": "push_ups",
      "displayName": "Push-ups",
      "defaultMetric": "reps",
      "suggestedTargets": [10, 25, 50],
      "supportedFormats": ["first_to_goal"],
      "availability": "supported",
      "featured": false,
      "sortPriority": 100,
      "currentReleaseId": "rel-...",
      "racerCount": 12
    }
  ]
}
```

`racerCount` = distinct users who joined a still-active, non-deleted race of
that activity within the last 7 days (the "[N] racing" count on trending-move
cards). It is decorative: if the stats query fails the catalog still returns
with `racerCount: 0`.

### POST /races

Create a new race.

Request body:

```json
{
  "title": "Push-Up Showdown",
  "description": "First to 100 push-ups.",
  "raceType": "first_to_target",
  "verificationType": "movecheck",
  "movementType": "pushups",
  "targetValue": 100,
  "targetUnit": "reps",
  "startLineAt": "2026-07-01T00:00:00Z",
  "finishLineAt": null,
  "visibility": "crew_only",
  "rules": "Use MoveCheck."
}
```

Response: race object with the same shape as `GET /races`.

### GET /races/:id

Get a single race.

Response: same race object shape as `GET /races`.

### POST /races/:id/join

Join a race. Who may enter depends on `visibility`:

- `invite_code` — requires a valid `inviteCode` in the body
- `crew_only` — the viewer must be an active friend of the creator **or of any
  active racer** in the race (the friend-of-a-participant path behind
  `GET /races/open`)
- `public_demo` — anyone, when `publicJoinEnabled` is on
- `private` — invite path only

A block with the creator in either direction always denies; a racer blocked
with the viewer cannot supply the friend link; a member row with status
`removed` denies with `403 "You were removed from this race"` (a `left` row
reactivates instead of blocking).

Request body (optional):

```json
{
  "inviteCode": "ABC123"
}
```

Response:

```json
{
  "ok": true,
  "race": { ... }
}
```

### POST /races/:id/leave

Leave a race.

Response:

```json
{
  "ok": true,
  "race": { ... }
}
```

### PATCH /races/:id

Update race settings (creator only).

Request body: same fields as `POST /races`. Partial updates allowed.

Response:

```json
{
  "ok": true,
  "race": { ... }
}
```

### DELETE /races/:id

Soft-delete a race (creator only).

Response:

```json
{
  "ok": true
}
```

### POST /races/:id/proof

Legacy proof submission endpoint. Maps into `move_logs`.

Request body:

```json
{
  "value": 25,
  "unit": "reps",
  "notes": "Great set",
  "proofType": "manual",
  "aiActivityType": "pushups",
  "mediaUrl": "https://..."
}
```

Response:

```json
{
  "ok": true,
  "race": { ... }
}
```

### PATCH /races/:id/proofs/:proofId

Legacy proof review endpoint (creator only).

Request body:

```json
{
  "verificationStatus": "accepted",
  "verificationSummary": "Looks good"
}
```

`verificationStatus` may be `accepted`, `rejected`, or `ai_verified`.

Response:

```json
{
  "ok": true,
  "race": { ... }
}
```

### POST /races/:id/moves

New move submission endpoint.

Request body:

```json
{
  "value": 25,
  "unit": "reps",
  "source": "manual",
  "summary": "Manual entry",
  "mediaObjectKey": "race-proofs/..."
}
```

Response:

```json
{
  "ok": true,
  "move": { ... }
}
```

### GET /races/:id/moves

List moves for a race.

Response:

```json
{
  "ok": true,
  "moves": [
    {
      "id": "mv-001",
      "userId": "user-uuid",
      "value": 25,
      "unit": "reps",
      "source": "movecheck",
      "status": "verified",
      "summary": "25 push-ups verified by MoveCheck.",
      "submittedAt": "2026-07-01T12:00:00Z",
      "verifiedAt": "2026-07-01T12:00:00Z"
    }
  ]
}
```

### GET /races/:id/progress/:userId

Get progress for a specific member.

Response:

```json
{
  "ok": true,
  "progress": {
    "userId": "user-uuid",
    "progressValue": 75,
    "progressPercent": 75,
    "rankPosition": 2,
    "completedAt": null,
    "updatedAt": "2026-07-01T12:00:00Z"
  }
}
```

### PUT /races/:id/progress/:userId

Edit a member's progress (creator only).

Request body:

```json
{
  "progressValue": 100
}
```

Response:

```json
{
  "ok": true,
  "race": { ... }
}
```

### POST /races/:id/invite

Create or refresh an invite code.

Response:

```json
{
  "ok": true,
  "inviteCode": "ABC123"
}
```

### POST /races/:id/members

Add a member to a race by user id (creator only). `POST /races/:id/participants`
is the legacy alias with the same behavior.

Request body:

```json
{ "userId": "user-uuid" }
```

Response: `200` with the updated race object (same shape as `GET /races/:id`).

**"Who can race me" gate:** every add-member path — this route,
`/participants`, rematch fan-out, and crew race fan-out — checks the
*target's* `raceInvitesFrom` pref. When the target has
`raceInvitesFrom = "friends"` and the inviter is not a connected friend, the
add returns `403`:

```json
{ "ok": false, "error": "This member only races with friends" }
```

Rematch fan-out silently skips ineligible members rather than failing the
whole rematch. Existing block checks still apply on top of this gate.

---

## 5. Arena route

### GET /arena

Returns the arena snapshot for the current user.

Response:

```json
{
  "ok": true,
  "snapshot": {
    "mode": "real",
    "headerPulse": "2 boards need proof",
    "focusBoard": { ... },
    "liveBoards": [...],
    "activity": [],
    "results": [...]
  }
}
```

If `users.demo_world_enabled = 1`, the snapshot is generated from `demo_world_seed` and `demo_world_variant`.

---

## 6. Crew and leaderboard routes

### GET /crew

List current user's friends (active `crew_connections`).

Response:

```json
{
  "ok": true,
  "crew": [
    {
      "id": "user-uuid",
      "displayName": "Alex Demo",
      "username": "alexdemo",
      "memberId": "ABC123",
      "initials": "AD",
      "profilePhotoUrl": "https://...",
      "addedAt": "2026-07-01T00:00:00Z",
      "lastActiveAt": "2026-07-01T12:00:00Z",
      "level": 4,
      "racesTogether": 3
    }
  ]
}
```

`racesTogether` = count of distinct, non-deleted races where both the viewer
and that friend hold a member row with any status other than `removed` —
leaving a race still counts as having raced it, being kicked does not.

### GET /leaderboard?scope=friends|global

The weekly leaderboard. `scope` defaults to `friends`; any other value falls
back to `friends`.

- `friends` — the viewer plus their active friends (`crew_connections` in
  either direction)
- `global` — every active user

Rows:

```json
{
  "ok": true,
  "scope": "friends",
  "periodDays": 7,
  "rows": [
    {
      "userId": "user-uuid",
      "displayName": "Alex Demo",
      "profilePhotoUrl": "https://...",
      "points": 30,
      "rank": 1,
      "isMe": false
    }
  ]
}
```

- `points` = sum of `value` over the person's **verified** `move_logs` across
  all non-deleted races in the last 7 days ("total verified proof value this
  week"). Pending, rejected and removed proofs never count.
- `rank` = competition rank — `1 +` the number of people with strictly more
  points — so equal points share a rank (same convention as race standings).
- Sorted by rank ascending. The viewer's row (`isMe: true`) is always
  present, even with 0 points; the response is rank-capped (`friends`: 200,
  `global`: 50) with the viewer unioned in regardless.
- Anyone blocked with the viewer in either direction is excluded from the
  ranking entirely.
- Supports conditional GET via `ETag` / `If-None-Match`.

### POST /crew/add

Add a crew member.

Request body:

```json
{
  "userId": "user-uuid"
}
```

Response:

```json
{
  "ok": true
}
```

### POST /crew/remove

Remove a crew member.

Request body:

```json
{
  "userId": "user-uuid"
}
```

Response:

```json
{
  "ok": true
}
```

---

## 7. User routes

### GET /users/search?q=alex

Search users by username or email prefix.

Response:

```json
{
  "ok": true,
  "users": [
    {
      "userId": "...",
      "fullName": "Alex Demo",
      "username": "alexdemo",
      "profilePhotoUrl": "...",
      "memberPass": "..."
    }
  ]
}
```

### GET /users/:id

Another member's public profile card plus the viewer's relationship to them.
Accepts `?tz=<minutes-from-UTC>` (clamped to ±840) for viewer-local streak math.

- `404` when the user doesn't exist.
- `403` (`"This person is not available"`) when either side has blocked the other.

Response (`user` object; v13 fields marked ★, all additive):

```json
{
  "ok": true,
  "user": {
    "id": "...",
    "displayName": "Tess Them",
    "username": "tess",
    "memberId": "...",
    "initials": "TT",
    "profilePhotoUrl": "...",
    "isPrivate": false,
    "connectionStatus": "connected",
    "level": 4,
    "levelProgress": 0.62,
    "achievementsEarned": 7,
    "achievementsTotal": 20,
    "featuredAchievements": [ ... ],
    "earnedAchievements": [ ... ],
    "raceStats": { ... },
    "racesWithYou": 3,
    "lastActiveAt": "...",
    "bio": "lifts",                            ★ null when unset
    "favoriteMovementKey": "squats",           ★ null when unset
    "friendsCount": 6,                         ★ target's active friend count
    "activityShared": true,                    ★ target's activity-map pref
    "muted": false,                            ★ viewer muted this member
    "mutual": {                                ★ null when viewer == target
      "count": 4,
      "preview": [
        { "id": "...", "displayName": "Mutual Max", "profilePhotoUrl": "..." }
      ]
    },
    "versus": {                                ★ null when viewer == target
      "you":  { "level": 3, "wins": 2, "winRatePercent": 40, "bestStreakDays": 5, "proofsThisWeek": 4 },
      "them": { "level": 4, "wins": 5, "winRatePercent": 55, "bestStreakDays": 9, "proofsThisWeek": 6 }
    },
    "friendship": {                            ★ only when connected, else null
      "connectedSince": "...",
      "badges": [
        {
          "key": "first_race",
          "name": "First race",
          "description": "...",
          "earned": true,
          "progress": 1,
          "threshold": 1
        }
      ]
    },
    "lockedAchievements": [                    ★ catalog entries not yet earned
      { "key": "...", "name": "...", "iconKey": "...", "category": "..." }
    ]
  }
}
```

Notes on the v13 keys:

- `mutual.preview` is capped at 3 entries; `mutual.count` is the full count.
- `friendship.badges` covers `first_race` (≥1 race together), `rivals` (10
  races together), `cheer_squad` (20 reactions exchanged between the pair),
  `best_friends` (30 days connected), `streak_buddies` (both streakDays ≥7).
  `progress`/`threshold` describe pair progress; these are pair-scoped, not
  global achievements.
- `lockedAchievements` exposes only `key`, `name`, `iconKey`, `category` — no
  progress values for unearned entries.
- `muted` is visible only to the muter; the target's own view always returns
  `false`.
- `versus` is present for any non-self viewer (not only friends).

### GET /users/:id/activity?days&tz

Another member's activity map — same shape as `GET /profile/activity`
(`days` clamped 7–366, `tz` clamped ±840).

- `404` when the user doesn't exist.
- `403` when either side has blocked the other.
- When the target has `activityMapShared = false`: `200` with
  `{ "ok": true, "shared": false, "days": [] }`.
- Otherwise: `200` with `{ "ok": true, "shared": true, "days": [{ "date": "YYYY-MM-DD", "proofs": 3 }, ...] }` (verified proofs per day, ascending).

---

## 8. Progression route

### GET /progression?tz

The member's Nuvo Level / XP / achievement payload plus a `record` strip.
Accepts `?tz=<minutes-from-UTC>` for viewer-local streak math. Supports ETag
validation (`304` when unchanged; the tag covers the record fields below).

Response (`record` object; v13 fields marked ★):

```json
{
  "ok": true,
  "progression": { ... },
  "record": {
    "wins": 5,
    "active": 2,
    "finished": 9,
    "winRatePercent": 55,
    "friends": 6,           ★ active friend connections
    "streakDays": 3,        ★ consecutive verified days ending today/yesterday
    "bestStreakDays": 9,    ★ longest verified-day run ever
    "proofsThisWeek": 4     ★ verified proofs in the trailing 7 local days
  }
}
```

Streaks are derived from verified `move_logs` in the viewer's local day — a
streak stays alive when the latest verified day is today or yesterday.

---

## 9. Mutes routes

Mutes are private to the muter: the target is never notified, can't read the
state, and keeps all their permissions. All mute/unmute calls are idempotent.

Muting a **user** removes their activity items from the muter's `GET /crew/feed`
and suppresses in-app and push notifications from that actor to the muter.
Muting a **crew** additionally removes feed items from every race linked to
that crew.

### POST /mutes/users/:id

- `400` when muting yourself (`"Cannot mute yourself"`).
- `404` when the target user doesn't exist.
- `200` → `{ "ok": true, "muted": true }` (re-muting is a no-op).

### DELETE /mutes/users/:id

`200` → `{ "ok": true, "muted": false }` (unmuting a non-muted user still returns `200`).

### POST /mutes/crews/:id

- `404` when the crew doesn't exist.
- `200` → `{ "ok": true, "muted": true }`.

### DELETE /mutes/crews/:id

`200` → `{ "ok": true, "muted": false }`.

### GET /mutes

The caller's own mute list.

```json
{
  "ok": true,
  "users": [
    {
      "id": "...",
      "displayName": "Muted Max",
      "username": "max",
      "memberId": "...",
      "initials": "MM",
      "profilePhotoUrl": "...",
      "mutedAt": "..."
    }
  ],
  "crews": [
    { "id": "...", "name": "The Crew", "memberCount": 5, "mutedAt": "..." }
  ]
}
```

---

## 10. Error responses

All errors follow this shape:

```json
{
  "ok": false,
  "error": "Human-readable message"
}
```

Common HTTP status codes:

- `400` — bad request / validation error
- `401` — missing or invalid access token
- `403` — forbidden (not creator, etc.)
- `404` — resource not found
- `409` — conflict (username taken, already joined, etc.)
- `500` — unexpected server error

---

## 11. Notes for the Flutter app

- Continue using `POST /races/:id/proof` for all proof submissions.
- Continue using `PATCH /races/:id/proofs/:proofId` for proof review.
- New `moves` endpoints are optional and can be adopted later.
- Profile photo flow is unchanged from the app's perspective.
- All v13 additions (migration 0048) are additive keys — older app builds ignore
  them. `privateProfile`/`isPrivate` remain `false` for compatibility; there
  are no private profiles.
