# ACTIVITY_ONBOARDING.md — v13 spec mapping

Status: COMPLETE (Phase A documentation; no code changes made).
Scope: v13 spec section **"Activity (bell)"** (`docs/redesign/PROTOTYPE_V13_SPEC.md:121-122`)
plus the **Global rules** (`:5-18`) applied to onboarding / auth / splash.
Covers: `lib/features/notifications`, `lib/features/onboarding`,
`lib/features/auth/presentation` (UI only — logic files are no-touch),
`lib/features/splash`, `lib/features/pass`, and the worker surfaces behind them
(`server/worker/src/routes/{notifications,devices,pass,invites,auth,motion}.ts`,
`src/domain/{notifications,notificationPolicy,crewLifecycle}.ts`, `src/index.ts`,
migrations `0001`, `0014`, `0032`).

Verdict legend: **KEEP** (works as-is) · **RESTYLE** (same behavior, new skin) ·
**REPLACE** (new implementation on same contract) · **DELETE** (remove).

---

## 0. Spec target (quoted)

> **Activity (bell)** — "Notifications grouped into New and Earlier. Each has a
> photo, text, time, and an inline action button where it fits (Take it back,
> Accept, View). Opening the screen clears the badge count."
> — PROTOTYPE_V13_SPEC.md:121-122

