# v13 redesign — feasibility, adaptations, ordered build plan

Inputs: `PROTOTYPE_V13_SPEC.md`, `SCREEN_INVENTORY.md`, `specs/ARENA_SHELL.md`,
`specs/COMPETE_RACES.md`, `specs/CREW_SOCIAL.md`, `specs/PROFILE.md`,
`specs/ACTIVITY_ONBOARDING.md`. Base: `motion-ota-tuning` 0a6f761 →
branch `redesign/v13`.

## 1. Verdict

The v13 design is buildable on the current code. Most of what the
prototype shows is already on the wire:

- `GET /races` includes `viewerContext` (rank, gaps, time left, leader)
  and `participants` (with photos) for list rows, which is enough for the
  Arena swiper, Compete live cards and the Race detail podium.
- `GET /progression` provides level, XP, record, badges and featured slots.
- `GET /profile/activity` provides the heat map.
- `GET /notifications` provides the unread count, and `read-all` clears it.
- `GET /crew/feed` provides the "passed you" nudge, the feed and cheers.
- `/squads/*` covers crews with owner/admin/member roles.
- `GET /users/:id` covers public profiles and races with you.
- Block, report, remove friend, username check, photo upload, delete
  account and notification preferences already exist.

What's missing is additive Worker work (section 4) and client-side
derivations (race color, gap copy, "moves you to 1st" preview).

No pubspec change is needed:

- Fonts: `google_fonts` (Manrope).
- QR: `qr_flutter`, plus `google_mlkit_barcode_scanning` for scanning.
- Sharing: `share_plus`.
- Animation: `flutter_animate`.
- Confetti: built as a small CustomPainter. The `_Burst` painter pattern
  already exists in `board_moved_screen.dart`.

## 2. Decided adaptations

Spec vs repo rules and real features:

