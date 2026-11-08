# CREW_SOCIAL.md — v13 spec mapping: Crew tab, Crew page, My Nuvo code

Scope: v13 spec sections **"Crew tab"** (PROTOTYPE_V13_SPEC.md lines 66–77),
**"Crew page"** (79–87) and **"My Nuvo code"** (118–119), plus the friend
graph they depend on (friends, requests, search, scan, public profile entry
points). Phase A documentation only — nothing here is an edit instruction for
no-touch files.

Legend: **KEEP** = exists today, restyle only · **REPLACE** = exists but must
change behavior/shape · **DELETE** = remove · **NEW** = no code exists ·
**MISSING** = no server data; proposed additive API + migration below.

---

## 0. Terminology: crews vs squads — which code is canonical

Three feature dirs split the social surface. The naming is confusing on
purpose only at the API layer — in code it is consistent:

| Layer | Dir | API | Product word | Canonical for |
|---|---|---|---|---|
| Person-to-person links | `lib/features/crew/` | `/crew/*` | **friend** | Friends list, friend requests, public profile cards |
| Named groups | `lib/features/squads/` | `/squads/*` | **crew** | Crew groups (create/join/roles/races/settings) |
| Cross-cutting social | `lib/features/social/` | `/invites`, `/crew/feed`, `/reactions` | — | Invites, QR/scan, activity feed, deep links |

`squad_api.dart:17-18` states the rule: "The API calls it a squad; the app
always says 'crew'." **`lib/features/squads` + `server/worker/src/routes/squads.ts`
is the canonical crew-group stack.** `lib/features/crew` is the friends stack
— it was written before the product model renamed "crew" (people) to
"friend" and "squad" to "crew". Do not merge the dirs; keep the API nouns
(`/crew` = friend graph, `/squads` = crews) and only fix app-side copy.

`docs/API_CONTRACT.md` §6 documents only the `/crew` friend endpoints — it
predates migration 0046 and does not cover `/squads`, `/invites`, `/reactions`
or `/crew/feed`. Those are documented below from route code.

Current bottom nav (`lib/core/widgets/bottom_nav.dart:31-56`): **Arena ·
Compete · Friends (`/pass`) · Profile** — 4 tabs. `/pass` renders
`PassScreen` (router.dart:92), the combined friends+crews+feed surface.
**v13 renames this tab to "Crew" and folds crews into it** — see §1.0.

`lib/features/squads` is behind a server flag: `NuvoFlags.crews`
(`lib/core/config/nuvo_flags.dart:20,42`), set from a remote config body key
`crews`. The PassScreen "Crews" entry row is hidden when the flag is off
(`pass_screen.dart:732-758`).

### Current route map (all verified in `lib/app/router.dart`)

| Route | Screen | File |
|---|---|---|
| `/pass` (tab) | `PassScreen` ("Friends") | `pass/presentation/pass_screen.dart:50` |
| `/crews` | `CrewGroupsScreen` | `squads/presentation/crew_groups_screen.dart:151` |
| `/crews/:id` | `CrewGroupDetailScreen` | `crew_groups_screen.dart:648` |
| `/crews/:id/settings` | `CrewSettingsScreen` | `crew_groups_screen.dart:1738` |
| `/crews/join/:code` | `CrewJoinScreen` | `crew_groups_screen.dart:1534` |
| `/crew/add` | `AddCrewScreen` | `social/presentation/add_crew_screen.dart:24` |
| `/my-nuvo` | `MyNuvoScreen` | `social/presentation/my_nuvo_screen.dart:31` |
| `/scan` | `QrScanScreen` | `social/presentation/qr_scan_screen.dart:25` |
| `/invite/:token` | `InviteScreen` | `social/presentation/invite_screen.dart:34` |
| `/u/:id` | `PublicProfileScreen` | `crew/presentation/public_profile_screen.dart:39` |
| `/u/:id/badges` | `PublicBadgesScreen` | `crew/presentation/public_badges_screen.dart` |
| `/race/:id/invite` | `InviteCrewScreen` | `races/presentation/invite_crew_screen.dart:22` |

