# ARENA_SHELL.md — v13 spec mapping

Phase A documentation for the app shell (`lib/main.dart`, `lib/app`,
`lib/features/shell`, the tab bar) and the Arena tab
(`lib/features/arena` and everything it renders). Maps every v13 element
to the current code and the deployed Worker contract. Read-only; nothing
here changes code.

**v13 source:** `docs/redesign/PROTOTYPE_V13_SPEC.md` sections "Global
rules" (L5-18) and "Arena tab (home)" items 1-7 (L21-36). Item 8
("Submit proof bottom sheet", L37-43) is owned by
`docs/redesign/specs/COMPETE_RACES.md` — this doc covers only its Arena
entry point (§2.3d).

**Current surfaces:**

| v13 surface | Current code |
|---|---|
| App bootstrap | `lib/main.dart` (main():14-29) |
| App/router host | `lib/app/app.dart` `NuvoApp` (`MaterialApp.router` :140-148) |
| Route table + shell branches | `lib/app/router.dart` `routerProvider` (:105-115), `StatefulShellRoute` (:264-299), `_tabScreenFor` (:89-103) |
| Tab bar | `lib/core/widgets/bottom_nav.dart` `NuvoBottomNav` (:74-183), `nuvoDestinations` (:31-56), `_NavSlot` (:185-349) |
| Shell host | `lib/features/shell/presentation/main_shell.dart` `MainShell` (:38-291) |
| Shared motion | `lib/core/widgets/nuvo_motion.dart` `NuvoMotion` (:12-61), `NuvoHaptics` (:66-76), `NuvoPressable` (:89-185), `NuvoTabStack` (:388-489) |
| Toasts | `SnackBarThemeData` `lib/core/theme/app_theme.dart:212-222`; `ScaffoldMessenger` call sites |
| Arena tab | `lib/features/arena/presentation/arena_screen_fixed.dart` `ArenaScreen` (:34; re-exported by `arena_screen.dart:1`) — route `/arena` |
| Arena data | `lib/features/arena/data/arena_api.dart` (:30-85), `arena_models.dart` (:3-155), `presentation/arena_controller.dart` `arenaControllerProvider` (:272+) |
| Arena podium/rest | `arena_podium.dart` `ArenaPodium`, `arena_rest_board.dart` `ArenaRestList`/`ArenaRestArrow` |
| Race card backing data | `raceControllerProvider` (`race_controller.dart:1494`) → `GET /races` |
| Bell / Activity | `notification_bell.dart` `NotificationBell` (:12-69); `notifications_screen.dart` (route `/notifications`, `router.dart:198`) |
| Stats / level / badges | `progression_controller.dart` `progressionControllerProvider` (:456); `profile_screen.dart` `_StatsStrip` (:1200), `_LevelTrack` (:479); `badges_screen.dart` (route `/profile/badges`, `router.dart:417-420`) |
| Heat map | `profile/presentation/widgets/activity_heatmap.dart` `ActivityHeatmap` (:74+); `profileActivityProvider` (`activity_controller.dart:13-47`) |

---

## 0. Architecture + data map (verified in `server/worker/src`)

### Shell architecture — how the four tabs work today

- `main()` (`lib/main.dart:14-29`): `ensurePresentationModeLoaded()` (24),
  `ensureNuvoThemeModeLoaded()` (26), `unawaited(NuvoFlags.load())` (28),
  `runApp(ProviderScope(child: NuvoApp()))`.
- `NuvoApp` (`app.dart:140-153`): `MaterialApp.router(theme: light,
  darkTheme: dark, themeMode: nuvoThemeModeProvider, routerConfig:
  routerProvider)`.
- `routerProvider` (`router.dart:105-431`): one `StatefulShellRoute`
  (:274) with `navigatorContainerBuilder` → `NuvoTabStack` (:275) and one
  branch per entry in `nuvoDestinations` (:283-289). Branch → screen is
  `_tabScreenFor(path)` (:89-103): `/arena`→`ArenaScreen`,
  `/compete`→`CompeteScreen`, `/pass`→`PassScreen`,
  `/profile`→`ProfileScreen`. Tab pages are `NoTransitionPage` (:76-77);
  the directional slide lives in `NuvoTabStack` (`nuvo_motion.dart:388-489`).
- `nuvoDestinations` (`bottom_nav.dart:31-56`) is **the** index contract:
  `0 Arena /arena` · `1 Compete /compete` · `2 Friends /pass` (renders
  `PassScreen`) · `3 Profile /profile`. Branch order = nav order =
  transition direction.
- `MainShell` (`main_shell.dart`): first-mount fills for all canonical
  controllers (:95-128); resume revalidates race/arena/crew/notification/
  progression (:138-148); `_onTapTab` revalidates the tapped tab's data
  then `shell.goBranch(index, initialLocation: false)` (:157-196); the
  level-up + achievement moments live here (:204-233 →
  `showLevelUpMoment`/`showAchievementMoment`, `markLevelSeen`).
- Flags: `NuvoFlags` (`nuvo_flags.dart:12-53`) loads `custom_motion` +
  `crews` from `GET /config` asynchronously — server switches, not a
  build flag. `NUVO_INITIAL_LOCATION` dart-define exists
  (`router.dart:107`) — precedent for defines.

### Arena data path today

`GET /arena` (`arena.ts:127-163`, `arena_api.dart:30-85`) returns
`{mode, headerPulse, focusBoard, liveBoards[≤5], activity[], results[≤3]}`.
`buildRealBoard` (`arena.ts:378-437`) emits per board:
`id, source, title, proofLabel, progressLabel, boardContext,
primaryActionLabel, primaryActionType, progressPercent, racerCount,
isResult, badgeLabel, miniLeaderboard[≤5]{label, value, isCurrentUser,
profilePhotoUrl}`.

**Fields the Dart model parses but the real endpoint never emits:**
`myRank`, `chaseCopy`, `leaderName`, `leaderPhotoUrl`, `daysLeft`
(`arena_models.dart:77-81` parsed :100-104; absent from `buildRealBoard`
return :422-436). Do not rely on them.

Conditional `ETag`/`304` (`arena.ts:263-271`; `arena_api.dart:35,60-62`);
disk cache + stale-while-revalidate in `ArenaController`
(`arena_controller.dart:84-109` hydrate, :150-237 fetch,
`revalidate()` :132-139, `markStale()` :145-147).