| # | Topic | Decision |
|---|---|---|
| A1 | "Private profile" toggle | **Dropped** (private profiles don't exist). Privacy = "Show my activity map", "Who can race me" (Everyone / Friends), "Blocked accounts". |
| A2 | "Challenge [Name]" / "Who can challenge me" | **"Race [Name]"** / **"Who can race me"**. Banned word. |
| A3 | Tab 3 "Crew" | Follow v13. Tab label "Crew"; it holds friends (person links) **and** crews (groups). Copy keeps the friend/crew distinction ("Add friend", "Your crews"). `/pass` redirects to `/crew`. NUVO_PRODUCT_MODEL.md gets a v13 note at the end. |
| A4 | Manual proof | Server requires photo evidence for non-AI proofs (`races.ts:2085`). Manual mode = stepper **plus a required photo row**. Not faked, contract unchanged. |
| A5 | "Message" on non-friend profile | **Dropped.** It would be a button that only explains it can't work, which breaks the no-dead-buttons rule. |
| A6 | Streak (header, Best streak, Streak buddies, Streaks filter) | **Build** a server-derived day streak from verified `move_logs` (additive keys on `/progression` and `/users/:id`). |
| A7 | Locked badges on public profiles | Show locked tiles from catalog metadata only (`key, name, iconKey`), **never** a friend's progress. |
| A8 | Featured badge slots | v13 max 3, but the server grants slots by level. The UI renders the unlocked slots, up to 3. |
| A9 | Light mode only | v13 shell forces `ThemeMode.light`. Dark code stays for the old shell. The "Appearance" row is hidden under v13. |
| A10 | Arena podium / stats on Arena | Follow v13. Podium moves to Race detail and reuses `NuvoPodium`. |
| A11 | "unlock" wording on Badges | Copy uses "closest to earning" / "up next". |
| A12 | Crew battle | Additive Worker feature, built **last** (W4). The section is hidden when there's no active battle, so it's never an empty or dead block. |
| A13 | "Add friend" on Crew tab | Opens My Nuvo code on the **Scan** segment, as the spec says. Search stays reachable from the friends list. |
| A14 | Real features not in v13, kept | Race settings, cancel, leave, report race, rematch and proof review go in the Race detail 3-dot menu or rows. Teach movement / custom movements become the "Custom" tile in composer step 2. Manual (non-movement) goals become "Custom goal" in step 2. Invite code join becomes "Join with a code" on Compete and Crew. Member pass becomes My Nuvo code. Legal links and replay guide go in Settings › Support. The level-up and achievement moments are kept as reward moments with confetti. Move log is a collapsed "Proofs" section under Race detail (proof transparency + review). |
| A15 | Race color | Client-deterministic: `palette[hash(race.id) % 5]` (coral, sun, lilac, mint, sky). Crews use the server `color_key` (W2), with the same hash as fallback. |
| A16 | Haptics / sounds prefs | Haptics = local pref gating `NuvoHaptics`. **Sounds dropped** (no sound system exists; a toggle would be dead). |
| A17 | Settings › Notifications rows | Map onto existing server categories (passes = rank changes, invites, results, cheers = reactions, reminders = race_starting). |

## 3. Architecture for the build

- `lib/core/config/v13.dart`:
  `const kNuvoV13 = bool.fromEnvironment('NUVO_V13', defaultValue: true);`.
  Setting `--dart-define=NUVO_V13=false` restores the old shell
  byte-for-byte.
- New UI lives in `lib/features/<area>/presentation/v13/` and
  `lib/core/v13/` (tokens, widgets). Old screens stay untouched until S9,
  which deletes everything only the old shell uses. Stage S9 then removes
  the flag.
- Router: `router.dart` picks `v13Destinations` (`/arena`, `/compete`,
  `/crew`, `/profile`) and `_tabScreenFor` maps to the v13 screens. Pushed
  v13 routes are added under new paths only where a screen is genuinely
  new (`/races/new` and `/race/:id` swap their builder by flag).
- Every network surface uses one state widget set: `V13AsyncView`
  (loading skeleton / empty / error + Retry / pull-to-refresh). Mutations
  use optimistic update + rollback + error toast.
- Profile taps: one helper `openPerson(context, userId)` → `/profile` tab
  if it's me, else `/u/:id`.

## 4. Worker additions

All additive migrations 0048+, tests in `server/worker/test`,
`docs/API_CONTRACT.md` updated, deployed to **dev only** (`nuvo-api-dev`).

| Stage | Migration | Adds |
|---|---|---|
| W1 profile | `0048_v13_profile.sql`: `profiles.bio`, `favorite_movement_key`, `activity_map_shared`, `race_invites_from`; `user_mutes` | `POST /profile` + `GET /profile/me` new fields (bio ≤ 80); streak (`streakDays`, `bestStreakDays`) + `friends` + `proofsThisWeek` on `/progression.record`; `GET /users/:id` additive `bio, favoriteMovementKey, friendsCount, mutual{count,preview}, versus{…}, friendship{connectedSince,badges[]}, lockedAchievements, muted, activityShared`; `GET /users/:id/activity`; `/mutes` CRUD; mute filtering on feed + notification fan-out; respect `race_invites_from` on race invites. |
| W2 crews | `0049_v13_crews.sql`: `squads.bio, color_key, icon_key`; `squad_members.muted_at`; join requests (`status='requested'`); `squad_recurring_races` + `squad_recurring_optouts` | Additive fields on `GET /squads` / `GET /squads/:id` (ownerName, memberPreviews, myRankWeek, nextRecurring, stats{wins,races,streakDays}, createdAt); `GET /squads/:id/standings?period=week\|all`; `GET /squads/discover`; `GET /squads/:id/preview`; join-request + approve/decline; `PATCH` identity; mute; `POST /reports/squads/:id`; recurring CRUD + per-member auto-join + scheduled spawn on the existing cron; any active member can start a crew race; `GET /crew/requests` mutuals; `badge_earned` feed item. |
| W3 races | none | `GET /races/open` (friends' races I'm not in); `racesTogether` on `GET /crew` rows; `GET /leaderboard?scope=friends`; `racerCount` per activity on `GET /races/activities`; `previousRank` on list rows. |
| W4 battles | `0050_v13_crew_battles.sql` | `squad_battles` + create/accept/decline + score on `GET /squads/:id`. |

## 5. Ordered task list

Each task runs on its own sub-branch, reviewed and merged into `redesign/v13` by the orchestrator.

| # | Branch | Owner | Files (main) | Depends |
|---|---|---|---|---|
| S1 | `redesign/s1-ci` | orchestrator | `.github/workflows/ci.yml`, `tool/ci/known_failing_tests.txt`, 7 test-file warning fixes | — |
| S2 | `redesign/s2-flag-shell` | Devin | `lib/core/config/v13.dart`, `lib/app/router.dart`, `lib/app/app.dart`, `lib/features/shell/presentation/main_shell.dart`, `lib/core/v13/widgets/v13_tab_bar.dart` | S3 tokens (rebased) |
| S3 | `redesign/s3-design-system` | Devin | `lib/core/v13/tokens.dart`, `lib/core/v13/motion.dart` (spring curve, press, haptics pref), `lib/core/v13/widgets/*` (`V13Card`, `V13Button` primary/secondary/ghost/danger, `V13Face` + `V13FaceStack` + silhouette, `V13Pill`/chips, `V13Segmented`, `V13Toggle`, `V13Stepper`, `V13Row`/divider list, `V13SectionHeader`, `V13Toast`, `V13Confetti`, `V13FloatingPlus`, `V13NumberPop`, `V13ProgressBar`, `V13Sheet`, `V13IconTile`, `V13HeatMap`, `V13MedalCircle`, `V13AsyncView` states, `V13ConfirmSheet`), `test/v13/design_system_test.dart` | — |
| W1 | `redesign/w1-worker-profile` | Devin | `server/worker/migrations/0048_*`, `src/routes/{profile,users,progression}.ts`, new `src/routes/mutes.ts`, tests, API_CONTRACT | — |
| W2 | `redesign/w2-worker-crews` | Devin | `0049_*`, `src/routes/squads.ts`, `crew.ts`, `reports.ts`, cron, tests | W1 merged (migration order) |
| W3 | `redesign/w3-worker-races` | Devin | `src/routes/races.ts`, `crew.ts`, new `leaderboard.ts`, tests | — |
| S4 | `redesign/s4-arena` | Devin | `lib/features/arena/presentation/v13/*` | S2, S3 |
| S5 | `redesign/s5-compete-races` | Devin | `lib/features/compete/presentation/v13/*`, `lib/features/races/presentation/v13/{composer,race_detail,submit_proof_sheet}.dart` | S3, W3 for open races / leaderboard / trending |
| S6 | `redesign/s6-crew` | Devin | `lib/features/social/presentation/v13/*`, `lib/features/squads/presentation/v13/*`, squads/crew data additions | S3, W2 |
| S7 | `redesign/s7-profile` | Devin | `lib/features/profile/presentation/v13/*` (profile, public profile, badges, settings, edit, my code + scan) | S3, W1 |
| S8 | `redesign/s8-activity-onboarding` | Devin | `lib/features/notifications/presentation/v13/*`, restyle of onboarding, auth **UI** and splash (logic files untouched) | S3 |
| S9 | `redesign/s9-cleanup` | Devin + orchestrator | delete old-shell-only screens/widgets (import-verified), remove flag | S4–S8 |
| S10 | `redesign/s10-qa` | orchestrator + Devin | full click-through: every button → real destination, every request → 4 states, screenshot tests | S9 |

S3, W1 and W3 start immediately in parallel. S2 starts once S3's tokens
land. S4–S8 run in parallel once S2 + S3 are merged, each in its own
worktree, and each falls back to existing data where its Worker stage
isn't merged yet: the element is hidden, never faked.

## 6. Quality gate per merge

`flutter analyze` (0 errors, no new warnings), `flutter test` (no new
failures vs `tool/ci/known_failing_tests.txt`), worker `npm test` green,
no hardcoded colors in `v13/` files (tokens only), one primary blue
action per screen, no `onPressed: () {}` / TODO handlers, every request
uses `V13AsyncView` or an equivalent loading/empty/error/retry. No
edits to no-touch files (checked with `git diff --name-only`).