---

## 1. "Crew tab" (spec lines 66–77)

### 1.0 Header: "Crew" + QR button (→ My Nuvo code) + "Add friend" (→ scan)

- **Current:** `PassScreen` header `_CrewHeader` (pass_screen.dart:2802) shows
  title **'Friends'**, a search icon toggling inline search, a QR icon →
  `/my-nuvo`, and `NotificationBell` (line 2874).
- **Verdict: REPLACE.** Retitle to "Crew", keep QR → My Nuvo code; spec says
  the second button is "Add friend" and parenthetically "(opens scan)".
  Reading strictly, "Add friend opens scan" is odd; the sane resolution is a
  single add-friend affordance opening the add-friend hub (`/crew/add`,
  AddCrewScreen), which already offers search + scan + my-code
  (`add_crew_screen.dart:168-187`). Flag for product confirmation: literal
  spec = open `/scan` directly.
- Tab rename: `nuvoDestinations` label 'Friends' → 'Crew'
  (`bottom_nav.dart:44-49`); path `/pass` can stay or become `/crew` with a
  redirect — either is additive (router.dart:89-95 `_tabScreenFor`).

### 1.1 "Your crews" cards

Spec: crew icon tile in **crew color**, name, `"[N] members · Run by Alex"`,
**my rank this week** ("#2 · this week"), **member faces (+N)**, **next
recurring race** ("Pushup Monday · In 2 days"). Below: "+ Start a crew"
(dashed) + "Join with a code".

- **Current:** `CrewGroupsScreen` list — `_GroupCard`
  (crew_groups_screen.dart:383) shows generic `NuvoCrewIcon` tile (no color),
  name, `"N in crew · M races"`, `_CodeChip` join code. `_AddPanel` (line 265)
  = Start a crew / Join with a code / Scan a crew QR. Empty state has same
  two CTAs (line 218-230).
- **Verdict: KEEP the panel + cards; REPLACE card content.** New fields needed:

| Spec element | Data today | Verdict |
|---|---|---|
| Crew color + icon tile | none — `squads` table has no color/icon columns | **MISSING** → `ALTER TABLE squads ADD color_key, icon_key` (0048) |
| "Run by Alex" | `isOwner` bool only; owner name not serialized | **MISSING** → additive `ownerName` on `GET /squads` + detail |
| My rank this week | `standings` exist (all-time only, `computeSquadStandings`) | **MISSING** → week-windowed standings (see §2.4) |
| Member faces (+N) | `memberCount` int only on list | **MISSING** → additive `memberPreviews` array on `GET /squads` |
| Next recurring race | no recurrence anywhere | **MISSING** → `squad_recurring_races` table (see §2.5) |
| "+ Start a crew" dashed / "Join with a code" | `_AddPanel` exists | KEEP, restyle to dashed |

### 1.2 "Racing right now" — horizontal friends row

Spec: photo + small **movement badge** + name + what they're doing → profile.

- **Current:** `_PeopleStrip` (pass_screen.dart:2895): "You" tile + friend
  faces ordered by presence + trailing "Add" tile; `_StatusPill` shows
  Racing / 🔥 / Active derived from `racingIds`/`hotIds`/`lastActiveAt`
  (computed pass_screen.dart:506-549). `_CrewRacesNow` (line 2275) renders
  shared live/active races as cards below.
- **Verdict: KEEP, restyle.** Data is all client-derivable today:
  `racingIds` = crew members inside an active shared race
  (RaceController.races + `crewIds`); movement badge from `Race.activityId`/
  `movementType` on the shared race. "What they are doing" = race title or
  movement. Tap → currently `_openPerson` sheet; spec wants profile →
  `/u/:id` (or keep sheet — flag; public profile exists).