### Canonical race payload (the richer source)

`GET /races` (`races.ts:1217-1294`) returns each race through
`shapeRaceResponse` (:716-836) — **shared by list and detail paths**
(:712-715 comment) — so list rows already carry, per race:
`participants[]{displayName, profilePhotoUrl, progressValue, rank}`
(:837+), `targetValue`, `finishLineAt` (:825), `startLineAt`, and
`viewerContext` (:823) = `{rank, previousRank, leaderUserId, leaderScore,
viewerScore, gapToLeader, gapToNextRank, goalRemaining,
timeRemainingSeconds, startsInSeconds, isLeading, isTied, isFinished,
isMember, attemptsUsed, attemptsRemaining}` (DTO
`race_models.dart:450-519`). The Dart `Race` parses all of it
(`race_models.dart:58,123,191-195`).

> Correction to COMPETE_RACES.md §1.2: `viewerContext` is **not**
> detail-only — `buildRaceResponsesBatch` routes every list row through
> the same `shapeRaceResponse` (:1162-1174). Rank/gap/time-left trend
> data is on the wire for `GET /races` today.

### Endpoint inventory used by Arena + shell

| Endpoint | File:line | Used for |
|---|---|---|
| GET `/arena` | `arena.ts:127-163` | Board order + board payload (focus first, then liveBoards) |
| GET `/races` | `races.ts:1217-1294` | `Race` objects: participants, `viewerContext`, `finishLineAt`, `targetValue`, format/scoring fields |
| GET `/progression` | `routes/progression.ts:30-56` | `progression.{level,currentLevelXp,nextLevelXp,xpToNext,progress,achievementsEarned,achievementsTotal,featuredBadges,nextAchievement,levelUnlock,newlyEarned,lastSeenLevel}` + `record.{active,finished,wins,winRatePercent}` (`profileRecord.ts:16-75`) |
| GET `/progression/badges` | `progression.ts:59-64` | Full badge collection → `/profile/badges` |
| POST `/progression/level-seen` | `progression.ts:97` | Level-up seen marker (MainShell :221) |
| GET `/notifications` | `notifications.ts:52-109` | Items + `unreadCount` + `nextCursor` |
| POST `/notifications/:id/read`, `/read-all` | `notifications.ts:113,125` | Per-row + clear-all |
| GET `/profile/activity?days&tz` | `profile.ts:85-107` | `[{date, proofs}]`, days clamped 7..366 |
| GET `/crew/feed` | `crew.ts:190-242` | `CrewActivityItem`s — `rank_changed` (`payload.overtakenUserIds`), `lead_changed` (`payload.displacedUserId`), actor{name,photo}, raceId/raceTitle, `destination` (`crew_activity_models.dart:75-140`) |
| GET `/crew` | `crew.ts:67` | Friend rows (v13 Crew tab + nudge faces) |
| GET `/users/:id` | `users.ts:124-199` | Public profile card behind `/u/:id` face taps — includes `level`, `achievementsEarned/Total`, `raceStats`, `racesWithYou`, `connectionStatus` |
| GET `/squads`, `/squads/:id` | `squads.ts:211,351` | Crew groups for the v13 Crew tab |
| GET `/pass/me` | `pass.ts:11` | Member pass (QR/`@handle`) |
| GET `/config` | `index.ts` | `NuvoFlags` server switches |
| POST `/races/:id/proof` | `races.ts:2028` | Proof submit (Submit-proof sheet's write — other spec) |

---

## 1. Global rules (v13 L5-18) — mapped to the shell

### 1.1 Light mode only (L6)

- **Current:** full light+dark themes — `nuvoThemeModeProvider`
  (`nuvo_theme_mode.dart:87-90`, persisted in `NuvoThemeModeStore`
  :14-60), `AppTheme.dark()` wired in `MaterialApp` (`app.dart:143-145`),
  `NuvoThemeColors.dark` + `NuvoSemanticColors.dark`
  (`app_colors.dart:373-415,536+`). An "Appearance" row exists on Profile
  (`profile_screen.dart:1406` `_AppearanceRow`).
- **Verdict:** REPLACE for the v13 shell only. Under `NUVO_V13`, force
  `themeMode: ThemeMode.light` in `MaterialApp` and hide the Appearance
  row; do **not** delete dark theme code (old shell keeps working,
  `NUVO_V13=false` retains user choice).
- **States:** n/a (build-time). Conflict logged in §5.

### 1.2 Colors (L6-8)

- **Current:** `NuvoColors` — `navy` `#07152D` (:8 ✓ spec match), `blue`
  `#1264FF` (:11 ✓), `page` `#FBFCFF` (:52 — spec wants `#F5F6F8`),
  `surface` `#FFFFFF` (:58 ✓), `muted` `#5E6C85` (:90 — spec `#5E6A80`),
  `divider` `#DCE3EE` (:69 — spec `#E6E9EF`), `gold` `#E0A72E` (:160 —
  spec `#F5B800`), `coral` `#C97968` (:41 — spec `#FF8A65`).
- **Verdict:** REPLACE/extend tokens. Add v13 tokens: `page #F5F6F8`,
  race palette `raceCoral #FF8A65`, `raceSun #FFC93C`, `raceLilac #CDBFFF`,
  `raceMint #9EE6C4`, `raceSky #B8D2FF`, `position1/gold → #F5B800`,
  `divider #E6E9EF`, `muted #5E6A80`. Existing `avatarPalette`
  (:168-185) is avatar-only — do not reuse for race cards. Prefer adding
  v13 aliases over mutating shared constants (old shell keeps its look).
- **Data:** none. **States:** n/a.

### 1.3 Signature look — 2-2.5px navy outline + hard offset shadow (L7)

- **Current:** already the design language. Cards/buttons:
  `Border.all(color: border, width: 2)` + `AppShadows.hardOffset` —
  e.g. nav bar (`bottom_nav.dart:142-147`), hero card
  (`arena_screen_fixed.dart:828-837`, offset 7,7), Compete field
  (`compete_screen_fixed.dart:437-442`). `NuvoColorRole.hardShadow`
  (:294-296) for role-tinted plates.
- **Verdict:** KEEP. Retune shadow offset to spec's 3-6px range where the
  v13 mock differs (hero currently 7,7; spec says 6px on race cards).
- **States:** presses sink — already `NuvoPressable.pressTranslateY=3`
  + `shadowCompress=0.6` (`nuvo_motion.dart:37-46`) — KEEP.

### 1.4 One colored hero + one blue primary action per screen (L9)

- **Current:** Arena today has a navy-outline hero + a 3-button
  `_QuickActions` row (arena_screen_fixed.dart:355-368) — two blue
  actions visible (Submit + Start) plus podium color below.
- **Verdict:** REPLACE composition — v13 gives Arena exactly one blue
  action per card ("Submit proof") and makes the hero the race-color
  card. Enforced by layout, not a token.

### 1.5 Open rows, thin dividers, section spacing 36-48 (L10)

- **Current:** v13 stats/rows style ≈ existing `_StatsStrip` dividers
  (`profile_screen.dart:1196+`) and `c.divider` usage. Arena today is
  card-heavy.
- **Verdict:** NEW for Arena's stats/achievements rows; existing divider
  token covers it.

### 1.6 Type: Manrope 500-800 (L11)

- **Current:** `GoogleFonts.manrope` everywhere —
  `app_text_styles.dart:20,98,166` (`google_fonts` in pubspec :21 ✓).
- **Verdict:** KEEP. Map spec sizes onto `AppTextStyles` (titles 24-28@800
  → `screenTitle`; section heads 19@800; body 13-15) — create v13 styles
  rather than re-editing shared ones.

### 1.7 Radii: buttons 14, cards 22-28, pills 99, icon tiles 10-16 (L12)

- **Current:** `NuvoRadii` (`app_geometry.dart`) — nav bar radius is
  height/2 = 32 (pill, `bottom_nav.dart:144`), cards `NuvoRadii.lg`/`hero`
  ≈ 22-28 already, buttons ~14. Close but verify per-widget at build.
- **Verdict:** KEEP/adjust constants under v13 theme extension only.

### 1.8 People = photos in navy circles; no initials; blue ring = you; tap → profile (L13)

- **Current:** `NuvoAvatar` (`nuvo_avatar.dart:30-56`) — photo →
  **initials fallback**, `borderColor`/`borderWidth` params, deterministic
  `nuvoAvatarColorFor` bg (:20-24). "You" rows tint blue but no blue ring.
  Face-tap → `/u/:id` exists (`pass_screen.dart:287-290`;
  `router.dart:146-151` `PublicProfileScreen`; `GET /users/:id` serves
  the card, `users.ts:124-199`).
- **Verdict:** REPLACE fallback — add a neutral-silhouette asset/painter
  (spec bans initials); add a `isYou`/`ringColor` param painting the blue
  ring. KEEP photo + tap behavior; every Arena face (card leaders, nudge)
  routes `/u/:id` — own avatar routes to `/profile` (tab switch, not
  push).
- **States:** photo loading (`CachedNetworkImage` already handles);
  no photo → silhouette; blocked/stranger → still tappable (public
  profile exists for everyone — product model).

### 1.9 Motion: one overshoot spring 420-600ms for presses, tab indicator, toggles, number pops; press sinks into shadow + light haptic (L14)

- **Current:** `NuvoMotion` (`nuvo_motion.dart:12-61`) — `pressIn` 80ms,
  `pressOut` 220ms, `select` 200ms, `tabSwitch` 250ms, `spring =
  Curves.easeOutBack` (:57), `pressTranslateY` 3, `pressScale` .97;
  `NuvoHaptics.select/press/confirm` (:66-76); nav pill animates 320ms
  easeOutCubic (`bottom_nav.dart:251-257`).
- **Verdict:** KEEP infrastructure, REPLACE tuning: introduce a shared
  `overshootSpring` (Cubic/spring spec, ~420-600ms) and apply to tab
  indicator, toggles, `NuvoPop`/number pops, press release — instead of
  per-widget `easeOutCubic`/`easeOutBack` mixes. Haptic already wired
  (selectionClick on nav :172; `NuvoPressable.haptic` :96,156).
- **States:** `MediaQuery.disableAnimationsOf` reduced-motion paths
  already exist (nuvo_motion.dart:134,141,226,423; bottom_nav:120,253) —
  KEEP.

### 1.10 Reward-only celebrations: confetti on join/accept/earn, "+N" on proof, rank pop; no decorative stickers/glow/pulse (L15)

- **Current:** confetti = hand-rolled `_Burst` CustomPainter
  (`board_moved_screen.dart:350-355` — **no `confetti` package in
  pubspec**). "+N" floats: `NuvoRepPulse`/`rep_burst_controller` in the
  camera flow (`ai_motion_proof_screen_io.dart:2477-2531`). Number pops:
  `NuvoPop` (:194-260), `NuvoNumberFlow`, `count_up_text.dart`.
  Level-up/achievement modals on `MainShell` (:204-233).
- **Verdict:** KEEP all; promote `_Burst` to a shared widget for
  Arena-level rewards (take-lead confetti after proof — owned by the
  Submit-proof spec; Arena just hosts the toast). No new dependency.

### 1.11 No dead buttons (L16)

- **Current:** matches `NUVO_PRODUCT_MODEL.md` dead-UI rule. Two live
  violations today: `ArenaBoard` demo boards snack-bar on tap
  (`_demoSnack` :594-596 — intentional, keep for demo mode); spec's
  "Swipe for more" label is affordance text, not a button.
- **Verdict:** KEEP rule; audit at build.

### 1.12 Toasts: small navy pill near bottom for confirmations (L17)

- **Current:** `SnackBarThemeData` — `backgroundColor: navy`, floating,
  `NuvoRadii.md` corners (`app_theme.dart:212-222`), used app-wide
  (`ScaffoldMessenger...showSnackBar`, e.g. `pass_screen.dart:159-167`).
- **Verdict:** KEEP mechanism; REPLACE shape → pill radius (99) and copy
  style. No new toast system.

### 1.13 Tab bar: white, outlined, 4 tabs (Arena, Compete, Crew, Profile), blue spring indicator under the active tab (L18)

- **Current:** `NuvoBottomNav` — white surface, 2px ink border, hardOffset
  shadow, floating pill (`bottom_nav.dart:130-182`) ✓ shape. Selected
  slot = **blue filled pill with icon+label** (`_NavSlot` :258-267) — spec
  wants outlined slots + a **blue spring indicator under** the active tab.
  Third destination is `/pass` labeled **"Friends"** (:44-49) — spec
  wants "Crew".
- **Verdict:** REPLACE slot presentation (keep the floating outlined
  bar + geometry contract `navDockHeight/navDockGap/bottomPadding`
  :88-114 — every screen's scroll inset depends on it). Indicator: small
  blue pill/underline animating with the §1.9 spring. Destination table:
  see §4 (`/crew` replaces `/pass`).
- **States:** 4 slots fixed; reduce-motion instant.

---

## 2. Arena tab (v13 L21-36)

Current composition (`arena_screen_fixed.dart`): `_ArenaHeader`
(greeting only, :631-696) → "Your next move" section label + `n/N`
(:300-313) → full-bleed `PageView` (`_boardsController`,
`viewportFraction: 1` :49) of `_NextMoveHero` cards → `_PageDots`
(:341-348) → `_QuickActions` (Submit/Start/Join, :355-368) →
`ArenaPodium` + `ArenaRestArrow` (:377-407) → `ArenaRestList` (:411-428).
Board order = `focusBoard` then `liveBoards`, `results` only when no live
boards (`_boardsFor` :547-558).

### 2.1 Header — "Hey [first name]" + streak/level line + bell + XP-ring avatar (L21)

| Element | Current | Verdict | Data |
|---|---|---|---|
| "Hey [first]" | `_ArenaHeader` renders "Arena" + "Good morning, {first}" (:679-693); first name = `user.fullName.split.first` (:92-93) | REPLACE copy/layout (keep name source) | `authControllerProvider.user` — HAVE |
| flame + "[N] day streak" | **none** — no user streak anywhere (server `streak` hits are the `daily_streak` race type, `races.ts:188,198`; in-app `_streakCount` is rep bursts) | **NEW — MISSING endpoint** | Proposed additive: `streakDays` on `GET /progression` (server computes consecutive verified-proof days from `move_logs`; additive JSON field, no schema change). Stopgap: derive from `GET /profile/activity` daily map (already fetched for §2.6) — flag: "does a missed day reset" is a product call; server field preferred |
| "Level [L]" | exists on Profile (`_LevelTrack` :479+) not Arena | KEEP data, NEW placement | `GET /progression` → `progression.level` (`progression.ts:30-56`); `progressionControllerProvider` (:456) — already revalidated on Arena-tab resume via MainShell (:146) |
| bell + coral unread badge → Activity | `NotificationBell` exists (`notification_bell.dart:12-69`) but is mounted only on PassScreen (`pass_screen.dart:2874`); badge uses `NuvoColors.danger` (:44) | KEEP widget, REPLACE badge color→coral + mount on Arena header | `unreadCountProvider` (`notification_controller.dart:399-400`) ← `GET /notifications` `unreadCount` (`notifications.ts:52-109`); loaded by MainShell (:113-118), revalidated on tab switch? — note: `/notifications` itself isn't revalidated by `_onTapTab` case 0; provider stays fresh via shell fills |
| "opening clears the badge" (spec L122) | rows mark read via `markRead` (:63,:90); explicit `markAllRead` button (:141) → `POST /notifications/read-all` (`notifications.ts:125`) | REPLACE to match spec: clear `unreadCount` optimistically on screen open (call `markAllRead`); per-row styling can still show read/unread | endpoint exists — HAVE |
| avatar in blue XP ring | `NuvoAvatar` photo (:30-56); no ring widget | **NEW widget** (progress ring around avatar; painter — `race_ring.dart` shows existing ring-painter precedent) | ring fraction = `progression.progress` (0..1) or `currentLevelXp/nextLevelXp`; tap → Profile tab (branch 3) — HAVE |
| "no separate level bar" | Profile's `_LevelTrack` stays on Profile | KEEP (no change) | — |

**States:** header data is spread across three providers — render per-
provider: name/avatar instant (auth); streak/level line skeletons until
`progressionControllerProvider` has a value, hides (not errors) on
failure (progression failure must not blank the header — mirror
`_ProgressionUnavailable` fallback pattern `profile_screen.dart:1084`);
bell badge shows only `unreadCount>0`; refresh = shell resume/tab
revalidation + pull-to-refresh must also hit
`progressionControllerProvider.revalidate()` (add to Arena's refresh —
currently only `arenaControllerProvider.loadSnapshot()` :209-211).

### 2.2 "YOUR RACES · [count]" + "Swipe for more" (L22)

- **Current:** `_SectionLabel('Your next move', trailing: 'n / N')`
  (:305-310).
- **Verdict:** REPLACE copy/trailing ("Swipe for more" hint, no count
  badge when 1 race; hide hint entirely when the dashed card is the only
  page — dead-UI rule).
- **Data:** count = live boards (`_boardsFor` count) or
  `raceState.races.where(raceIsActive).length` — prefer the same list
  that drives the swiper for consistency. HAVE.

### 2.3 Race swiper + cards + dashed last card + dots (L23-32)

- **Current:** `PageView(viewportFraction:1)` full-page
  `_NextMoveHero` cards with arc-swipe transform
  (`_BoardCarouselItem` :764-769) and `_PageDots` (non-interactive
  `AnimatedContainer`s :1103-1128).
- **Verdict:** REPLACE card + presentation. `PageController(
  viewportFraction ≈ 318/screenWidth + gap)` for peek + snap; card =
  race-color background + outline + 6px shadow. Drive card **content**
  from the `Race` objects (`raceById` join already exists at :74-76,
  :332) and page **order** from the arena snapshot.

#### 2.3a Card data — field-by-field

| v13 field | Endpoint/field | Status |
|---|---|---|
| race color background | **MISSING** — no `color` column on `races` (SELECTs `arena.ts:174-177`; response `shapeRaceResponse` :788-836), nothing in `race_models.dart` | Client-deterministic palette `hash(race.id) % 5` over the v13 race palette (same proposal as COMPETE_RACES.md §1.2/§7 — keep consistent). Optional additive later: `races.color` TEXT + `color` on create/patch/read |
| ≤3 leader faces | `race.participants` ranked (`serverRankedParticipants`, `race_display.dart:131-151`) `.profilePhotoUrl`; or `board.miniLeaderboard` top-5 (already has photos, `arena.ts:410-419`) | HAVE — prefer `race.participants` (canonical ranks) |
| "[Movement] · [N] racers" | movement = `raceActivityTitle(race)` (`race_display.dart:61-78`; needs `activityId`/`movementType` — not on board JSON, IS on `Race`); count = `board.racerCount` / `race.participants.length` | HAVE via race join. (Board lacks an activity label — additive `activityLabel` on board JSON only if the race list is ever unavailable) |
| time left | `race.finishLineAt` (`race_models.dart:101`; `races.ts:825`) + `viewerContext.timeRemainingSeconds`/`startsInSeconds` | HAVE via race join. `ArenaBoard.daysLeft` is parsed but never emitted by the real endpoint — do not use |
| race name 18@800 | `board.title` / `race.title` | HAVE |
| score huge (84px) + "/ goal" | `viewerContext.viewerScore` + `race.targetValue` (or `goalRemaining`); board `progressLabel` "v / t units" is the display-string fallback (`arena.ts:96-99`) | HAVE via race join. Format with `raceScoreLabel`/`raceProgressLabel` (`race_display.dart:94-129`) — never raw ints (duration/plank races) |
| your place (right) | `viewerContext.rank` / `rankForUser(race, uid)` (`race_display.dart:164-172`); `board.myRank` parsed-but-never-emitted — do not use | HAVE via race join |
| progress bar navy/white | `viewerContext` ratio (`viewerScore/targetValue`, `scoreDirection`-aware, or `raceLaneGeometry` fractions `race_display.dart:209-258`); board `progressPercent` fallback | HAVE. REPLACE `NuvoRacePath` marker lane (:948) with the spec's plain bar (`nuvo_progress_bar.dart` exists) — see §3 |
| gap line "9 behind Alex" / "Leading Priya by 4" / "crossed the finish line" | `viewerContext.gapToLeader` + leader name (participants[0] / `leaderUserId`), `gapToNextRank` for "ahead by", `isFinished`/`goalRemaining<=0` for finish line; `raceNearestRival` (`race_display.dart:265-280`) names the rival | HAVE via race join. `ArenaBoard.chaseCopy` parsed-but-never-emitted — could also be emitted server-side later (additive) |
| "Submit proof" button | card-level `openAiMotionProof(context, ref, race)` (`ai_motion_proof_entry.dart:25-70`) → `/race/:id/proof` (`router.dart:370-374` `SubmitProofScreen`, `submit_proof_screen.dart:34-35`) or `/race/:id/proof/ai-motion` for camera races (`router.dart:377-381`) | KEEP entry. The sheet itself = COMPETE_RACES.md §4 (other agent). Arena passes `race.id` — per-card race resolution, not the active board |
| card tap → Race detail | `_openBoard` → `context.push('/race/${board.id}')` (:589-592) | KEEP — `/race/:id` route (`router.dart:343-348`) |
| finished race in swiper | `isResult` boards (`results[]`, `_boardsFor` :556) — spec gap line "You crossed the finish line" implies finished cards; CTA switches to "Open board"/race detail | KEEP results in order after live cards (current ordering already does); `viewerContext.isFinished` + `finalStandings` drive the copy |
| dashed "Up for another one?" card | none (`_FirstRunState` :1286 is the zero-race state) | **NEW** — client-only sentinel appended as last page: "Start a race" → `/races/new` (`router.dart:305`), "Join a race" → Compete tab (`goBranch(1)` or `/compete`) — spec says "to Compete" not `/races/join`; follow spec, and keep `/races/join` reachable on Compete |
| page dots: wide navy pill active, tap scrolls | `_PageDots` (:1103-1128) — right look (20px pill vs 6px dots), not tappable | REPLACE — wrap in `NuvoPressable`/`GestureDetector` → `_boardsController.animateToPage(i)`; keep pill shape |

#### 2.3b Board sourcing — recommended composition

Swiper pages = `[for b in snapshotBoards] b` where each renders the
`raceById[b.id]` `Race` when loaded (board fields as fallback —
miniLeaderboard/racerCount/progressLabel already cover a degraded card),
then the dashed sentinel. `results[]` boards render as finished cards
(gap line + "Open board"). This preserves `/arena`'s server-chosen
ordering while giving the card every field the board JSON lacks.

**States:**
- loading skeleton → `_LoadingState` exists (:236-240) — restyle to card
  silhouette.
- zero races → `_FirstRunState` (:1286) replaced by the dashed card as
  the *only* page (it IS the empty state).
- error + retry → `_ErrorState`/`NuvoErrorState` (:252-261) KEEP;
  offline-with-cache → `NuvoOfflineBanner` (:229-235) KEEP.
- partial data: snapshot ok but `GET /races` still loading → render
  board-degraded card (title, faces, % only) — never a blank card.
- refresh → pull-to-refresh currently hits only `loadSnapshot()`
  (:209-211); extend to `raceControllerProvider.revalidate()` +
  `progressionControllerProvider.revalidate()` +
  `notificationControllerProvider.revalidate()` so every visible element
  refreshes on one gesture.

### 2.4 Nudge row — "[photo] passed you · [race] · [N] ahead" + "Take it back" (L33)

- **Current:** none on Arena. Precedent: `_actionFor` on PassScreen
  renders exactly this CTA for `rank_changed`/`lead_changed` feed items
  (`pass_screen.dart:328-343` — labels "Take it back").
- **Verdict:** NEW (UI + wiring, no new endpoint).
- **Data:** `GET /crew/feed` (`crew.ts:190-242`) items via
  `crewActivityProvider` (already revalidated by MainShell :123-128 and
  tab-2 taps). Filter: latest `type == 'rank_changed'` with
  `payload.overtakenUserIds` containing my id, or `lead_changed` with
  `payload.displacedUserId == myId` (`CrewActivityItem.involvesUser`
  logic, `crew_activity_models.dart:126-136`) → actor photo/name,
  `raceTitle`, `raceId` → "Take it back" opens Submit-proof for that
  race via `openAiMotionProof` (same §2.3a entry; needs `raceById[raceId]`
  — fall back to `/race/:id` if the race isn't in the list).
  "ahead by N": `payload` carries `previousRank`/`newRank`
  (races.ts:622) — or compute via `viewerContext.gapToNextRank`.
- **Fallback nudge** ("if nobody passed you, show the next most useful
  nudge"): options ranked by usefulness — (a) race ending soonest
  (`viewerContext.timeRemainingSeconds` smallest positive), (b)
  `headerPulse` from `/arena` (`arena.ts:333-342` — "N boards need
  proof"), (c) solo race waiting for racers. Hide the row when none apply.
- **States:** skeleton line during first feed load; hidden when feed
  empty/unread-by-rule; tap error → snackbar + keep row; refresh via
  crew feed's SWR (45s stale window, `crew_activity.dart:279-289`).

### 2.5 Stats triple — RACING / WINS / WIN RATE (L34)

- **Current:** `_StatsStrip` on Profile (`profile_screen.dart:1196+`)
  fed by `progression?.record` (:103-120) with a race-list fallback
  (:114-120).
- **Verdict:** REPLACE placement → Arena section; reuse the widget/data
  path (it's a `_StatsStrip` private class — lift or rebuild in v13
  style; same source).
- **Data:** `GET /progression` → `record.{active,wins,winRatePercent}`
  (`progression.ts:34-56`; `readProfileRecord` `profileRecord.ts:16-75`).
  Racing=active, Wins=wins, Win rate=winRatePercent%. HAVE.
- **States:** skeleton until first progression value; on failure show
  race-list derived fallback (existing pattern :114-120) or hide the
  section; refresh with §2.3b pull-to-refresh.

### 2.6 Activity heat map — 18 weeks × 7 (L35)

- **Current:** `ActivityHeatmap` (`activity_heatmap.dart:74+`) —
  `weeks = 20` const (:80) with `heatmapDays(today, weeks: weeks)` (:114),
  `[N] proofs`/`[N] active days` computed (:115-116), Less→More legend,
  blue intensity ramp (:121-127). Mounted on Profile as
  `ActivityHeatmapSection` (profile_screen.dart:212).
- **Verdict:** REPLACE placement → Arena; parameterize `weeks` → 18
  (constructor arg; don't fork the widget — Profile keeps its own
  section per the Profile spec).
- **Data:** `GET /profile/activity?days=126&tz=<offsetMin>`
  (`profile.ts:85-107`; `ProfileActivityApi.fetch` `activity_api.dart:15-40`
  default 140 — pass 126 for exactly 18 weeks);
  `profileActivityProvider` (`activity_controller.dart:13-47`) — 30-day
  disk cache, offline falls back to cache (:42-45). HAVE.
- **States:** skeleton = `naturalHeight` placeholder (:97-109 pattern);
  empty map renders an all-grey map (not an error) — matches current
  "section simply stays hidden" contract for fetch failure
  (`activity_controller.dart:11-12`) — for v13 prefer showing the empty
  map + counts of 0 over hiding (it's a spec element). `autoDispose`
  provider — add to §2.3b refresh set or it refetches on each Arena
  mount (fine, it's cached).

### 2.7 Achievements — "[earned] of [total]" link + 4 badge tiles → Badges (L36)

- **Current:** `_AchievementsRow` on Profile (:1123-1194) — featured
  badges via `NuvoAchievementBadge` (`nuvo_badges.dart`), tap →
  `/profile/badges` (:1140; `BadgesScreen`, router.dart:417-420).
- **Verdict:** REPLACE placement → Arena row of 4 tiles; KEEP data path
  and destination.
- **Data:** `GET /progression` → `achievementsEarned`,
  `achievementsTotal`, `featuredBadges` (up to `featuredSlots`),
  `nextAchievement` (`progression.ts:30-56`; domain shape
  `domain/progression.ts:558-587`). Fill: featured first, then
  `nextAchievement`, then most-recent `newlyEarned` — need 4 slots; if
  fewer earned, show progress/dashed tiles per spec's locked-tile
  language (Badges-page spec L104 "Locked ones are dashed") — the full
  collection is `GET /progression/badges` (`progression.ts:59-64`) if
  client needs >featured. HAVE.
- **Copy:** say "earned"/"progress" — never "unlock" (product language;
  v13 spec's own "unlocking" wording on the Badges page is flagged in
  COMPETE_RACES §6 conventions; same rule here).
- **States:** skeleton tiles; `achievementsTotal == 0` → hide row;
  tap → `/profile/badges`; refresh with progression.

---

## 3. Current Arena/shell features v13 doesn't show — adapt, don't drop

| Feature | Where | Adaptation |
|---|---|---|
| `ArenaPodium` + `ArenaRestList` + `ArenaRestArrow` (top-3 podium, rest leaderboard) | `arena_podium.dart`, `arena_rest_board.dart`; mounted :377-428 | REMOVE from Arena home (v13 puts podium on Race detail — spec L63; leaderboard intent folds into card faces + gap line). **Do not delete the widgets** — reuse on Race detail v13. Conflict vs product model "Arena owns the podium" → §5 |
| `NuvoRacePath` marker lane in hero | `nuvo_race_path.dart` (:948 in arena) | REPLACE on Arena card by the plain progress bar; keep widget if Race detail still uses it |
| `headerPulse` string ("N boards need proof") | `arena.ts:333-342`, rendered `arena_screen_fixed` (pulse line) | Fold into "YOUR RACES · N" label or the §2.4 fallback nudge |
| `_QuickActions` row (Submit/Start/Join) | :355-368 | DELETE — replaced by per-card Submit + dashed card's Start/Join |
| `ArenaActivity` list (`snapshot.activity`) | `arena_models.dart:140+`; server always returns `[]` (`arena.ts:349`) | DELETE usage — dead field; v13's social feed lives behind the bell + Crew tab |
| `_FirstRunState` (ideas + first-race CTA) | :1286+ | REPLACE by the dashed swiper card (same two CTAs); keep idea-prefill pattern if wanted on the card (`RaceCreatePrefill` :267-270) |
| `NuvoOfflineBanner` + `AuthStatus.offline` | :229-235, :292-298 | KEEP — quiet banner above the swiper |
| Demo/preview seams (`preview`, `debugSnapshot`, `_previewSnapshot`, `_demoSnack`) | :35-42,:71-73,:594-596,:1624 | KEEP — v13 Arena keeps `debugSnapshot` for tests/demos; demo boards render through the same card with defaults for missing fields |
| ETag + disk cache + SWR on arena/feed/races/notifications | `arena_controller.dart`, `crew_activity.dart`, `race_controller.dart`, `notification_controller.dart` | KEEP — v13 sections reuse the same controllers; don't re-block the screen on refresh (`refreshing` keeps cached data visible) |
| Level-up + achievement moments | `main_shell.dart:204-233` | KEEP on MainShell — matches v13's reward rules; restyle dialog to v13 |
| `NuvoTabStack` directional slide + keep-alive branches | `nuvo_motion.dart:388-489` | KEEP |
| Dock geometry contract (`navDockHeight`/`bottomPadding`) + `_DockOcclusion` fade | `bottom_nav.dart:86-114`, `main_shell.dart`, bottom fades (:462-483) | KEEP — v13 dock still floats; same inset math |
| `NuvoPressable`/`NuvoPop`/haptics/reduced-motion | `nuvo_motion.dart` | KEEP — retune per §1.9 |
| `_PageDots` | :1103-1128 | REPLACE — same visuals + tap-to-page |
| Pull-to-refresh (`RefreshIndicator`) | :204-211 | KEEP — extend provider set (§2.3b) |
| `LiveRefresh` helper (auto revalidate on visible) | `live_refresh.dart` (PassScreen wraps with it, `pass_screen.dart:550-551`) | Consider for Arena — optional parity with other tabs |
| First-race guide (`first_use_guide`, `FirstRaceGuideKeys`) | `first_use_guide.dart`; Compete coach :222-235 | KEEP — retarget keys onto v13 widgets |
| `memberPassProvider` / GET `/pass/me` (My Nuvo code, QR) | `member_pass_provider.dart`; `pass.ts:11` | KEEP — v13 puts the QR button on the Crew tab header (other spec); nothing on Arena needs it |
| Push service + deep links + `pending_destination` | `app.dart`, `push_service.dart`, `deep_link_controller.dart` | KEEP — shell infra, untouched by the flag |
| `presentationModeEnabledProvider` + `PresentationDemoData.arenaSnapshot` | `presentation_demo.dart:99,116,528+` | KEEP — demo accounts must render the v13 shell with fixtures; demo boards lack new fields → card tolerates missing race/viewerContext (degraded card §2.3b) |

---

## 4. New shell structure + `NUVO_V13` flag

### 4.1 v13 destination table (proposal)

```dart
// New, parallel to nuvoDestinations (bottom_nav.dart:31-56):
const v13Destinations = <NuvoDestination>[
  NuvoDestination(path: '/arena',   label: 'Arena',   icon: ..., selectedIcon: ...),
  NuvoDestination(path: '/compete', label: 'Compete', icon: ..., selectedIcon: ...),
  NuvoDestination(path: '/crew',    label: 'Crew',    icon: ..., selectedIcon: ...),  // NEW path
  NuvoDestination(path: '/profile', label: 'Profile', icon: ..., selectedIcon: ...),
];
```

- `/arena`, `/compete`, `/profile` keep paths → branch navigators, deep
  links, `context.go('/compete')` call sites, and `_indexFor`
  (`main_shell.dart:150-155`) all keep working.
- Third branch moves `/pass` → **`/crew`**. `/pass` gets a
  `GoRoute redirect → /crew` so old links/pushes land on the new tab
  (`context.go('/pass')` call sites to update in Phase B:
  `crew_groups_screen.dart:40`, `public_profile_screen.dart:214` — plus
  `_onTapTab`/`_leave` fallbacks). `/crew` is only an API prefix on the
  Worker — no client route collision (`/crews` groups routes are
  distinct paths :169-187).
- The v13 Crew screen merges `PassScreen` content (friends, requests,
  feed via `crewControllerProvider`/`crewActivityProvider`) with squads
  (`squadControllerProvider` → `GET /squads`) — content spec is another
  agent's doc; the shell only guarantees the branch + flag-gated
  `NuvoFlags.crews` behavior (`nuvo_flags.dart:20`).

### 4.2 Flag mechanics (proposal)

```dart
const bool kNuvoV13 = bool.fromEnvironment('NUVO_V13', defaultValue: false);
```

- **Where:** a new `lib/core/config/` constant (compile-time — synchronous,
  unlike `NuvoFlags.load()` which is server config fetched async at
  `main.dart:28`). Safe to read at provider/router construction; dead
  branch tree-shakes in release builds.
- **Selection point — the router/provider boundary, not `main()`:**
  - `router.dart` branches: `for (final d in (kNuvoV13 ? v13Destinations : nuvoDestinations))` — the existing generator at :283 needs no structural change.
  - `_tabScreenFor` (:89-103): map `/crew` → `CrewTabScreen`, and each v13 path → its v13 widget (e.g. `ArenaScreenV13`) while the v13 flag is on; old screens stay registered under the old table.
  - `bottom_nav.dart`: `kNuvoV13 ? V13TabBar : NuvoBottomNav` inside `MainShell`'s dock slot — geometry contract (`bottomPadding`) must be honored by the new bar.
  - `MainShell`: `_paths`, `_indexFor`, `_onTapTab` revalidation switch (:170-186) must read the active table (tab-2 becomes crew+feed+notifications; `/crew` branch revalidates `squadControllerProvider` too).
  - `app.dart`: `themeMode: kNuvoV13 ? ThemeMode.light : ref.watch(nuvoThemeModeProvider)` (§1.1).
- **Fork nothing shared:** auth (`auth_gate` redirect uses location
  strings — keep `/pass`→`/crew` redirect consistent), race detail,
  proof routes, camera flow, all pushed routes — identical under both
  flags. Only the shell dock + the four tab screens differ.
- **Fallback safety:** `NUVO_V13` unset ⇒ current app, byte-for-byte.
  New screens land in `lib/features/*/presentation/v13/` (or parallel
  files like `arena_screen_fixed.dart` did) — no existing file needs a
  structural rewrite for the flag to work.

---

## 5. Conflicts: v13 spec vs AGENTS.md / product model

1. **Stats/heat map/achievements on Arena (v13 items 5-7)** — product
   model: Arena owns the next-move board, not dashboards/stats
   (`NUVO_PRODUCT_MODEL.md` screen ownership). Resolution: follow the v13
   spec (it's the approved target design) — keep sections *below* the
   race swiper so Arena still reads next-move-first; recommend updating
   `NUVO_PRODUCT_MODEL.md` when v13 ships. **Flag for sign-off.**
2. **"Crew" tab replaces "Friends"** — product model: Friends =
   person-to-person graph, Crews = named groups (`AGENTS.md` language
   section; distinct `/crew` vs `/squads` APIs confirm). v13 merges them
   into one Crew tab (spec L66-78). Resolution: single Crew tab per v13;
   friends + feed content and squads coexist on it; `/pass` redirects to
   `/crew`. Do not silently rename — this is a real IA change; the Crew
   tab spec owns the merge details.
3. **"private profile" toggle (spec L109)** — product model: "Private
   profiles do not exist. Everyone is visible." Resolution: **omit the
   toggle entirely** in v13 Settings; `GET /users/:id` already encodes it
   (`users.ts:188` `isPrivate: false // legacy key`). Blocking stays the
   only privacy control. (Settings is another spec's scope — recorded
   here for consistency.)
4. **"Challenge [Name]" (spec L94)** — banned word. Resolution:
   **"Race [Name]"** (consistent with COMPETE_RACES.md §6.1). Same rule
   anywhere Arena copy borrows spec text ("Take it back" stays).
5. **Light-mode-only vs existing dark mode** — §1.1: flag-scoped light
   enforcement, dark code kept, Appearance row hidden under v13.
6. **Arena podium removed** — product model assigns Arena the podium
   surface; v13 moves podium to Race detail and Arena keeps leader faces
   + gap line. Resolution: follow v13; reuse `ArenaPodium`/`NuvoPodium`
   widgets on Race detail rather than deleting them.
7. **"unlock" wording** — product language bans it; v13 spec text uses
   "unlocking" (Badges page). Resolution: implementation copy says
   "earned"/"progress"/"up next"; doc and code never say unlock.
8. **"Swipe for more" + dots** — trivial: v13 uses both a swipe hint and
   dots; keep both (hint hides once swiped/after first session —
   `firstUseStore` pattern exists for such once-ness if desired).

---

## 6. Missing data summary

| v13 need | Status | Proposed additive API / client path |
|---|---|---|
| Day streak (header) | **MISSING** | Add `streakDays` to `GET /progression` response (count consecutive days with verified `move_logs` in viewer TZ — additive field, no schema change). Stopgap: derive from `GET /profile/activity` map client-side |
| Race color | **MISSING** | Client-deterministic palette `hash(raceId) % 5` (consistent w/ COMPETE_RACES §7); optional later: `races.color` column + emit |
| "Who passed me" nudge | **HAVE** | `GET /crew/feed` `rank_changed`/`lead_changed` items — client filter only |
| Gap/place/score/goal/time-left/faces per race | **HAVE** | `GET /races` `viewerContext` + `participants` + `finishLineAt` via `shapeRaceResponse` (list path included — `races.ts:712-715,823,1162-1174`) |
| Leader faces on board-only fallback | **HAVE** | `board.miniLeaderboard` top-3 `profilePhotoUrl` (`arena.ts:410-419`) |
| Activity/movement label per board | **HAVE via join** | `raceActivityTitle(race)`; additive `activityLabel` on board JSON only if needed |
| Streak/level/XP/unread/stats/heatmap/achievements | **HAVE** | `GET /progression` (+`record`), `GET /notifications` (`unreadCount`), `GET /profile/activity?days=126&tz`, `GET /progression/badges` |
| "Opening Activity clears badge" | **HAVE** | `POST /notifications/read-all` (`notifications.ts:125`) — call on screen open |
| Dashed last card | **NEW client-only** | No API |
| Crew tab destination | **NEW route `/crew`** | Client-only; content providers all exist (`crewControllerProvider`, `crewActivityProvider`, `squadControllerProvider`, `memberPassProvider`) |

---

## 7. Guardrails for the build phase

- **No-touch files (never plan edits):** `auth_api.dart`,
  `auth_repository.dart`, `auth_controller.dart`, `auth_gate.dart`,
  `secure_token_store.dart`, `ai_motion_proof_screen.dart`,
  `motion_validators.dart`, `pose_detector_service.dart`,
  `camera_image_converter.dart`, all iOS native files. The flag must not
  fork anything on this list — `auth_gate.dart` location-based redirects
  stay single-sourced (the `/pass`→`/crew` redirect lives in
  `router.dart`, not auth).
- **Do-not-casually-touch:** `race_api.dart`, `race_repository.dart`,
  `race_controller.dart` — the v13 card *reads* `raceControllerProvider`
  but changes to it need the AGENTS task declaration.
- **`bottom_nav.dart` geometry contract:** `navDockHeight`,
  `navDockGap`, `bottomPadding()` (:86-114) are consumed by every tab
  screen's scroll inset — the v13 bar must implement the same contract or
  update every caller.
- **`pubspec.yaml`/`pubspec.lock` — no changes.** Already present:
  `google_fonts` (Manrope :21), `flutter_riverpod` :15, `go_router` :18,
  `shimmer` :23, `flutter_animate` :24, `rive` :25, `qr_flutter` :26,
  `camera` :55, `google_mlkit_pose_detection` :56,
  `google_mlkit_barcode_scanning` :60 (deliberately *not*
  `mobile_scanner` — comment :57-60), `cached_network_image` :40.
  **Missing:** `confetti` (use the `_Burst` painter pattern,
  `board_moved_screen.dart:350+`) and `mobile_scanner` (intentional —
  QR scan uses `google_mlkit_barcode_scanning`, see `/scan` route
  :142-144).
- **Avatar rule:** v13 bans initials — add a silhouette fallback to
  `NuvoAvatar` (new param/default for v13 call sites) instead of editing
  initials out globally (old shell + other screens still rely on
  initials).
- **State contract everywhere:** every new section ships skeleton /
  empty / error+retry / pull-refresh per §2; never block the whole
  screen on a secondary provider (streak/level/nudge/heatmap degrade or
  hide).
- **Verification (read-only this phase):** no Flutter files changed, so
  `flutter analyze` isn't required for this doc. Phase B must run
  `flutter analyze --no-fatal-infos` (baseline: 4 infos in
  `auth_controller.dart`) and `cd server/worker && npm run typecheck`
  (baseline: clean) if any Worker proposal lands.