Global rules that apply to this whole spec: light mode only (#F5F6F8 page,
#FFFFFF cards); 2-2.5px navy #07152D outline + 3-6px hard offset shadow on
cards/buttons; Nuvo blue #1264FF reserved for the one primary action + "you";
race/crew palette coral #FF8A65, sun #FFC93C, lilac #CDBFFF, mint #9EE6C4,
sky #B8D2FF, gold #F5B800 (1st only); open rows with 2px dividers instead of
boxed lists; Manrope 500-800; 36-48px section gaps; real photos in navy-outlined
circles (neutral silhouette fallback, blue ring for "you"); one overshoot spring
(~420-600ms); confetti only on join/accept/earn; navy pill toasts; no dead
buttons.

---

## 1. Activity (bell) — the notifications inbox

### 1.1 Where the bell lives today vs v13

| Location | Current code | v13 target | Verdict |
|---|---|---|---|
| Friends tab header (`/pass`) | `NotificationBell` at `pass_screen.dart:2874` inside `_CrewHeader` | v13 "Crew tab" header shows only a QR button + "Add friend" — no bell | **MOVE** to Arena header |
| Arena header | none — `grep NotificationBell\|notifications\|bell` over `lib/features/arena/` returns nothing; the baseline's "dead bell" (`BASELINE_BEFORE_PRODUCT_SKELETON.md:73`, old `arena_screen.dart:60`) no longer exists | Arena header "bell button that opens Activity (a coral badge shows the unread count)" | **NEW** — mount `NotificationBell` (restyled) in the v13 Arena header |
| Bell widget | `notification_bell.dart:12-69`: `Icons.notifications_none_rounded` 24px in a 44px `NuvoRippleSurface`; red `NuvoColors.danger` pill badge (top-right, `min 16px`, `9+` cap, 1.5px page-colored border) fed by `unreadCountProvider`; tap → `notificationControllerProvider.markStale()` + `context.push('/notifications')` | Same position/behavior; badge must be **coral #FF8A65** per spec §1 | **RESTYLE** (badge color + icon weight; keep semantics `Semantics(button, label:)` at :21-23) |

### 1.2 `/notifications` screen — element map

Route: `_detailPage` `GoRoute('/notifications')` — `lib/app/router.dart:197-201`.
Screen: `NotificationsScreen` — `notifications_screen.dart:31-358`.
State: `notificationControllerProvider` — `notification_controller.dart:361-396`
(`NotificationState` at :15-56). Unread badge: `unreadCountProvider` (:399-401).

| # | Element | Current code | Data / endpoint | Verdict |
|---|---|---|---|---|
| 1 | Back button → pop or `/arena` fallback | `notifications_screen.dart:114-116` | — | KEEP (route unchanged) |
| 2 | Title "Notifications" + "{n} unread" subtitle | :118-136 | `state.unreadCount` | RESTYLE → v13 header "Activity"; unread copy becomes the "New" group count |
| 3 | Mark-all-read icon (`Icons.done_all_rounded`) | :138-146 | `controller.markAllRead()` → `POST /notifications/read-all` | **REPLACE** — spec says opening the screen clears the badge, so the explicit button becomes redundant (see §1.5) |
| 4 | Notification-settings gear → `/settings/notifications` | :147-153 | — | KEEP (restyle icon to v13 chrome); destination in §1.8 |
| 5 | First-load spinner | :163-165 (`NuvoLoadingIndicator`) | — | KEEP |
| 6 | Error + retry (no cached data) | :166-174 (`NuvoErrorState`, `load(force:true)`) | `GET /notifications` | KEEP — v13 "navy pill toast" pattern applies to transient errors; full-page error stays for cold failures |
| 7 | Empty state "You're all caught up" | :175-184 (`NuvoEmptyState`) | — | RESTYLE copy/icon to v13 illustration style |
| 8 | Pull-to-refresh | `RefreshIndicator` :186-188 | `load(force:true)` → `GET /notifications` (+`If-None-Match` ETag → 304) | KEEP |
| 9 | Flat chronological list, hairline dividers `indent:70` | :190-215 | — | REPLACE → grouped **New / Earlier** open rows (2px dividers, open layout already conforms to spec) |
| 10 | Infinite scroll (fetch at 400px from bottom) | :45-49 | `loadMore()` → `GET /notifications?cursor=<iso>` | KEEP |
| 11 | End-of-list page spinner | :216-220 | — | KEEP |
| 12 | `_NotificationRow`: 38px `NuvoAvatar` (initials fallback) | :269-273 | `actor.profilePhotoUrl`, `actor.displayName` | RESTYLE — real photo in navy-outlined circle; silhouette fallback (spec §13 kills initials as primary) |
| 13 | Row title (bold when unread) + relative time | :279-301 | `title`, `createdAt` via `notificationRelativeTime` (`notification_display.dart:18-25`) | KEEP text treatment; unread signal moves into New-group membership + spec accent |
| 14 | Optional 2-line body | :303-312 | `body` | KEEP |
| 15 | Inline Accept/Decline — **only** for unread `crew_request` w/ `ProfileDestination` | :245-249 (`_isActionableRequest`), :313-339, `_resolveCrew` :68-101 → `crewControllerProvider.acceptRequest/declineRequest` → `POST /crew/requests/:id/{accept,decline}` (`crew_api.dart:338-356`) | **RESTYLE + EXTEND** to the v13 action set (§1.4) |
| 16 | Unread dot (accent-colored, 8px) | :259-260, :343-352 | `socialAccentFor(category)` (`social_event_accent.dart:23-60`) | REPLACE — spec has no unread dots; "New" grouping replaces the dot |
| 17 | Row tap → `markRead(id)` + `context.push(dest.location)` | `_open` :62-66 | `POST /notifications/:id/read`; destination → route via `NuvoDestination.location` | KEEP |
| 18 | Stagger-in entrance | `NuvoStaggerIn` :205-214 | — | RESTYLE to the single overshoot spring |
| 19 | Busy state on action buttons (per-row `_busy` set) | :40, :78/:99, :323/:333 | — | KEEP |

### 1.3 Data + Worker contract (verified)

Client: `notification_api.dart:13-78` via `NotificationRepository`
(`notification_repository.dart:6-46`, token-refresh wrapper — logic no-touch
adjacent but safe to leave entirely alone).

| Call | Endpoint | Worker source |
|---|---|---|
| List page 1 / next pages | `GET /notifications?cursor={iso}&limit={n}` (limit default 30, clamp 1-50). Response `{ok, notifications[], unreadCount, nextCursor}`; weak ETag → `304` on `If-None-Match` | `routes/notifications.ts:52-110` |
| Mark one read | `POST /notifications/:id/read` | `routes/notifications.ts:113-122` |
| Mark all read | `POST /notifications/read-all` | `routes/notifications.ts:125-133` |
| List prefs | `GET /notifications/preferences` → `{ok, preferences[]}` merged with `CATEGORY_DEFAULTS` | `routes/notifications.ts:138-157` |
| Update pref | `PATCH /notifications/preferences` `{category,inApp?,push?}` | `routes/notifications.ts:160-181` |
| Row shape | `{id, category, title, body, createdAt, read, actor:{id,displayName,profilePhotoUrl}\|null, destination:{type,id?,context?}\|null}` | `notifications.ts:30-49` |
| Schema | `notifications` + `notification_preferences` + `device_tokens` | `migrations/0014_social_platform.sql:57-114` |

**Every row field the v13 design needs already exists**: photo (`actor.profilePhotoUrl`),
text (`title`+`body`), time (`createdAt`), destination for routing/inline actions,
unread flag (`read_at`). No worker change is required for the v13 inbox —
**MISSING = none for the list itself.**

### 1.4 Notification kinds → accent, destination, v13 inline action

Canonical server categories: `NOTIFICATION_CATEGORIES`,
`domain/notifications.ts:15-28`. Emission sites verified below; `dest` is a
structured `{type,id,context}` descriptor → `NuvoDestination.fromDescriptor`
(`nuvo_destination.dart:69-89`) → `.location`.

| Category | Accent (`social_event_accent.dart:23-60`) | Server dest (emission site) | Lands on (`.location`) | v13 inline action → endpoint |
|---|---|---|---|---|
| `passed_on_leaderboard` | threat (red) | `{race, id, context:'leaderboard'}` — `notificationPolicy.ts:333,420` | `/race/:id` (`context:'leaderboard'` has no distinct branch — same default as bare race, `nuvo_destination.dart:100-108`) | **Take it back** → `/race/:id/proof` (Submit proof). Precedent: `_actionFor` in `pass_screen.dart:328-343` already renders exactly this label for feed overtakes |
| `crew_request` | attention (orange) | `{profile, id=<requester>}` — `crewLifecycle.ts:144-153` | `/u/:id` | **Accept** (+ Decline) → `POST /crew/requests/:id/{accept,decline}` — exists today (:313-339). Confetti on accept per spec §15 |
| `race_invite` | competition (blue) | `{race, id}` — `notificationPolicy.ts:586` | `/race/:id` | **Accept** → `POST /races/:id/join` then `/race/:id`. NEW inline action — today the row only routes; join is one tap deeper. Client-side only; no worker change |
| `race_starting` | attention | `{race, id}` — `notificationPolicy.ts:749-755` | `/race/:id` | **View** |
| `race_joined` | competition | `{race, id}` (aggregated) — `notificationPolicy.ts:599-605` | `/race/:id` | View |
| `race_completed` | positive | `{race, id}` — `notificationPolicy.ts:384-391` | `/race/:id` | View |
| `proof_accepted` | positive | `{race, id}` — `notificationPolicy.ts:623-634` | `/race/:id` | View |
| `proof_rejected` | threat | `{race, id}` — `notificationPolicy.ts:646-652` | `/race/:id` | **Take it back** (copy "Submit proof" or "Try again") → `/race/:id/proof`. Spec only names three actions; this is the same resubmit intent — flag for design |
| `proof_disputed` | neutral | `{race, id}` — `notificationPolicy.ts:664-671` | `/race/:id` | View |
| `reaction` | attention | `{race,id}` or `{crew}` — `notificationPolicy.ts:689-699` | `/race/:id` or `/pass` (`CrewDestination.location` `:135`) | View |
| `crew_request_accepted` | positive | `{profile}` — `crewLifecycle.ts:144-153` | `/u/:id` | View |
| `crew_connected` | positive | `{profile}` — `crewLifecycle.ts:144-153` | `/u/:id` | View |
| unknown/future | neutral | whatever server sends | safe fallback — `fromDescriptor` returns null → row tap just marks read (`_open` :64-65 guards null) | none |

Additional kinds appear in `socialAccentFor`/`socialAccentIcon`
(`social_event_accent.dart:44-84`) — `rank_changed`, `lead_changed`,
`rematch_requested`, `race_live`, `winner_determined`, `personal_best`,
`participant_finished`, `race_created`, `race_started`, `attempt_started`,
`attempt_completed`, `progress_accepted`. These are **crew-feed** event types
(`/crew/feed`), not `notifications`-table categories — they can still arrive in
the inbox only if a later migration adds them; render via the neutral fallback.

### 1.5 "Opening the screen clears the badge" — behavior delta

Current behavior: the badge only clears when each row is tapped
(`markRead` :62-66) or the mark-all icon is pressed (:138-146). Rows render
bold-when-unread forever.

Spec behavior: badge resets on open.

**Proposed implementation (client-only):**
1. On first build after data is present, snapshot `unreadIds = {n.id | !n.read}`.
2. Call `markAllRead()` once → `POST /notifications/read-all` (optimistic local
   patch already exists, `notification_controller.dart:322-333`).
3. Render groups from the snapshot: **New** = snapshot ids (preserves the
   "what's new since last time" signal the spec wants), **Earlier** = the rest.
   Rows in "New" can still carry the accent tick/weight for this session only.
4. Keep `markRead` on row tap (harmless no-op server-side; keeps the
   `crew_request` actionability contract: `_isActionableRequest` :245-249 keys
   off `!item.read`, so if mark-all runs on open the Accept/Decline buttons must
   key off *snapshot* unread state instead of live `read` — otherwise every
   friend-request row loses its buttons the moment the screen opens. **This is
   the one subtlety the build must get right.**)

Alternative considered: mark-all on *exit* — rejected; a killed app would leave
the badge stale, and the spec is explicit about open.

### 1.6 Required states (v13 Activity)

| State | Handling |
|---|---|
| First load | skeleton/spinner (existing `NuvoLoadingIndicator`, restyle) |
| Cold error | `NuvoErrorState` + retry (existing) |
| Empty | v13 empty state (existing copy is fine: "You're all caught up") |
| New = 0, Earlier > 0 | show only "Earlier" group; never a dead "New (0)" header (dead-UI rule) |
| Action in flight | per-row busy (existing `_busy`) |
| Action failure | navy pill toast "That didn't go through. Try again." (existing copy at :95) |
| Pagination | footer spinner (existing) |
| Offline/presentation demo | fixture inbox `PresentationDemoData.notifications()` (`presentation_demo.dart:681-760`, 8 rows incl. `crew_request`, `reaction`, `passed_on_leaderboard`) — covers the v13 grouping for demos |
| Push arrived while open | `markStale()` → refetch merges (existing `PushService._invalidateFor`) |

### 1.7 Push deep-link handling (end to end)

Wiring (`lib/app/app.dart:85-119`):
- `deepLinkControllerProvider.start(router)` — universal links + `nuvo://`
  scheme → `NuvoDestination.tryParse` → `handleDestination`.
- `pushServiceProvider.start(router)` — dormant until Firebase config exists
  (`push_service.dart:62-96`; `Firebase.initializeApp()` throws → all no-ops).
- Sign-out → `beforeSignOut` → `PushService.onSignedOut` →
  `DELETE /devices/:token` while the token is still valid (:90-95).
- `shouldDrainPendingDestination` (:23-30, :115-118) — a stashed destination
  drains exactly once when the user is authenticated **and**
  `onboardingComplete` (a sign-up from an invite link finishes setup first).

Push tap path (`push_service.dart:198-214`): `_routeFromMessage` →
`_invalidateFor(data)` (marks domains stale) →
`destinationFromPushData` (`destType`/`destId`/`destContext` →
`NuvoDestination.fromDescriptor`) → `deepLinkController.handleDestination(dest,
authed:)` → `router.go(dest.location)`, or stash the destination's `.location`
string into `PendingDestinationStore`
(`lib/features/social/data/pending_destination_store.dart:22-33` —
`FlutterSecureStorage`, `localStorage` on web) + `/welcome` when logged out
(`lib/features/social/application/deep_link_controller.dart:61-75`).

Domain invalidation map —
`lib/features/notifications/domain/push_invalidation.dart:28-54`
(`pushDomainsFor`):
- `race_invite|race_joined|race_starting|passed_on_leaderboard` →
  notifications + races + arena + activity
- `race_completed|proof_accepted|proof_rejected|proof_disputed` → above +
  progression (XP/badges)
- `crew_request|crew_request_accepted|crew_connected` → notifications + crew +
  activity
- `reaction` → notifications + activity

**Routing per kind in the new shell** — unchanged destinations; the only change
is *where each location lives* in the v13 IA:

| dest.type | `.location` | v13 home |
|---|---|---|
| `race` | `/race/:id` (`context:'review'` → `/race/:id/settings`) | Race detail (leaderboard room) — unchanged |
| `profile` | `/u/:id` | Public profile — unchanged |
| `crew` | `/pass` | **Maps to the v13 "Crew" tab** — `CrewDestination` currently points at the `/pass` path (`nuvo_destination.dart:135`); if the tab path is renamed in the v13 shell this ONE line is the single point to update (contract: server sends `type:'crew'`, client owns the string) |
| `invite` | `/invite/:token` | Invite preview — unchanged; `requiresAuth=false` (:168) |
| `notifications` | `/notifications` | Activity screen — unchanged |

Push token lifecycle (no UI): `PushTokenSync` (`push_token_sync.dart:20-142`)
retries `getToken` (APNs can lag) + `POST /devices` with backoff
(`device_api.dart:24-54` ⇄ `devices.ts:11-44`; server deletes the token from
other accounts before upserting — one-token-one-owner). On sign-out:
`DELETE /devices/:token` (`devices.ts:47-55`).

### 1.8 Notification prefs screen (`/settings/notifications`)

`notification_prefs_screen.dart:30-334` — `NuvoPage` + `NuvoBackHeader`
(title "Notifications"), "Control in-app and push alerts." subtitle, grouped
`App`/`Push` toggle columns via `NotificationPref.display` groups
(`notification_prefs.dart:31-45`: Races / Proof / Friends / Other),
OS-denied banner with `app-settings:` deep link (:158-188), optimistic toggle +
rollback snackbar (:77-107).

- Verdict: **RESTYLE** (v13 Settings "Notifications" row list is flatter and
  uses spring toggles; keep the two-channel App/Push model — it matches
  `PATCH /notifications/preferences {category,inApp,push}` exactly).
- Conflict: v13 spec lists pref groups as "passes, invites, results, cheers,
  reminders" (:108) vs the server's 12 categories. Resolution: keep server
  categories; map onto the spec's five visual groups if the v13 Settings design
  is locked — `invites` = race_invite + crew_request, `results` = race_completed
  + proof_*, `cheers` = reaction, `reminders` = race_starting, `passes` has no
  server category (member pass has no notifications — drop it or treat as
  inert). **Do not collapse the backend contract** — prefs stay per-category.

---

## 2. Onboarding (`lib/features/onboarding`)

Route map (`router.dart:225-261`): `/onboarding/profile`,
`/onboarding/motion-consent`, `/onboarding/nuvo`, `/onboarding/notifications`,
plus retired redirects `/onboarding/member-pass` and `/onboarding/finish` →
`/onboarding/nuvo`. Gate: `auth_gate.dart:97-110` (`!onboardingComplete` →
`_firstRunTarget` :167-176 — profile+legal → consent → story).

**Sequencing (must not change):** sign-in → profile/legal
(`OnboardingScreen`) → motion consent (`MotionContributionScreen`) → 8-page
story (`NuvoOnboardingScreen`, final CTA writes `POST /onboarding/complete`)
→ notification primer (`NotificationPermissionScreen`) → Arena + first-race
coach (`firstRaceGuideProvider`).

### 2.1 `/onboarding/profile` — `OnboardingScreen` (`onboarding_screen.dart:23-849`)

| Element | Code | Calls (keep identical) | Verdict |
|---|---|---|---|
| 3-step progress bar | :361-380 | — | RESTYLE |
| "Build your profile" header + subtitle | :383-400 | — | RESTYLE |
| Live identity preview card (photo, name, @handle, LEVEL 1 chip) | :404-541 | `ref.watch(authControllerProvider).user?.profilePhotoUrl` :127 | RESTYLE |
| Photo bottom sheet (choose/take/remove/cancel) | `_openPhotoSheet` :170-231, `_PhotoSheetOption` :806-849 | `photoPickerProvider` :234 (`_pickPhoto` :233-263); `app-settings:` on denied :558 | RESTYLE — picker + upload calls identical |
| Full name / Username inputs | `NuvoTextInput` :581-604 | — | RESTYLE |
| Username availability (debounced 650ms) | `_onUsernameChanged` :72-103 | `authControllerProvider.notifier.checkUsername(raw)` :84-86 → `POST /profile/username/check` | KEEP logic; RESTYLE indicator |
| Format/taken feedback rows | :607-680 | — | RESTYLE |
| Terms + age checkboxes + legal links | `_ConsentRow` :684-729, :765-802; `LegalLinks` uris :701-715 | — | RESTYLE |
| Continue CTA | :744-754, `_canContinue` :276-282 | `_continue` :284-339 → `acceptTerms()` (`POST /auth/terms`) :303, `attestAge()` (`POST /auth/age-attestation`) :304, `uploadProfilePhoto` (`POST /profile/photo/upload-url` → signed `PUT`) :308-323, `saveProfile(fullName,username)` (`POST /profile`) :324-327, then `context.go('/onboarding/motion-consent')` :328 | RESTYLE — the four writes + nav call stay in this exact order |

### 2.2 `/onboarding/motion-consent` — `MotionContributionScreen` (`motion_contribution_screen.dart:16-240`)

- UI: 3-step bar (:53-68), "Help make Nuvo better" title (:83-96), explainer
  (:98-109), 3 fact chips (:113-200), blue "Help improve Nuvo" + "Not now"
  (:209-233). All pure UI → **RESTYLE** (one colored hero + one blue action).
- Logic to keep: `_choose` :28-41 →
  `authControllerProvider.notifier.setMotionConsent(consented:)` →
  `PUT /motion/consent` (`motion.ts:60`, consent version
  `MOTION_CONSENT_VERSION` :22); **failure still navigates**
  `context.go('/onboarding/nuvo')` :39 — do not "fix" this; it is deliberate
  (consent is editable later in Settings).

### 2.3 `/onboarding/nuvo` — `NuvoOnboardingScreen` (`nuvo_onboarding_screen.dart:182-3392`)

8 pages (`_pageCount` :192). Each page owns a one-time entrance and calls
`_markReady` once (:202-203, :252-255); `PageView` is swipe-locked until page 0
settles (:385-387). Back unwinds one page via `PopScope` (:333-339).

| Page (index) | Class | Copy (verified) | Teaching content | Verdict |
|---|---|---|---|---|
| 0 | `_IntroPage` :686 | "Ready, {firstName}?" / "Make real life a race." (:750-766) | `WelcomeOpeningCinematic` path-to-finish-line animation (:739) | RESTYLE — keep cinematic or reskin to v13 mark |
| 1 | `_RaceAnythingPage` :790 | "Race anything." / "Set the finish line. Bring your friends." (:927-1026) | Rotating example races (books/pushups/math/golf, :819-831) | RESTYLE |
| 2 | `_MovePage` :1045 | "Make your move." / "Real progress becomes race progress." (:1138-1153) | `RiveMovementPreview` motion demo | RESTYLE |
| 3 | `_ClimbPage` :1377 | "Climb the board." / "That progress also builds your Nuvo." (:1443-1455) | `_OvertakeScene` leaderboard animation | RESTYLE |
| 4 | `_LevelPage` :1740 | "Every race builds your Nuvo." / "Do real race things. Watch the level move." (:1850-2008) | Real XP table `_xpLesson` :30-35 (mirrors worker `XP_AWARDS`); live progression payload | RESTYLE — real XP values must keep matching `server/worker/src/domain/progression.ts` |
| 5 | `_IdentityPage` :2226 | "Make your name mean something." / "Your level and achievements go with you." (:2331-2495) | Real badge defs via `_onboardingAchievementDefsProvider` :41-47 → `progressionControllerProvider.getBadges()`; offline fallbacks `_defFallbacks` :52-123 (mirror migration 0042) | RESTYLE — fallbacks must stay in sync with badge defs |
| 6 | `_CrewPage` :2683 | "Better with competition." / "Race friends. Find rivals. Keep moving." (:2766-2793) | Crew/friends teaching | RESTYLE |
| 7 | `_ReadyPage` :2902 | "{firstName}, you're ready." / "Your first move starts now." (:2988-3064) | Personalized payoff; primary CTA "Start your first race" (`_buttonLabel` :257-261) | RESTYLE |

Logic to keep identical:
- `_firstName` :212-217 (reads `authControllerProvider.user.fullName` — nameless
  fallbacks required).
- `_finish` :268-324 — `authControllerProvider.notifier.completeOnboarding()`
  → `POST /onboarding/complete` (`index.ts:421-437`); then
  `firstUseStoreProvider.markNotificationPromptOwed()` :313 →
  `context.go('/onboarding/notifications')` :314. Error copy + `_finishing`
  :305-323.
- Demo-replay branch :271-303 (store-review account → mark owed → `/onboarding/
  notifications`; normal replay → `firstRaceGuideProvider=competeStart` →
  `/compete`). Keep verbatim.
- `_onboardingAchievementDefsProvider` warm-watch :354.
- `_asLightChrome` :164-167 — pins light theme; v13 is light-only anyway (keep,
  harmless).

### 2.4 `/onboarding/notifications` — `NotificationPermissionScreen` (`notification_permission_screen.dart:27-314`)

- UI: bell chip, "Don't miss the move." + explainer (:126-150),
  `_SampleNoticeStack` two sample notifications (:154, :201-239),
  "Turn on notifications" + "Maybe later" (:165-189). → **RESTYLE**.
- Logic to keep: `_checkAuthorization` :46-55 →
  `pushServiceProvider.notificationAuthorizationStatus()` — screen renders
  ONLY when `notDetermined`; `_enable` :65-76 →
  `requestPermissionInContext()` (the only place the OS dialog fires);
  `_resolve` :60-63 → `firstUseStoreProvider.clearNotificationPromptOwed()` +
  `context.go('/arena')`. Guard also checks the owed flag
  (`auth_gate.dart:118-123`).

### 2.5 First-race guide — `first_use_guide.dart`

- `firstRaceGuideProvider` (`StateProvider<FirstRaceGuideStep>` :34-36) steps:
  idle → competeStart → composerName/Activity/Goal/Racers/Review → raceDetail →
  verifySetup → profileReward → complete.
- `FirstRaceGuideKeys` :79-102 — `GlobalKey`s that must be **re-attached to the
  v13 controls**: `competeStart` (v13 "New race" button on Compete header),
  `composerName/Activity/Goal/Racers/Review` + the 4 CTA keys (v13 4-step
  composer's Next buttons), `racePrimary` (Submit proof on race detail),
  `verifyBegin`, `profileProgress`. v13's 4-step composer maps cleanly onto
  steps name → activity → goal → racers → review.
- `composerCoachSpec` :140-217 — bubble copy per page/input state;
  `firstRaceGuideAllowed` :226-231; `completeFirstRaceGuide` :236-242
  (persists per-email via `firstUseStoreProvider.markGuideDone`).
- `FirstRaceGuideCoach` overlay :256-536 — scrim + pulse ring + `_GuideCallout`
  bubble; **RESTYLE** to v13 (navy outline bubble, single spring; the
  per-frame `_locateTarget` tracking :329-379 and `avoidKeys` handling are
  mechanics to keep).
- `resetDemoExperienceForColdLaunch` :64-77 — store-review reset; keep.
- `demoReplayProvider` :40 — keep.

### 2.6 `FirstUseStore` (`data/first_use_store.dart:32-146`)

Install-scoped flags: `introSeen` (legacy decode only :12-14), 
`notificationPromptOwed` (:88-96), `cameraPrimerSeen` (:98-101), per-account
`guideDone` (:83-86); file `nuvo_first_use.json` via `path_provider`.
**KEEP** — pure persistence; no v13 surface change.

---

## 3. Auth screens (`lib/features/auth/presentation` — UI only)

Logic files `auth_api.dart`, `auth_repository.dart`, `auth_controller.dart`,
`auth_gate.dart`, `secure_token_store.dart` are **no-touch** — every call site
listed below must keep calling the same provider method with the same
arguments. Restyle = layout/copy/widget chrome only.

### 3.1 `/splash` → `SplashScreen` (`splash_screen.dart:14-372`)

- UI to restyle: `_LaunchAtmospherePainter` blue radial glow (:339-372),
  `_LaunchMark` 60fps frame sequence `AssetPaths.splashFrame` 280→180 + settle
  lift + "WELCOME TO" eyebrow + `nuvotext.png` reveal (:247-328). Frame
  precache `_startSequence` :102-126.
- Verdict: **RESTYLE** visuals only.
- Logic to keep verbatim: `_resolveLaunch` :80-100 and `_tryNavigate`
  :148-194 — `firstUseStoreProvider.ensureLoaded()` :72, unauthenticated →
  `context.go('/welcome')` :93, `AuthStatus.offline` → `/arena` :157-161,
  demoReplay/`guideFirstRace` + `!guideDone` → `/onboarding/nuvo` :177-187,
  else `/arena` :190 / `/welcome` :192; auto-continue timer :136-146;
  `ref.listen(authControllerProvider)` :204-210.

### 3.2 `/welcome` → `WelcomeAuthScreen` (`welcome_auth_screen.dart:25-519`)

| Element | Code | Auth calls (keep identical) | Verdict |
|---|---|---|---|
| Title "Ready to start your first race?" / "Welcome back." + subtitle | :226-248 | — | RESTYLE |
| "Create account" → `/auth/email`; login mode embeds `EmailStartScreen` | :249-258 | `context.push('/auth/email')` :255 | RESTYLE (one blue primary; Apple/Google become outlined secondary) |
| `_AppleButton` / `_GoogleButton` (`_ProviderButton` :333-391) | :260-272 | `_signInWithApple` :123-171 → `SignInWithApple.getAppleIDCredential` then `authControllerProvider.notifier.signInWithApple(idToken, fullName:, authorizationCode:)` :153-159 → `POST /auth/apple`; `_signInWithGoogle` :87-121 → `GoogleSignIn().signIn()` → `account.authentication.idToken` → `signInWithGoogle(idToken)` :110 → `POST /auth/google` | RESTYLE buttons; calls untouched |
| Mode toggle "Already have an account? Log in" | :278-310 | `authIntentProvider.notifier.state = AuthIntent.{signUp,signIn}` :62-64,:81-83 — the reviewer-path intent contract; do not drop | RESTYLE |
| `_continueDemo` (store-review "Continue demo") | :182-187, shown :249-256 when `demoReplayProvider` | sets `demoReplayProvider=false`, `firstRaceGuideProvider=competeStart`, `context.go('/compete')` | KEEP verbatim |
| Back button when stack allows | :217-225 | `safePopOrGo(context,'/welcome')` | KEEP |
| `NuvoLegalFooter` | :312 | — | RESTYLE |
| `_kGoogleEnabled = true` | :23 | gate for Google button — baseline's "needs setup" copy is already gone (grep: no "coming soon"/"needs setup" strings remain in `lib/`) | KEEP |
| `_GoogleGPainter` official G mark | :451-519 | — | KEEP (brand requirement comment :455-457) |

### 3.3 `/auth/email` → `EmailStartScreen` (`email_start_screen.dart:15-283`)

- UI: back → `/welcome`, "Enter your email" + "We'll send a sign-in code for
  your Nuvo race pass." (:230-247), `NuvoTextInput` email (+ password when
  reviewer) `_buildFields` :142-197, pinned `NuvoPrimaryButton`
  "Send code"/"Sign in" :263-273, `NuvoLegalFooter` :274-277. → **RESTYLE**
  ("race pass" copy should become "member pass" per product language).
- Logic to keep: `_normalizedEmail` :44, `_isReviewerEmail` :49
  (`isNuvoStoreDemoEmail` — auth_controller.dart:28), `_canSubmit` :51-55,
  `_submit` :57-140 → `authIntentProvider` read :69, replay arm :71-73,
  `signInReviewer(email,password,intent:)` :79-85 → `POST /auth/reviewer`,
  `resetDemoExperienceForColdLaunch` :90-94, guide/replay resets :96-101,
  `startEmailAuth(email)` :105 → `POST /auth/email/start`
  (`auth_api.dart:167`; worker `auth.ts:329`), `context.push('/auth/verify',
  extra: email)` :110-113 with the `route.isCurrent` guard, replay restore on
  failure :117-121, `finally _loading=false` :131-139.
- **Stale doc flag:** `docs/API_CONTRACT.md` names these
  `/auth/email/send-code`, `/auth/email/verify-code`, `/auth/token` — the code
  and worker actually use `/auth/email/start`, `/auth/email/verify`,
  `/auth/refresh` (`auth.ts:329,388,707`). Update the contract doc, not the code.

### 3.4 `/auth/verify` → `EmailVerifyScreen` (`email_verify_screen.dart:16-271`)

- UI: back → `/auth/email`, "Check your email" + address line (:183-196),
  `OtpInput` 6 digits :198, error text :199-207, resend block :208-240,
  pinned "Verify code" :255-265. → **RESTYLE**.
- Logic to keep: `_verify` :75-118 → `verifyEmailCode(email, code)` :81-83 →
  `POST /auth/email/verify` (`auth_api.dart:170`; `auth.ts:388`) — navigation
  is owned by the route guard; `_resend` :120-159 → `startEmailAuth` again;
  `_resendCooldownSeconds = 30` :28 mirrors the worker throttle — keep in sync.

### 3.5 `WelcomeOpeningCinematic` (`welcome_opening_cinematic.dart:10-251`)

Pure `CustomPaint` path animation (no state, no network); consumed only by
`_IntroPage` (`nuvo_onboarding_screen.dart:739`). **RESTYLE or REPLACE** with a
v13-native intro mark; its contract is `onComplete` — keep the reduced-motion
path (`MediaQuery.disableAnimationsOf`, :45-63).

### 3.6 Auth logic call inventory (must call the SAME methods)

| Caller | Method → endpoint |
|---|---|
| welcome_auth_screen.dart:110 | `signInWithGoogle(idToken)` → `POST /auth/google` |
| welcome_auth_screen.dart:153-159 | `signInWithApple(idToken, fullName:, authorizationCode:)` → `POST /auth/apple` |
| email_start_screen.dart:79-85 | `signInReviewer(email, password, intent:)` → `POST /auth/reviewer` |
| email_start_screen.dart:105 / email_verify_screen.dart:127-129 | `startEmailAuth(email)` → `POST /auth/email/start` |
| email_verify_screen.dart:81-83 | `verifyEmailCode(email, code)` → `POST /auth/email/verify` |
| onboarding_screen.dart:303-304 | `acceptTerms()` → `POST /auth/terms`; `attestAge()` → `POST /auth/age-attestation` |
| onboarding_screen.dart:310 | `uploadProfilePhoto(xFile)` → `POST /profile/photo/upload-url` + signed `PUT` |
| onboarding_screen.dart:324-327 | `saveProfile(fullName:, username:)` → `POST /profile` |
| onboarding_screen.dart:84-86 | `checkUsername(u)` → `POST /profile/username/check` |
| motion_contribution_screen.dart:32-34 | `setMotionConsent(consented:)` → `PUT /motion/consent` |
| nuvo_onboarding_screen.dart:310 | `completeOnboarding()` → `POST /onboarding/complete` |
| Providers written/read | `authControllerProvider`, `authIntentProvider`, `demoReplayProvider`, `firstRaceGuideProvider`, `firstUseStoreProvider`, `pushServiceProvider`, `pendingDestinationStoreProvider` |

---

## 4. Member pass (`lib/features/pass`)

### 4.1 What "member pass" is today

`PassInfo{memberId, passSlug, shareUrl}` — `GET /pass/me`
(`auth_api.dart:359-362` ⇄ `routes/pass.ts:10-27`; table `member_passes`
`migrations/0001_initial.sql:61-68`). Loaded by `memberPassProvider`
(`member_pass_provider.dart:148-159`): `MemberPassController` —
`ensureLoaded`/`refresh`, disk cache domain `member_pass` max 30d
(:38-39, :91-143), demo fixture `presentationDemoPassInfo()`. **KEEP provider
as-is** (it lives in application/, not auth no-touch, but has no reason to
change).

### 4.2 Surfaces using it today

| Surface | Code | Notes | Verdict |
|---|---|---|---|
| Friends tab header QR icon → `/my-nuvo` | `pass_screen.dart:2858-2873` (`onMyCode` = `context.push('/my-nuvo')` :584) | v13 Crew-tab header keeps a QR button | KEEP → point at v13 "My Nuvo code" |
| `_PeopleStrip` "You" tile → `/my-nuvo` | :763-771 | — | v13 "Racing right now" row — keep the self-tile entry |
| "Your member code" row (empty-crew state) | :787-794 | shows `profile.memberId` | fold into v13 entry points |
| Profile → "Member pass" row → `/my-nuvo` | `profile_screen.dart:233-235` | v13 Profile keeps a QR button top-right | KEEP |
| `/my-nuvo` `MyNuvoScreen` | `my_nuvo_screen.dart:31-445` | identity hero `_identityHero` :217-279 + `_CodeChip`, QR card `_qrCard` (QrImage, `qr_flutter`), `Share my Nuvo` (`share_plus`), `NuvoCopyButton`, "Scan a code" → `/scan` :142-147 | **REPLACE → "My Nuvo code"** — v13 wants a `My code / Scan` segmented control on ONE screen (:118-119). Port `_identityHero`/QR/share/copy into "My code"; embed the scanner view in "Scan" instead of pushing `/scan` |
| `showMyQrSheet` bottom sheet | `my_qr_sheet.dart:21-210` | same minted invite; used by other flows (invite/crew) | KEEP sheet for in-flow use; the full screen becomes the canonical surface |
| `/scan` `QrScanScreen` | `qr_scan_screen.dart:25-464` | `camera` + `google_mlkit_barcode_scanning` + `camera_image_converter.dart` (**no-touch** bridge); parses `NuvoDestination.tryParse` only | KEEP route + logic; the Scan tab of "My Nuvo code" should reuse `BarcodeScannerService` + the same parse — do NOT duplicate the camera converter |

### 4.3 Important data distinction

The QR shown in My Nuvo / My QR sheet encodes a **minted `crew_connect`
invite URL** (`POST /invites {kind:'crew_connect'}` →
`https://getnuvo.net/invite/<token>` — `invite_repository.dart:27-28`,
`invite_api.dart:80-104`), **not** the member pass `shareUrl`
(`{SHARE_BASE}/pass/{slug}`). `memberId`/`passSlug` show as text only. Two
different "codes" exist; the v13 "My Nuvo code" screen should keep the invite
QR (scan → `/invite/:token` preview → Add friend) as the working contract and
surface `memberId` as the printed code. Flag: the member-pass `shareUrl` has no
app-facing use today beyond text display — unverified whether `/pass/:slug` is
a live web surface (worker only mints the string, `pass.ts:25`).

### 4.4 Invite landing (`/invite/:token` → `InviteScreen`)

`invite_screen.dart:34-440` — preview `GET /invites/:token` (public), accept
`POST /invites/:token/accept` (`invite_api.dart:47-77`). Logged-out accept →
`pendingDestinationStoreProvider.put(InviteDestination)` + `/welcome`
(:76-81). Successful accept → `_afterAccept` :113-141 (refresh race/crew/notif
controllers, `pushServiceProvider.requestPermissionInContext()` :135 —
**the contextual permission moment**, keep), navigate `dest.location`.
Verdict: **RESTYLE**; confetti on successful add per spec §15.

### 4.5 Friend request resolution chain (for the Activity Accept action)

`_resolveCrew` (notifications_screen.dart:68-101) →
`crewControllerProvider.acceptRequest/declineRequest`
(`crew_controller.dart:423-442`) → `POST /crew/requests/:id/{accept,decline}`
(`crew_api.dart:338-356`) → server marks the `crew_request` notification read
in the same write (`crewLifecycle.ts:106-110`) →
`onRequestResolved` → `notificationControllerProvider.resolveCrewRequest`
(`crew_controller.dart:497` wiring → `notification_controller.dart:300-320`)
+ local `markRead` :89-91. Keep this whole chain identical.

---

## 5. Spec conflicts + proposed resolutions

| # | Conflict | Where | Resolution |
|---|---|---|---|
| C1 | v13 badge color "coral" | spec §1 vs `NuvoColors.danger` badge :44 | Coral #FF8A65 — pure restyle |
| C2 | Spec "Opening the screen clears the badge" vs current mark-read-per-tap | §1.5 | Snapshot-unread → `markAllRead` on open; group New/Earlier from snapshot; **keep `crew_request` actionability keyed to the snapshot, not live `read`** |
| C3 | Server titles embed emoji ("keep trading the lead 🔥" `notificationPolicy.ts:417`) vs spec "No decorative stickers" | spec §15 | Trim emoji client-side at render time (leave server copy alone — worker is no-touch-adjacent and other clients may show it) |
| C4 | v13 "Challenge [Name]" button (spec :94) vs banned word "challenge" (NUVO_PRODUCT_MODEL.md:180) | profile spec | Rename to "Race [Name]" — same action, opens New race prefilled (belongs to PROFILE.md; noted here for language consistency) |
| C5 | v13 Settings "private profile" toggle (spec :109) vs "private profiles do not exist" (model :173-174) and worker hardcodes `privateProfile:false` (`profile.ts:125,325`) | settings spec | Drop the toggle; do NOT build it. If privacy UI is wanted, the only honest controls are the existing block/report rows (belongs to PROFILE.md) |
| C6 | v13 prefs groups "passes, invites, results, cheers, reminders" vs 12 server categories | §1.8 | Keep per-category contract; map categories onto the five labels visually |
| C7 | "crew_*" category names vs product language (crew = named group, friend = person link) | `crewLifecycle.ts` + `crew_api.dart` endpoints `/crew/*` | Backend contract is friend-graph named "crew" historically — do NOT rename API fields; copy already says "friend request" server-side (`crewLifecycle.ts:147-149`). v13 UI must say friend/friends, never "add to crew" for a person link |
| C8 | `API_CONTRACT.md` documents `/auth/email/send-code`, `/auth/email/verify-code`, `/auth/token` | docs vs `auth_api.dart:167-209`, `auth.ts:329-707` | Doc is stale — real endpoints `/auth/email/start`, `/auth/email/verify`, `/auth/refresh`. Fix the doc during the build phase |
| C9 | Baseline lists a "dead notifications bell" at `arena_screen.dart:60` | baseline :73 vs current code | Already resolved pre-redesign — the bell lives only on `/pass` (`pass_screen.dart:2874`); v13 re-adds a *live* one to the Arena header |
| C10 | "Take it back" action for `passed_on_leaderboard` needs the proof route, but `dest` only carries `{race, id, context:'leaderboard'}` | §1.4 | Client composes `/race/$id/proof` — same pattern the feed already uses (`pass_screen.dart:334-343` via `_openCrewActivity` → `/race/:id`; take it one step deeper to the proof route). No worker change needed |

## 6. Features v13 doesn't show — adaptation notes

| Feature | Status | Adaptation |
|---|---|---|
| Member pass screen/QR | v13 shows "My Nuvo code" instead | Merge into My code/Scan segmented screen (§4.2); `GET /pass/me` stays |
| Race invite-code entry (`/races/join` `JoinRaceScreen`) | not in v13 spec | Keep behind Compete "Join a race" link (spec §3 last card "Join a race" → Compete). Restyle only; `joinRaceByCode` → `POST /races/:id/join {inviteCode}` |
| Crew join code (`/crews/join/:code`, `CrewJoinDestination`) | v13 "Join with a code" under Your crews | Keep — `nuvo_destination.dart:145-158` → confirm screen |
| `/crew/add` `AddCrewScreen` (search + requests) | v13 Crew tab has "Add friend" header button → opens **scan**, plus "Find people" affordances | Keep `/crew/add` as the search/requests hub; map the header Add-friend button to `/scan` per spec §67 |
| Notification prefs deep screen | v13 Settings has a Notifications section | Keep `/settings/notifications`; restyle to spring toggles + grouped sections (§1.8) |
| First-race coach overlay | not drawn in v13 | Keep — re-attach `FirstRaceGuideKeys` to v13 controls (§2.5); restyle bubble to v13 chrome |
| Store-review replay machinery (`demoReplayProvider`, `resetDemoExperienceForColdLaunch`, `/auth/reviewer`, `signInReviewer`, `presentationDemo*`) | invisible in v13 | **Mandatory keep** — App Store review depends on the deterministic first-run replay (`auth_controller.dart:24-29,185+`, `first_use_guide.dart:64-77`) |
| Push permission education screen | not drawn in v13 | Keep `/onboarding/notifications` — it's the OS-prompt gatekeeper (§2.4); restyle |
| `InviteDestination`-based QR/invite flow | v13 shows QR + scan only | Keep `/invite/:token` + deep-link stack untouched (§4.4) — it's the contract every QR/link resolves through |
| `introSeen` flag | legacy | No-op in practice (`first_use_store.dart:12-14`); leave for file-format compatibility |
| `race pass` copy on email screen | v13 language | Change "your Nuvo race pass" → "your member pass" (`email_start_screen.dart:243`) per product language |

## 7. Backend gaps (MISSING) vs already-satisfied

**Already satisfied — no worker change needed:**
- Unread count (`unreadCount` in `GET /notifications` response :107)
- Mark-all-read (`POST /notifications/read-all`)
- Structured destinations for every category (§1.4)
- Inline action endpoints for Accept (friend request) and race invite
  (`/crew/requests/:id/{accept,decline}`, `/races/:id/join`)
- Per-category prefs + device-token registration
- ETag/304 polling + cursor pagination

**Genuinely missing (flag — do not build against them):**
- No "who can challenge me"/private-profile settings backend (C5)
- No server "activity heat map" endpoint for the spec's Arena heat-map block —
  out of scope here (ARENA_SHELL.md owns it); feed/notification data partially
  covers it client-side today via `crewActivityProvider`
- No dedicated `/pass/:slug` web landing route — `shareUrl` is minted but no
  worker route serves it (§4.3)
- No notification-delete/clear-earlier endpoint (not in spec — don't add)

## 8. No-touch inventory for the later build

- `lib/features/auth/data/auth_api.dart`, `auth_repository.dart`,
  `secure_token_store.dart`, `_ls_stub.dart`, `_ls_web.dart`
- `lib/features/auth/presentation/auth_controller.dart`,
  `auth_gate.dart` — providers and redirect logic referenced throughout §2-3;
  screens may call them but files must not be edited
- `lib/features/races/ai/pose_detector_service.dart`,
  `camera_image_converter.dart`, `motion_validators.dart`,
  `presentation/ai_motion_proof_screen.dart` — `camera_image_converter` is also
  the QR scanner's frame bridge (`qr_scan_screen.dart:16`), so the Scan tab of
  My Nuvo code must reuse it, not re-implement it
- `ios/` native files; `pubspec.yaml`/`pubspec.lock`
- `server/worker/` — every endpoint cited is a deployed contract

**Packages already in pubspec (no additions needed):** `qr_flutter` (QR),
`camera` + `google_mlkit_barcode_scanning` (scan — deliberately NOT
`mobile_scanner`, which pins an incompatible MLKit 7.x; pubspec.yaml:57-60),
`share_plus`, `cached_network_image`, `image_picker`/`image_cropper`,
`flutter_animate`, `rive`, `intl`, `google_fonts` (Manrope source),
`firebase_messaging` (dormant push). **Missing for spec:** no `confetti`
package — confetti moments (join/accept/earn, spec §15) need either a custom
`CustomPainter`/`flutter_animate` implementation or a scoped pubspec exception;
recommend the custom painter to keep pubspec frozen.

## 9. Task-declaration preview for the build (per AGENTS.md)

```
Files to read:   this spec + files cited inline
Files to edit:   notifications_screen.dart, notification_bell.dart,
                 notification_prefs_screen.dart, welcome_auth_screen.dart,
                 email_start_screen.dart, email_verify_screen.dart,
                 welcome_opening_cinematic.dart, onboarding_screen.dart,
                 motion_contribution_screen.dart, nuvo_onboarding_screen.dart,
                 notification_permission_screen.dart, first_use_guide.dart,
                 splash_screen.dart, my_nuvo_screen.dart, my_qr_sheet.dart,
                 qr_scan_screen.dart, invite_screen.dart, join_race_screen.dart,
                 pass_screen.dart (header strip only), + v13 theme/widgets
Files to NOT edit: everything in §8
Behavior changes: badge clears on Activity open; New/Earlier grouping; inline
                 actions (Take it back / Accept / View); bell moves to Arena
                 header; My Nuvo becomes My code/Scan segmented screen
Risk level:      medium (auth-adjacent UI, route-touching; no contract change)
```