- Data: `GET /crew` (presence `lastActiveAt`, crew.ts:88-94) +
  `GET /races` (shared races). No new API.

### 1.3 Friend request card (lilac)

Spec: "Sam Rivera wants to race" · "Friends with Priya and Alex" · Accept.

- **Current:** `_RequestSurface` (pass_screen.dart:3369): incoming rows with
  Decline/Accept, outgoing rows with Pending + cancel. Same queue on
  `AddCrewScreen` ("Wants to be friends", add_crew_screen.dart:217-247).
- **Verdict: KEEP data, restyle to featured lilac card.**
  Mutuals: `mutualCount` is returned **only on `/users/search` rows**
  (users.ts:73-82) — **not** on `GET /crew/requests` rows (crew.ts:98-124).
  "Friends with Priya and Alex" needs names, not a count →
  **MISSING → additive `mutualCount` + `mutualNames[]` on `/crew/requests`.**
- Endpoints exist: `POST /crew/requests/:id/accept`, `/decline`,
  `DELETE /crew/:id` (cancel outgoing). KEEP.

### 1.4 "What your crew is doing" feed

Spec per item: photo + kind badge (logged / earned a badge / passed you),
text ("[Name] logged 14 pushups"), race color + time, big number chip for
logs, **cheer button (flame + count) that toggles**.

- **Current:** `_FeedColumn` (pass_screen.dart:933) under the Activity lens —
  `CrewActivityItem` from `GET /crew/feed` (conditional GET at
  crew_activity.dart:68), typed
  by `race_events.event_type` or notification category; headline composed
  client-side (crew_activity_models.dart:149-189); `_ReactionBar`
  (pass_screen.dart:2643) toggles 🔥/👏/💪 via `POST/DELETE /reactions`
  (reactions.ts:151,235). `race_live` items render `_LiveRaceCard`
  (pass_screen.dart:2760).
- **Verdict: KEEP almost everything.**
  - "cheer button (flame + count)" = the `fire` reaction with aggregate
    count — exists (`kReactionEmojis`, crew_activity_models.dart:13).
  - "big number chip for logs" — needs the logged value in the item:
    `attempt_completed` payloads carry `score`; `progress_accepted`
    payload contents are **unverified** (server writes payload_json from
    race_events — the value key needs a server-side confirm before build).
  - "earned a badge" items — **MISSING**: feed sources are `race_events` +
    3 crew notification categories; achievements (migration 0042) are not
    projected into `/crew/feed`. Additive: extend feed union to
    achievement events, or emit `badge_earned` race-scoped event.
  - "race color" — races have no color field server-side. Assign color
    client-side by hashing `raceId` over the spec palette (coral/sun/lilac/
    mint/sky) — deterministic, no API change. Same trick covers §1.1 crew
    color until 0048 lands.
