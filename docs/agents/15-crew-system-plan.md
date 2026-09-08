# Nuvo Crew System — Product + Technical Plan

> **SUPERSEDED by [19-social-platform-contract.md](19-social-platform-contract.md).** Kept for design rationale only; where it disagrees with doc 19, doc 19 wins.

Status: **SUPERSEDED by [19-social-platform-contract.md](19-social-platform-contract.md)** — kept for design rationale. Original note: PLAN ONLY. Reviewed together with
[16-notification-system-plan.md](16-notification-system-plan.md) and
[17-qr-sharing-plan.md](17-qr-sharing-plan.md) — one invite/identity model
across all three.

---

## 0. What exists today (build on this, don't replace)

- `crew_connections(user_id, crew_user_id, status)` — a **directional follow**.
  `status = 'active'`. Used for the private-profile allowlist
  (`lib/privacy.ts` `resolveRaceMemberVisibility` / `canViewFullProfile`).
- `GET /crew`, `POST /crew` (add by userId), `DELETE /crew/:id`.
- `member_passes(user_id, member_id, pass_slug)` — a public **member ID**
  (human handle) + a pass card. This is the shareable identity.
- Client: `PublicUser`, `pass_screen.dart` (search + "Your crew" list),
  `RaceController.getCrew/addCrewUser/removeCrewUser`.
- `blocked_users(user_id, blocked_user_id)`.

**Decision: "crew" stays a per-person connection graph, NOT a named group.**
A named/owned "Crew" (a team with a roster) is a *later, separate* concept —
call it a **Squad** if we build it — so we don't overload the word now. The
rest of this doc plans the connection graph to a finished state, then sketches
Squads as a follow-on.

---

## 1. Crew = your people (the connection graph)

### 1.1 Model

Promote `crew_connections` from a directional follow to a **mutual connection
with a lifecycle**:

```
crew_connections(
  id, user_id, crew_user_id,
  status TEXT,          -- pending | active | declined | removed
  requested_by TEXT,    -- user_id who initiated
  created_at, updated_at
)
```

- One row per ordered pair; a connection is two rows kept in sync (or one row
  + a `direction` — pick one, one-row+mutual-flag is simpler). **Recommend:**
  one canonical row keyed `least(a,b), greatest(a,b)` with `a_accepted`,
  `b_accepted` booleans. `active` when both true.
- `pending` → the other person sees a request (notification: `crew_request`).
- No request needed to connect with a **public** profile you found by member ID
  / QR — that's an immediate `active` (like following). A request is only
  required to connect with a **private** profile. (Keeps friction low, matches
  "search by member ID" today.)

### 1.2 Roles / admin

None. A connection graph has no owner. Either side can `removeCrewUser` →
`status = 'removed'` on the canonical row; re-add is a fresh request/accept.

### 1.3 Privacy

- Public profile: connectable immediately; name + photo visible everywhere.
- Private profile: connect = a `pending` request they must accept; until then
  you see only their member ID / `@username`.
- Blocking (`blocked_users`) always wins: hides identity, removes any
  connection, prevents new ones, hides from search. Already enforced in
  `resolveRaceMemberVisibility`.
- **Co-race identity is independent of crew** — being in the same race already
  reveals race identity (name + photo) via `coRacerIds` in
  `resolveRaceMemberVisibility`. Crew adds: visible in the profile screen,
  visible in "closest race" / crew leaderboards, eligible for
  `crew_member_joined` notifications.

### 1.4 Member limits

Soft cap **500** connections (abuse ceiling, not a product limit). Search
results 10. No pagination on the crew list until someone hits ~100 — then
cursor-paginate `GET /crew?cursor=`.

---

## 2. API (crew connection graph)

| Route | Purpose | Notes |
|---|---|---|
| `GET /crew` | active connections | `{ members: PublicUser[] }`, cursor later |
| `GET /crew/requests` | incoming `pending` | drives the requests badge |
| `POST /crew` `{ userId \| memberId }` | connect / request | public → `active`, private → `pending` + notification |
| `POST /crew/requests/:id/accept` | accept | → `active`, notify requester |
| `POST /crew/requests/:id/decline` | decline | → `declined`, silent |
| `DELETE /crew/:userId` | remove connection | either side |
| `GET /crew/discover` | *(later)* suggestions | mutuals-of-mutuals, co-racers you're not connected to |

All under `requireAuth`. Reuse `resolveRaceMemberVisibility`-style anonymization
for any list that can contain private non-connections (search, discover).

---

## 3. Crew surfaces (client)

Follow [18-data-freshness-contract.md](18-data-freshness-contract.md):

- **`CrewController` / `crewControllerProvider`** — `CrewState { members,
  requests, loading, refreshing, error }`. `revalidate()` on Pass-tab focus
  and app resume. `clearCrew()` on sign-out.
- `onMutated` → `raceController.markParticipantsStale()` (a new connection can
  reveal identity in a shared race) and → a `notifications` badge refresh.
- **Pass screen** gains: an incoming-requests section (accept/decline inline),
  the existing search + crew list, and a "Find people" entry that opens the QR
  scanner (see 17).
- **Empty states** per the contract: "No crew yet" / "No pending requests".
- **Crew leaderboard** (new, small): within a race detail, a "Your crew" filter
  on the leaderboard showing only connected racers + you. Pure client filter
  over the existing participants list — no new endpoint.
- **Crew activity** — a lightweight feed ("Riley finished Squat Sprint",
  "Sam joined Morning Miles"). **Defer to a v2**; it needs an events table and
  overlaps heavily with notifications (§16). If built: one
  `crew_activity(actor_id, verb, race_id, created_at)` table, `GET /crew/feed`,
  fan-out on write is unnecessary at this scale (query `WHERE actor_id IN
  (my active connections)`).

---

## 4. Race creation with crew

- Composer "Invite racers" step: show the crew list first (one-tap add), then
  search, then "Share link / QR" (17). Adding a crew member = `POST
  /races/:id/participants` (already exists) — they appear immediately
  (write-through, §4 of the contract) and get an `invited_to_race`
  notification (§16).
- A **private race** + crew: only invited people can join; the invite link
  (17) carries a signed token.

---

## 5. Squads (named groups) — follow-on sketch, NOT this phase

If a named team is wanted later:

```
squads(id, name, slug, owner_id, visibility, avatar_key, created_at)
squad_members(squad_id, user_id, role)   -- role: owner | admin | member
```

- Owner/admins invite, remove, rename, set public/private.
- Public squads are discoverable (`GET /squads/discover`); private need an
  invite/QR.
- A squad can co-own a **recurring** race; a squad leaderboard aggregates
  member scores across squad races.
- Squad QR (17) = join the squad. Squad notifications (§16):
  `squad_invitation`, `squad_member_joined`, `squad_race_created`.
- Member limit ~100; one owner, transferable.

Do not start Squads until the connection graph above is shipped and used.

---

## 6. Cross-references

- Identity/anonymization: `resolveRaceMemberVisibility` in
  `server/worker/src/lib/privacy.ts` — the single policy. Crew adds ids to the
  `crewIds` set.
- Invites & QR: [17-qr-sharing-plan.md](17-qr-sharing-plan.md) — a crew invite
  and a race invite share one signed-token + universal-link format.
- Notifications: [16-notification-system-plan.md](16-notification-system-plan.md)
  — `crew_request`, `crew_request_accepted`, `crew_member_joined`,
  (`squad_*` later).
- Freshness: `CrewController` plugs into
  [18-data-freshness-contract.md](18-data-freshness-contract.md) unchanged.