- Data: `GET /crew/feed?limit&cursor` (ETag'd), `POST /reactions`,
  `DELETE /reactions`. Entities: `race_event | move_log | crew | race`;
  emojis `fire | clap | muscle` (reactions.ts:24,27).

### 1.5 "Your friends' crews" — Ask to join / Requested

Spec: crew icon tile, name, faces, "Priya's crew · 6 members",
"Ask to join" → "Requested".

- **Current: nothing.** Crews are join-by-code only; `POST /squads/join` is
  instant membership (squads.ts:279-348), `GET /squads/:id` 404s for
  non-members (squads.ts:358-360). No discovery, no approval flow.
- **Verdict: NEW + MISSING.** Proposed additive API + migration in §6:
  `GET /squads/discover` (friends' crews preview), squad public preview,
  join requests via `squad_members.status='requested'`, owner/admin
  approve/decline.

---

## 2. "Crew page" (spec lines 79–87)

### 2.0 3-dot menu

Spec: members → Share crew, Copy invite link, Mute crew, Leave crew (red,
confirm). Non-members → Report crew.

- **Current:** gear icon → `CrewSettingsScreen` (rename, crew code copy/
  share, About rows, Leave w/ confirm, owner-only Delete)
  (crew_groups_screen.dart:1738-2039). `_shareCrew` (line 116) shares
  `https://getnuvo.net/c/<joinCode>` via `share_plus`.
- **Verdict:**
  - Share crew / Copy invite link — KEEP (exists; move to overflow menu).
  - Leave crew — KEEP (confirm exists, line 1793).
  - **Mute crew — MISSING** → `ALTER TABLE squad_members ADD muted_at` +
    `POST /squads/:id/mute {on}` (0048). Semantics: suppress crew
    notifications for me (wire into notification_policy).
  - **Report crew — MISSING** → `POST /reports/squads/:id` inserting
    `target_type='squad'` into existing `reports` table (reports.ts:46-49
    shows the pattern; target_type is free TEXT). Also needed for §1.5
    non-member previews.

### 2.1 Header: icon tile, name, "[N] members · since [month year]", bio

- **Current:** `_CrewSummaryCard` (crew_groups_screen.dart:1000): generic
  crew icon, name, "N members · M races", `_RoleChip` (owner gold / admin
  blue, line 1100).
- **Verdict: KEEP, replace content.**
  - `squads.created_at` exists in DB (0046_squads.sql:13) but is **not
    serialized** → additive `createdAt` on detail + list.
  - **Bio — MISSING** → `ALTER TABLE squads ADD bio TEXT`; PATCH
    `/squads/:id` already accepts partial body (squads.ts:617) — extend to
    `{name, bio, colorKey, iconKey}`.
  - Icon tile + color — MISSING (see §1.1).

### 2.2 Buttons: "Start a crew race" + "Invite"

Spec: blue "Start a crew race" opens New race with **all members invited**
(non-members see "Ask to join"/"Requested"); "Invite" opens My Nuvo code.

- **Current:** "Add race" (owner/admin only) → bring-race sheet →
  `/races/new` with `RaceCreatePrefill(crewId, crewName)`
  (`_bringRace`, crew_groups_screen.dart:685). "Add people" → `_CodeCard`
  modal with crew QR + code + Share (line 1421).
- **Verdict:**
  - Start a crew race — REPLACE. v13 gives **every member** the button;
    `POST /squads/:id/races` currently 403s non-admin members
    (squads.ts:572-575). Proposed: allow any active member to link a race
    they created (contract-compatible; same endpoint/shape). "All members
    invited" = today's fan-out: `addToRace` per member with `race_invited`
    notification (squads.ts:126-159, 602-613). Keep.
  - Invite → My Nuvo code — spec routes to the personal QR. Crew QR also
    exists (`_CodeCard`, `https://getnuvo.net/c/<code>` → `CrewJoinDestination`,
    nuvo_destination.dart:41-43,145-151). KEEP both surfaces; spec's choice
    is fine — note the crew-code path must stay reachable (settings + sheet).
  - Non-member "Ask to join"/"Requested" — NEW (see §1.5/§6).

### 2.3 Stats triple: Crew wins, Races, Crew streak

- **Current:** only member/race counts.
- **Verdict: MISSING.** Races = raceCount (exists). Crew wins — derivable
  from `computeSquadStandings` (`squadStandings.ts`; per-member `wins`
  already returned) — propose additive `stats.wins` = count of linked races
  whose winner is a member. Crew streak — **MISSING**; needs a definition
  (e.g. consecutive days with ≥1 member proof in a linked race). Propose
  server-computed `stats.streakDays` on detail; client never computes.

### 2.4 Crew leaderboard: This week / All time

Spec: medal circles, photo, name, Owner/Admin/Member tag, points; your row
tinted blue.

- **Current:** `standings` are computed and serialized by `GET /squads/:id`
  (squads.ts:497,547-561 → `CrewGroupStanding{rank,points,wins,races,isYou}`)
  **but never rendered** — `_CrewTabBar` shows only "Races" + "Members"
  despite its comment promising "three views: standings, people, races"
  (crew_groups_screen.dart:1134). Dead data today.
- **Verdict: KEEP data + NEW UI.** This week split — **MISSING**: standings
  aggregate all linked races ever. Propose additive
  `GET /squads/:id/standings?period=week|all` (same row shape) or a
  `standingsWeek` field on detail. Week = ISO week bucket of
  `race_progress.updated_at`/race window — define server-side.
  Role tags exist (`members[].role`, effectiveRole squads.ts:73-89).

### 2.5 Recurring crew races + auto-join

Spec: icon tile, name, "Every Monday · First to 100", "Live now"/"In 2 days"
tag, auto-join faces, **Auto-join toggle per race**, "+ Add" → New race
prefilled with crew.

- **Current: nothing.** No recurrence fields on `races`, no scheduler.
- **Verdict: NEW + MISSING.** Proposed `squad_recurring_races` table (0048)
  + `squad_recurring_optouts` (per-member auto-join off); materialization
  either via Worker cron or lazily on read (spawn next race when the
  weekday rolls). Endpoints in §6. Auto-join faces = opt-out list ⊖ members.
- Adjacent existing behavior to reuse: joining a crew already auto-pulls
  you into its **active** linked races (squads.ts:330-345) — the auto-join
  mechanic exists, it just isn't recurring.

### 2.6 Crew battle: "[crew] vs [rival crew]"

Spec: split bar, points each side, "Ends Sunday".

- **Current: nothing.**
- **Verdict: NEW + MISSING.** `squad_battles` table (0048) + endpoints;
  scoring = member proof totals inside the window (server-computed, like
  standings). Needs an accept step (rival crew admin accepts) — mirror the
  friend-request pattern.

### 2.7 Members grid

Spec: photo, name, Owner/Admin tag; tap → profile; back → crew page.

- **Current:** `_MembersTab` rows — `NuvoAvatar`, name, @username, Owner/
  Admin chip, manage sheet for make/remove-admin + remove member
  (crew_groups_screen.dart:1198-1313, sheet :783-873).
- **Verdict: KEEP, restyle rows→grid; wire tap → `/u/:userId`** (tap today
  only opens the manage sheet when permitted). Back → pop → `/crews`
  already guarded by `_leave` fallback (line 36-42).

---

## 3. "My Nuvo code" (spec lines 118–119)

Spec: My code / Scan segmented control. My code: QR with Nuvo logo,
@username, Share, Copy link. Scan: camera → finds code → shows person +
"Add friend" (confetti when added).

- **Current — two screens, to become one segmented screen:**
  - `MyNuvoScreen` `/my-nuvo` (my_nuvo_screen.dart:31): mints a
    `crew_connect` invite via `inviteRepositoryProvider.mintMyCrewInvite()`
    → `POST /invites {kind:'crew_connect'}` (invite_api.dart:80-104,
    invites.ts:171-173 — targetId forced to caller, reusable token) →
    `QrImageView` of `invite.url`, code chip, "Share my Nuvo"
    (`share_plus`), `NuvoCopyButton`, "Scan a code" → `/scan`.
  - `_MyQrSheet` (`my_qr_sheet.dart:21`) — duplicate sheet version, same
    mint + QR + share/copy.
  - `QrScanScreen` `/scan`: `camera` package stream →
    `BarcodeScannerService` (`google_mlkit_barcode_scanning`, QR only)
    via shared `inputImageFromCameraImage` — **the same no-touch camera
    bridge** (`races/ai/camera_image_converter.dart`). Non-Nuvo payloads
    toast "That isn't a Nuvo code." (qr_scan_screen.dart:141-156); a Nuvo
    URI → `NuvoDestination.tryParse` → `/invite/:token` → `InviteScreen`
    person preview → explicit accept → `POST /invites/:token/accept`
    (crew connect; invites.ts:406+).
  - Paste-a-link fallback bar exists on the scanner (line 302-355).
- **Verdict: KEEP both surfaces; NEW segmented parent** combining them.
  - QR "with the Nuvo logo" — `QrImageView` supports `embeddedImage`;
    `assets/branding/` exists. NEW styling only.
  - "@username" — shown via identity hero already.
  - "shows the person with an Add friend button" — today the flow lands on
    `InviteScreen` preview → Accept. Equivalent; keep (it handles
    race_join + crew_connect uniformly). "Confetti when added" — see §5.2.
  - Scan screen is `_cameraPage` + `KeepScreenAwake` (router.dart:65-66);
    keep that behavior under the segment.
- Packages: **no pubspec change needed** — `qr_flutter` (encode),
  `google_mlkit_barcode_scanning` + `camera` (scan), `share_plus`,
  `app_links`, `cached_network_image`, `google_fonts` (Manrope available).
  `mobile_scanner` is deliberately absent (pubspec.yaml:57-60 comment).
  **No `confetti` package** — spec's confetti must be a custom
  `flutter_animate`/`rive` burst or a new dep (pubspec is no-touch → flag).

---

## 4. Real features in current code the v13 spec doesn't show

Keep all of these — they map onto v13 surfaces or live in settings/overflow:

| Feature | Where today | v13 home |
|---|---|---|
| Member search (`GET /users/search`, 280 ms debounce, mutual count) | pass_screen.dart:115-153; add_crew_screen.dart:45-80 | Crew tab "Add friend" flow |
| Outgoing request cancel | `_SentRequestRow` → `DELETE /crew/:id` (pass_screen.dart:3566) | Request card overflow |
| Remove friend / Block / Unblock / Report user, race, content | public_profile_screen.dart:151-333; `crew_api.dart:323-336` | Public profile "Friends"/3-dot sheets |
| Rename crew / Delete crew / roles (make-remove admin) / remove member / remove crew race / bring existing race | `CrewSettingsScreen`, `CrewGroupDetailScreen` | Crew page settings + member manage sheet |
| Join-code copy + share + crew QR | `_CodeCard` (crew_groups_screen.dart:1421) | Crew page "Invite"/overflow |
| Presence pills ("Active now / Xh ago") | `crew_presence.dart`; `last_active_at` (0028) | Racing-right-now strip |
| `_PersonSheet` flip card (identity + head-to-head rivalry) | pass_screen.dart:3895+ | Optional; spec sends faces → profile instead |
| Feed lenses People/Activity + post CTAs (Take it back, Rematch, Join/Open race, Race X) | pass_screen.dart:318-448 | Crew tab feed |
| Member pass (`GET /pass/me` → memberId/passSlug/shareUrl, pass.ts:11-27) | `memberPassProvider` | My Nuvo code "Copy link" — note: `shareUrl` is `…/pass/<slug>` (permanent) vs invite `…/j/<token>` (expirable). Two parallel link models — pick one for spec, keep both server-side |
| Invite engine: mint/preview/accept/revoke, expiry, max_uses, 20/hr rate cap | invites.ts:153-503 | Underpins My Nuvo code + share sheets |
| Deep links/universal links: `nuvo://j/`, `/j/`, `/c/`, `/u/`… | `nuvo_destination.dart`, `deep_link_controller.dart`, `pending_destination_store.dart` | unchanged |
| `InviteCrewScreen` (invite friends to a race + race invite code card) | invite_crew_screen.dart:22 | Race flow (out of scope but adjacent) |
| `race_live` spectator cards in feed | pass_screen.dart:2760 | Crew tab feed |
| Presentation-demo fixtures for crew/feed | `presentation_demo.dart` | keep working |

---

## 5. Conflicts: v13 spec vs AGENTS.md / product model

1. **"private profile" toggle** (spec Settings §"Privacy: private profile")
   vs product model "Private profiles do not exist" + server truth
   (`canSeeIdentity` always returns true, crewLifecycle.ts:163-170;
   `users.ts` still emits `isPrivate:false` as a legacy key). **Resolution:
   drop the toggle; privacy = blocked-users management only.**
2. **"Challenge [Name]"** button (spec Profile §public profile) — "challenge"
   is banned vocabulary. **Resolution: "Race [Name]"** (existing copy
   already says "Race $first", pass_screen.dart:4176).
3. **Tab set**: product-model table lists separate Friends and Crews tabs;
   nav only ever had 4 slots and v13 says Arena/Compete/**Crew**/Profile.
   **Resolution: merge friends+crews into "Crew"** (rename `/pass`
   destination label); both feature sets already live on PassScreen.
4. **"Add friend" opens scan** (spec Crew tab header) — literal reading is
   odd; `AddCrewScreen` already unifies search+scan+my-code. **Resolution:
   open the add-friend hub (which contains scan), unless product wants the
   camera first.**
5. **"Crew battle"** — 'battle' is not on the banned list (betting/gambling
   are); ship with the name or rename "Crew vs crew" if it reads aggressive.
6. **"Ask to join"/"Requested"** introduces a crew approval gate the
   product model doesn't mention (it only specifies code/QR joins).
   Additive and consistent; keep code-join as the instant path, requests
   only for discovered friends' crews.
7. **Member pass vs invite link** — two link models (§4). Spec's "Copy link"
   should copy the invite URL the QR encodes (consistent), but the pass
   slug link must keep working for old shares.
8. **`isPrivate` legacy key** — keep emitting `false` for old builds; never
   surface in v13 UI.
9. No product-language violations found in scoped code: "crew" used only
   for groups, "friend" only for person links (AddCrewScreen title already
   reads "Add friend", add_crew_screen.dart:151).

### 5.1 No-touch files for the later build

`auth_api.dart`, `auth_repository.dart`, `auth_controller.dart`,
`auth_gate.dart`, `secure_token_store.dart`,
`ai_motion_proof_screen.dart`, `motion_validators.dart`,
`pose_detector_service.dart`, `camera_image_converter.dart` (QR scan
reuses it — read only), iOS native files, `pubspec.yaml`/`.lock`,
`server/worker/` in Phase B except the additive migration + additive route
code approved per-change. Also avoid casual edits to `race_api.dart`,
`race_repository.dart`, `race_controller.dart` (read for shared races).

---

## 6. MISSING data → proposed additive API + migration 0048

Existing crew/squad tables: `squads`, `squad_members`
(role `owner|admin|member`, status `active|left|removed`),
`squad_races` (0046); `crew_connections` (status `active|pending|declined|
removed`, +requested_by/updated_at via 0014), `invites`/`invite_uses`,
`activity_reactions` (0031), `reports`, `blocked_users`, `member_passes`,
`users.last_active_at` (0028).

### 6.1 Migration `0048_crew_v13.sql` (additive only)

```sql
-- Crew identity (icon/color/bio) — client maps keys to assets.
ALTER TABLE squads ADD COLUMN bio TEXT;
ALTER TABLE squads ADD COLUMN color_key TEXT;   -- coral|sun|lilac|mint|sky
ALTER TABLE squads ADD COLUMN icon_key TEXT;

-- Mute crew (per member).
ALTER TABLE squad_members ADD COLUMN muted_at TEXT;
-- Join requests reuse squad_members.status with new value 'requested'
-- (no schema change needed; status is free TEXT).

-- Recurring crew races.
CREATE TABLE IF NOT EXISTS squad_recurring_races (
  id TEXT PRIMARY KEY,
  squad_id TEXT NOT NULL REFERENCES squads(id),
  title TEXT NOT NULL,
  activity_id TEXT,
  race_type TEXT,
  target_value INTEGER,
  target_unit TEXT,
  weekday INTEGER NOT NULL,             -- 0..6
  auto_join INTEGER NOT NULL DEFAULT 1,
  active INTEGER NOT NULL DEFAULT 1,
  last_spawned_at TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS squad_recurring_optouts (
  recurring_id TEXT NOT NULL REFERENCES squad_recurring_races(id),
  user_id TEXT NOT NULL,
  PRIMARY KEY (recurring_id, user_id)
);

-- Crew battles.
CREATE TABLE IF NOT EXISTS squad_battles (
  id TEXT PRIMARY KEY,
  squad_id TEXT NOT NULL REFERENCES squads(id),
  rival_squad_id TEXT NOT NULL REFERENCES squads(id),
  status TEXT NOT NULL DEFAULT 'pending', -- pending|active|finished|declined
  starts_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### 6.2 Proposed additive endpoints (no contract breaks)

| Endpoint | Purpose | Notes |
|---|---|---|
| `GET /squads` +`ownerName`, `memberPreviews[]`, `myRankWeek`, `nextRecurring` | crew cards §1.1 | nullable-additive fields |
| `GET /squads/:id` +`createdAt`, `bio`, `colorKey`, `iconKey`, `stats{wins,races,streakDays}`, `standingsWeek`, `recurring[]`, `battle`, `joinRequests[]` (admins) | crew page §2 | same envelope, extra keys |
| `GET /squads/:id/standings?period=week|all` | leaderboard switch §2.4 | reuse CrewGroupStanding shape |
| `GET /squads/:id/preview` | non-member view (friends' crews, report target) | name/icon/memberCount/ownerName/faces only — detail stays 404 for non-members |
| `GET /squads/discover` | friends' crews §1.5 | squads where a crew_connection is active member and I'm not |
| `POST /squads/:id/join-request` | "Ask to join" §1.5/§2.2 | writes status='requested' row |
| `POST /squads/:id/join-requests/:userId/approve|decline` | owner/admin resolves | approve → status 'active' + pulls into open races (reuse squads.ts:330-345 logic) |
| `PATCH /squads/:id {bio,colorKey,iconKey}` | crew identity §2.1 | extend existing patch |
| `POST /squads/:id/mute {on}` | mute crew §2.0 | sets muted_at |
| `POST /reports/squads/:id` | report crew §2.0 | reports row target_type='squad' |
| `POST /squads/:id/recurring` / `PATCH|DELETE …/recurring/:rid` / `POST …/recurring/:rid/auto-join {on}` | recurring races §2.5 | admin manage; opt-out per member |
| `POST /squads/:id/battles {rivalSquadId}` + accept/decline | crew battle §2.6 | rival admin accepts |
| `GET /crew/requests` +`mutualCount`, `mutualNames[]` | "Friends with X and Y" §1.3 | additive fields |
| relax `POST /squads/:id/races` to any active member (own race only) | "Start a crew race" for all members §2.2 | currently owner/admin (squads.ts:572-575) |
| `/crew/feed` + badge-earned items | "earned a badge" §1.4 | new item type `badge_earned` |

### 6.3 Server verifications still needed before build

- `progress_accepted` payload keys (does it carry `value`/`score` for the
  "logged 14 pushups" number chip?) — unverified from route code read.
- Default expiry for `crew_connect` invites (`defaultExpirySeconds` in
  `lib/invites.ts`) — determines how long My Nuvo codes stay valid.
- Whether `races` table has any recurrence/schedule columns (none seen;
  recurring races are new either way).
- Where "who can challenge me" settings-style prefs would live if kept —
  likely `notification_preferences` pattern; deferred (out of scope).

### 6.4 What is NOT missing

Presence, mutual counts (search only), connection statuses, request
lifecycle, reactions/cheers, feed, invites/QR links, squads CRUD + roles +
standings (all-time), reports/blocks — all live and wired today.
