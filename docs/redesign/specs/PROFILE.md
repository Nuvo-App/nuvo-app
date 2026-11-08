# PROFILE.md — v13 spec audit: Profile tab, public profiles, Badges, Settings, Edit profile

Phase A documentation. Read-only audit of the current implementation against
`docs/redesign/PROTOTYPE_V13_SPEC.md` (v13). Nothing here is a build plan;
every element is marked `KEEP`, `REPLACE`, `DELETE`, or `NEW`, with its real
code location and its real data source (exact Worker endpoint, or `MISSING`
plus an additive proposal — next migration number: `0048`).

Sources audited: `lib/features/profile/**`, `lib/features/crew/**` (public
profile + social API), `lib/features/notifications/**`,
`lib/features/pass/**`, `lib/features/social/presentation/my_nuvo_screen.dart`,
`lib/app/router.dart`, `lib/core/widgets/bottom_nav.dart`,
`lib/core/demo/presentation_demo.dart`, `lib/core/theme/nuvo_theme_mode.dart`,
`lib/core/utils/photo_service.dart`, `lib/core/config/legal_links.dart`,
`lib/features/auth/data/auth_api.dart` (read-only, no-touch),
`server/worker/src/routes/{users,profile,progression,crew,reports,notifications,auth,devices}.ts`,
`server/worker/src/domain/{notifications,progression,profileRecord}.ts`,
`server/worker/src/lib/privacy.ts`, `server/worker/migrations/*`.

Legend: **file:line** = verified in this audit. "unverified" = evidence is
partial; the reason is stated.

---

## 1. Surface map (current state)

| Surface | Route | Screen | Entry |
|---|---|---|---|
| Own Profile tab | `/profile` (tab 3) | `ProfileScreen` — `lib/features/profile/presentation/profile_screen.dart:68` | `nuvoDestinations[3]` — `lib/core/widgets/bottom_nav.dart:50-55` |
| Edit profile | `/profile/edit` | `EditProfileScreen` — `lib/features/profile/presentation/edit_profile_screen.dart` | `lib/app/router.dart:414-415`; pushed from avatar edit dock `profile_screen.dart:371-372` and Settings row `settings_screen.dart:144-146` |
| Own badges | `/profile/badges` | `BadgesScreen` — `lib/features/profile/presentation/badges_screen.dart:24` | `lib/app/router.dart:418-419`; pushed from `_AchievementsRow` `profile_screen.dart:1140` |
| Settings | `/settings` | `SettingsScreen` — `lib/features/profile/presentation/settings_screen.dart` (`part` of `profile_screen.dart:40`) | `lib/app/router.dart:203-204`; pushed from Profile "Your Nuvo" row `profile_screen.dart:245-249` |
| Notification prefs | `/settings/notifications` | `NotificationPrefsScreen` — `lib/features/notifications/presentation/notification_prefs_screen.dart:30` | `lib/app/router.dart:206-209`; Profile row `profile_screen.dart:237-243` |
| Public profile | `/u/:id` | `PublicProfileScreen` — `lib/features/crew/presentation/public_profile_screen.dart:39` | `lib/app/router.dart:145-150` |
| Public badges | `/u/:id/badges` | `PublicBadgesScreen` — `lib/features/crew/presentation/public_badges_screen.dart:22` | `lib/app/router.dart:152-162` |
| My Nuvo (member code/QR) | `/my-nuvo` | `MyNuvoScreen` — `lib/features/social/presentation/my_nuvo_screen.dart:31` | `lib/app/router.dart:193-195`; Profile "My code" row `profile_screen.dart:231-235` |
| QR scan | `/scan` | `QrScanScreen` | `lib/app/router.dart:141-144` |
| Friends tab (member pass, friends, feed, crews entry) | `/pass` (tab 2, label "Friends") | `PassScreen` — `lib/features/pass/presentation/pass_screen.dart:50` | `nuvoDestinations[2]` — `bottom_nav.dart:44-49` |

Data providers used by these surfaces: `authControllerProvider` (identity,
photo upload, username check, motion consent, logout, delete),
`progressionControllerProvider` / `progressionApiProvider` (`GET /progression`,
`GET /progression/badges`, `PUT /progression/featured`,
`POST /progression/level-seen` — `lib/features/profile/data/progression_api.dart:120-164`),
`profileActivityProvider` (`GET /profile/activity` —
`lib/features/profile/application/activity_controller.dart:7-49`,
`activity_api.dart:9-39`), `crewRepositoryProvider`/`crewControllerProvider`
(`lib/features/crew/data/crew_api.dart`, `application/crew_controller.dart`),
`memberPassProvider` (`GET /pass/me` — `member_pass_provider.dart`),
`inviteRepositoryProvider` (mint `crew_connect` invites — `my_nuvo_screen.dart:67-70`),
`notificationPrefsApiProvider` (`notification_prefs_screen.dart:20-22`),
`raceControllerProvider` (shared active races on public profile —
`public_profile_screen.dart:632-637`).

---

## 2. v13 "Profile tab (your profile)" — element audit

v13: "Shared Instagram-like layout: @username at the top. Your own profile
also has a QR button and a real gear (settings) button. Then photo, name,
level as plain text (no blue box), bio, counts (Races, Wins, Friends), and a
favorite movement chip." + "Edit profile" and "Share profile" buttons;
"activity map, achievements (3 featured badges), and race history with medals."

| v13 element | Current code | Verdict | Data source |
|---|---|---|---|
| @username at top | `_IdentityCard` shows name + `@username` — `profile_screen.dart:311-431` (handle at 412-422) | KEEP (restyle: handle first/top per v13) | `authControllerProvider` → `GET /auth/me` (`auth_api.dart:217`) |
| QR button top-right | "My code" row inside "Your Nuvo" group — `profile_screen.dart:231-235` → `/my-nuvo` | REPLACE (move affordance to header; keep `/my-nuvo` screen) | `POST /invites` (`crew_connect`) + `GET /pass/me` |
| Gear (settings) button top-right | "Settings" row — `profile_screen.dart:245-249` → `/settings` | REPLACE (same move) | local navigation |
| Photo (navy-outlined circle) | `NuvoAvatar` in navy circle + hard shadow — `profile_screen.dart:338-360`; edit dock overlay 365-397 | KEEP (avatar already outlined; falls back to colored initials — v13 wants "neutral silhouette" fallback: REPLACE fallback art only) | `user.profilePhotoUrl` |
| Name | `displayName` — `profile_screen.dart:406-411` | KEEP | `GET /auth/me` |
| Level as plain text | Level shown inside progression plane (level number + bar), `_LevelTrack`/`_NextUnlockArtifact` — `profile_screen.dart:438+`; no blue box anywhere (plane is ice-blue card) | REPLACE (demote to plain text; v13 moves XP ring to Arena avatar — Arena scope, not this doc) | `GET /progression` (`progression_api.dart:120-140`) |
| Bio | none — no bio field in `AuthUser` (`auth_models.dart:1-90`), `profiles` table, or any Worker route. `people.bio` exists only as a legacy tombstone column nulled on delete (`server/worker/src/routes/auth.ts:254`) | NEW | MISSING → `POST /profile` gains `bio` (≤80 chars); `GET /profile/me`, `GET /users/:id` return it. Migration `0048`: `ALTER TABLE profiles ADD COLUMN bio TEXT` |
| Counts: Races / Wins / Friends | `_StatsStrip` — `profile_screen.dart:1200-1240` shows `RACING` = **active** count (1219-1223), `WINS` (1225-1229), `WIN RATE` (1231-1236) | REPLACE (labels + semantics: v13 wants total Races, Wins, Friends — no "Friends" count exists anywhere) | `GET /progression` → `record` (`profileRecord.ts:16-20` active/finished/wins/winRatePercent). Friends count: MISSING → propose additive `friends` key on `/progression` `record`, or client derives from already-cached `GET /crew` list |
| Favorite movement chip | none | NEW | MISSING → `profiles.favorite_movement_key` (migration `0048`), editable in Edit profile, returned by `GET /profile/me` + `GET /users/:id`. Keys reuse the existing race-movement catalog used by `RaceCreatePrefill` (e.g. `pushups`) |
| "Edit profile" button | Avatar edit dock → `/profile/edit` (`profile_screen.dart:365-397`); no standalone button | KEEP (v13 wants explicit button next to Share; reskin) | — |
| "Share profile" button | Exists on `/my-nuvo` as "Share my Nuvo" (`my_nuvo_screen.dart:119-129` → `share_plus`) sharing the minted invite URL; not on the profile itself | REPLACE (surface it on profile; reuse the same crew_connect invite link) | `POST /invites` + `share_plus` (already in `pubspec.yaml`) |
| Activity map | `ActivityHeatmapSection` → `ActivityHeatmap` — `profile_screen.dart:212`, `widgets/activity_heatmap.dart:37-60`. 20-week grid of verified proof counts, hidden on failure | KEEP (adjust to v13's 18 weeks + legend) | `GET /profile/activity?days&tz` (`activity_api.dart:9-39`) |
| Achievements (3 featured) | `_AchievementsRow` — `profile_screen.dart:1123-1194`: "Achievements · N of T earned · see all" + up to 3 featured badges → `/profile/badges` | KEEP | `GET /progression` (`featuredBadges`, `achievementsEarned/Total`) |
| Race history with medals | none on Profile (v13 Compete spec also lists a "Trophy shelf" — current app has no finished-race list surface; unverified whether any history list exists elsewhere) | NEW | Server has the data (finished races + winners power `readProfileRecord` — `profileRecord.ts:50-76`). MISSING as an API for a list → propose additive `GET /races?status=finished&me=1&limit=` or extend `/progression` with `recentFinishes[]`; decide which surface owns it (likely Compete trophy shelf, not Profile — flag for product) |
| Edit dock on avatar | `profile_screen.dart:365-397` | KEEP (or fold into Edit profile button) | — |

---

## 3. v13 "public profiles" — element audit

Current: `PublicProfileScreen` (`/u/:id`) is already close to v13 — hero,
progression plane, featured/earned achievements, "Races with you", CTA by
connection state, report/block overflow. The v13 additions that are missing:
bio, mutual friends, mute, share/copy link, the "vs you" stat rows, friendship
badges, and their activity map.

| v13 element | Current code | Verdict | Data source |
|---|---|---|---|
| Header: photo, name, active status | `_hero` — `public_profile_screen.dart:451-557`: navy-outlined avatar (459-476), name, `@username` (488-498), `LEVEL n` (499-510), member id (516-522), presence dot + label for connected friends only (523-554 via `crewPresenceFor/crewPresenceLabel`, `lastActiveAt`) | KEEP | `GET /users/:id` (`crew_api.dart:285-291` → `users.ts:123-203`) |
| Bio | none | NEW | MISSING → same `bio` field as §2 |
| Counts | `_PubStatsStrip` — `public_profile_screen.dart:930-958`: `RACING` = **finished** count (943), `WINS` (945), `WIN RATE` (947, computed client-side) | KEEP (note: label semantics differ from own profile — public "RACING" = finished, own "RACING" = active; align under v13) | `GET /users/:id` → `raceStats {races, wins}` |
| Mutual friends' faces | none. `mutualCount` exists **only** in search results (`crew_api.dart:271-283`, `CrewSearchResult.mutualCount`) | NEW | MISSING → additive `mutual: {count, preview:[{id,displayName,profilePhotoUrl}…≤5]}` on `GET /users/:id` |
| "Challenge [Name]" button → New race with them invited | Exists as **"Race {first}"** — `public_profile_screen.dart:680-690` → `/races/new` with `RaceCreatePrefill.pushups.copyWith(withUser: …)` | KEEP (wording already resolved — see §8 conflicts) | local navigation |
| "Friends" button with action sheet (Mute, Remove friend + confirm) | Friends state renders a static "Friends" badge (674-678) + tertiary "Remove friend" (692-696) with `showNuvoConfirmDialog` (`_remove`, 151-184) | REPLACE (badge → button opening sheet; Remove keeps its confirm; Mute is NEW) | Remove: `DELETE /crew/:userId` (`crew_api.dart:358-366` → `crew.ts:456`). Mute: MISSING → proposed `POST /mutes/users/:id` (§9) |
| 3-dot button: Share profile, Copy profile link, Mute, Report, Block | `_overflow` sheet — `public_profile_screen.dart:312-351`: **Report** + **Block** + Community Guidelines link only | REPLACE (add Share/Copy/Mute) | Report ✓ `POST /reports/users/:id` (`crew_api.dart:323-324` → `reports.ts:35`). Block ✓ `POST /reports/blocks/:id` (`crew_api.dart:332-333` → `reports.ts:89`), confirm dialog + exits page (233-253). Share profile → NEW (can reuse own-pass link only for self; for others needs target's slug — MISSING → additive `passSlug`/`shareUrl` on `GET /users/:id`). Copy link → same. Mute → MISSING (§9) |
| "[Name] vs you" scoreboard — "STATS WON a–b", rows Level / Wins / Win rate / Best streak / Proofs this week | Partial: `racesWithYou {total, viewerWins, targetWins, recent[]}` powers "RACES WITH YOU" block (561-629) — head-to-head **record**, not the stat grid. Level exists both sides (`GET /progression` + `GET /users/:id`); Wins/Win rate derivable both sides. **Best streak: MISSING** (no day-streak stat exists anywhere). **Proofs this week: MISSING** (derivable from `move_logs` — same source as the heatmap; not exposed) | NEW | Proposed additive `versus` object on `GET /users/:id`: `{bestStreakDays:{you,them}, proofsThisWeek:{you,them}}`; viewer-side values could also ship on `GET /progression` as additive keys so self-profile stays the source of truth |
| Friendship badges: First race / Rivals (10 races) / Cheer squad (20 cheers) / Best friends (30 days) / Streak buddies (both log 7 days) | none | NEW | MISSING → proposed additive `friendship` object on `GET /users/:id`: `{connectedSince, badges:[{key,unlocked,progress,threshold}]}`. Server can derive all five: races together = `racesWithYou.total` (already computed); cheers = `activity_reactions` pair count (table `0031_social_reactions.sql:12`); 30 days = `crew_connections.created_at` (exists, not exposed); streak buddies needs the same new day-streak stat as "Best streak" |
| Their activity map | none — `GET /profile/activity` is self-only (`profile.ts:85+`, uses auth user id) | NEW | MISSING → proposed additive `GET /users/:id/activity?days&tz` — same shape as `/profile/activity`; `403` when blocked; honors the new `activity_map_shared` pref (§5) |
| Their achievements (locked ones dashed) | `earnedAchievements` list + featured resolve → `_PublicAchievements` (1043-1128) → `/u/:id/badges` (`PublicBadgesScreen`, earned-only grid) | KEEP for earned. CONFLICT on locked: current contract is deliberately earned-only (`public_badges_screen.dart:19-21`, `crew_api.dart:96-98`) | `GET /users/:id` (`earnedAchievements`, `achievementsTotal`). To show locked tiles: additive `lockedAchievements:[{key,name,iconKey,category,threshold}]` (no progress values — keeps the self-only-progress rule) |
| Races with you | `_racesWithYou` (561-629): total + `You a · first b` + recent rows → `/race/:id` (613-621). Plus `_sharedRaces` (631-665): up to 3 **active** shared races filtered client-side from `raceControllerProvider` cache | KEEP | `GET /users/:id` → `racesWithYou`; active list from `GET /races` cache |
| Non-friend: "Add friend" → "Requested"; "Message" explains friends-only | "Add friend" (710-715) → `POST /crew/add` (`crew_api.dart:293-303`, `ConnectOutcome` active/pending); "Request sent" badge for `pendingOutgoing` (699-703); "Accept friend request" for `pendingIncoming` (704-709) → `POST /crew/requests/:id/accept` | KEEP for add/accept. **Message: DELETE** — no messaging exists; spec's explainer-only button is a dead-end control (see §8) | `POST /crew/add`, `POST /crew/requests/:userId/accept` (`crew.ts:418,433`) |
| Blocking leaves the page and hides them everywhere | `_block` exits via `_exit()` (210-216); server returns `403` on `GET /users/:id` when blocked in either direction (`users.ts`); UI shows "Not available" state (379-391). Unblock API exists (`DELETE /reports/blocks/:id` — `crew_api.dart:335-336`, `reports.ts:106`) but **no UI surface** lists blocked users | KEEP (+NEW "Blocked accounts" settings row → `GET /reports/blocks`, `reports.ts:115`) | `POST/DELETE /reports/blocks/:id`, `GET /reports/blocks` |

---

## 4. v13 "Badges page" — element audit

v13: "A progress ring, the badge closest to unlocking with a 'Find a race'
button, your 3 profile slots, filter chips (All, Earned, Locked, Racing,
Winning, Streaks), and a grid. Tapping a badge opens a detail sheet with a big
tile, description, status, rarity, and 'Show on profile' or 'Remove from
profile' (max 3)."

| v13 element | Current code | Verdict | Data source |
|---|---|---|---|
| Progress ring | none — header shows earned/total text (`badges_screen.dart`) | NEW | `GET /progression/badges` or `GET /progression` |
| Badge closest to unlocking + "Find a race" | `NextUpCard` widget exists — `widgets/next_up_card.dart:15-60` ("NEXT UP" + "Race toward it" → `/compete`). Usage inside `BadgesScreen` unverified (widget confirmed; mounting site not re-read) | KEEP (verify mount; restyle + label "Find a race" → keep `/compete` destination) | `GET /progression` `nextAchievement`/`nextUnlock` fields |
| "Your 3 profile slots" | Featured badges with server-owned `featuredSlots` count — `badges_screen.dart:53-54`. Slots are unlocked by level (capability ladder: slot 2 at Lv2, slot 3 at Lv7 — `0042_achievements.sql:137,142`), so today the cap is 1→3 by level, not always 3 | KEEP (v13's "max 3" is already the ceiling; keep server-driven slot count — a dedicated "3 slots" visual is NEW chrome only) | `GET /progression` (`featuredSlots`, `featuredBadges`) |
| Filter chips | `nuvoAchievementTabs` — `nuvo_badges.dart:278-288`: All, Racing, Winning, Creating, Performance, Social, Variety, Motion, Special (`special` = proof+category+level, 290). Selected `_tab` filters the grid (`badges_screen.dart:35-83`) | REPLACE list per v13: All / Earned / Locked / Racing / Winning map directly; **"Streaks" chip: NEW category** — no streak achievements exist in the catalog (see §8 conflicts). "Earned"/"Locked" become state filters, not categories | `GET /progression/badges` returns full catalog + `unlocked`/`progressValue` (`progression_api.dart:143-149`) |
| Grid | `NuvoBadgeGrid` — `nuvo_badges.dart:295-421`: 3-across tiles, earned accent by family (`nuvoBadgeAccent` 107-115), featured check, locked progress bar | KEEP | same |
| Detail sheet: big tile, description, status | `NuvoAchievementDetailSheet` — `nuvo_badges.dart:426-553`: 72px badge, name, description, earned date or `progressValue/threshold` bar + "One to go." | KEEP | same |
| Rarity in detail sheet | Rarity exists in data (`metadata_json` `{"rarity":"common|uncommon|milestone|legendary"}` — `0042_achievements.sql` passim; `NuvoBadge.isMilestone` reads `metadata['rarity']`) but is only used for accent color — **no rarity label is rendered** | NEW (label only; data already ships) | `GET /progression/badges` `metadata.rarity` |
| "Show on profile" / "Remove from profile" (max 3) | Sheet button "Feature on Profile"/"Unfeature" (`nuvo_badges.dart:518-546`) → slot-gated toggle `badges_screen.dart:54,105` → `PUT /progression/featured` (`progression_api.dart:151-157` → `progression.ts:67`, server validates in `setFeaturedBadges`) | KEEP (rename to v13 copy) | `PUT /progression/featured {unlockIds[]}` |

Backend facts: catalog + unlock state = `GET /progression/badges`
(`routes/progression.ts:60`); progression bundle = `GET /progression`
(`:30`); featured write = `PUT /progression/featured` (`:67`, delegates
validation to `setFeaturedBadges`, `:81`); also `GET /progression/race/:raceId`
(`:89`) and `POST /progression/level-seen` (`:97`). Tables:
`unlock_definitions`, `user_unlocks`, `user_featured_badges`,
`user_progression`, `xp_events` (`0039_progression.sql:12-69`).

---

## 5. v13 "Settings" — element audit

v13: "An account card at the top, then grouped sections: Notifications
(passes, invites, results, cheers, reminders). Privacy (private profile, show
my activity map, who can challenge me). App (appearance, haptics, sounds, help
improve AI Motion, presentation mode). Support. Account (sign out, delete
account with confirm)."

Current `SettingsScreen` sections (`settings_screen.dart`): **App** (102) —
"Replay the guide" (109-110), debug-only "Rive Calibration" (120-121);
**Privacy & Data** (131) — `_MotionConsentRow`, `_PresentationModeRow`
(1355); **Account** (138) — Edit profile (144-146), Sign out (150-152),
Delete account (157-159), Delete account on the web (163-165); **Legal**
(173) — Privacy/Terms/Guidelines (179-190).

| v13 element | Current code | Verdict | Data source |
|---|---|---|---|
| Account card at top | none (Account is a row group) | NEW chrome only (identity already in `authControllerProvider`) | `GET /auth/me` |
| Notifications → passes | no such category | NEW mapping or new category — see note below | `GET/PATCH /notifications/preferences` |
| → invites | `race_invite`, `crew_request` prefs exist | KEEP (merge under one v13 "Invites" row if desired — client-side grouping) | server: `notifications.ts:138-173`; categories `domain/notifications.ts:15-28`; client groups `notification_prefs.dart:31-45` |
| → results | `race_completed`, `proof_accepted`, `proof_rejected` | KEEP | same |
| → cheers | `reaction` | KEEP | same |
| → reminders | only scheduled pre-start reminders exist (`domain/notificationJobs.ts:28-109`, fires `race_starting`) — no generic "reminders" category | KEEP `race_starting` as the row; a broad reminders category is NEW backend work (flag, don't promise) | same |
| Privacy → private profile | **CONFLICT — see §8. `privateProfile` is a dead legacy field** (`docs/API_CONTRACT.md`, `lib/privacy.ts:1-5`) | DELETE | — |
| → show my activity map | none | NEW | MISSING → `profiles.activity_map_shared` (migration `0048`), enforced inside proposed `GET /users/:id/activity` (own map unaffected) |
| → who can challenge me | none | NEW + rename ("challenge" → "who can race me" / "race invites", §8) | MISSING → `profiles.race_invites_from` `'everyone'|'friends'` (migration `0048`), checked in `POST /invites` / race-invite fan-out |
| Also add (not in v13): Blocked accounts | API exists, no UI | NEW | `GET /reports/blocks` (`reports.ts:115`), `DELETE /reports/blocks/:id` |
| App → appearance | `_AppearanceRow` — `profile_screen.dart:1406-1452` (lives on Profile's "Your Nuvo" group, not Settings): light/dark `NuvoToggle` | KEEP (move row into Settings > App per v13) | local pref — `NuvoThemeModeStore`/`nuvoThemeModeProvider`, file `nuvo_theme_mode.json` (`nuvo_theme_mode.dart:14-90`) |
| → haptics | `NuvoHaptics` + `HapticFeedback` calls exist (e.g. `bottom_nav.dart:172`, `level_up_dialog.dart:22`) but **no preference gate** | NEW | local pref — same JSON-file pattern via `path_provider` (no `shared_preferences` in pubspec) |
| → sounds | **no sound system exists at all** | NEW — recommend deferring (asset + engine + pref); if shipped, same local-pref pattern | none |
| → help improve AI Motion | `_MotionConsentRow` — `profile_screen.dart:1458-1578` under Settings > Privacy & Data: server-backed toggle + 13+ attestation flow on 403 (1498-1518) | KEEP | `GET /motion/consent`, `POST /motion/consent` (`auth_api.dart:260-275`); `POST /auth/age-attestation` (`:258`) |
| → presentation mode | `_PresentationModeRow` (1355) + `settings_screen.dart:26-47` (`setPresentationModeEnabled`, cache clear) — visible only for `canTogglePresentationMode` account (`presentation_demo.dart:32-33`); `isDemo` accounts are always-on (116-126) | KEEP | local pref — `PresentationModePreferences`, file `nuvo_presentation_mode.json` (`presentation_demo.dart:37-114`) |
| Support | none (Legal links exist) | NEW | external URL — `url_launcher` (already used by `legal_links.dart`); needs a support URL/mailto — flag for product |
| Account → sign out | `settings_screen.dart:150-152` → `authControllerProvider.logout()` | KEEP | `POST /auth/logout` (`auth_api.dart:213-214`) + local token clear |
| → delete account with confirm | `settings_screen.dart:157-159` → `_confirmDeleteAccount` → "Delete account?" dialog (53) → `deleteAccount()`; web link 163-165 → `LegalLinks.deleteAccountUri` | KEEP | `DELETE /auth/account` (`auth_api.dart:250-251`; worker cascade + tombstone `auth.ts:216-289`) |

Server-side notification preference facts (verified): `GET
/notifications/preferences` merges stored rows over `CATEGORY_DEFAULTS`
(`notifications.ts:138-156`); `PATCH /notifications/preferences
{category,inApp?,push?}` upserts `notification_preferences`
(`notifications.ts:160-173`, table `0014_social_platform.sql:87`). Twelve
categories (`domain/notifications.ts:15-28`): race_invite, race_joined,
race_starting, race_completed, passed_on_leaderboard, proof_accepted,
proof_rejected, proof_disputed, crew_request, crew_request_accepted,
crew_connected, reaction. Push delivery honors the `push` flag
(`domain/notifications.ts:168-279`); device tokens via `POST /devices`,
`DELETE /devices/:token` (`devices.ts:11,47`).

---

## 6. v13 "Edit profile" — element audit

v13: "A Cancel and Done top bar, a photo change, boxed fields (name, username
with an availability check, and bio with an 80-character counter), and
favorite movement chips. Cancel discards unsaved changes."

| v13 element | Current code | Verdict | Data source |
|---|---|---|---|
| Cancel + Done top bar | `EditProfileScreen` (`edit_profile_screen.dart:25+`) has a save flow; Cancel/Done chrome unverified in detail — current submit calls `_save` → `saveProfile` (249) | KEEP (restyle chrome to Cancel/Done; semantics match) | `POST /profile` (`auth_api.dart:283-289` → `profile.ts`) |
| Photo change | Photo sheet: Choose/Take photo/Remove/Cancel — `edit_profile_screen.dart:58-129`; pick+crop via `photoPickerProvider` (`photo_service.dart:30`, `ImageCropper` :76); upload `:161`; remove `:189` | KEEP | `POST /profile/photo/upload-url` → `PUT /profile/photo/upload?token=` (unsigned; `profile.ts:19-61`, R2 `PROFILE_PHOTOS` + `media_objects`); serve `GET /profile/photo/object/*` (`:63-76`); remove via `POST /profile` (avatar cleared) |
| Name field | `_nameController` seeded from `fullName` (45) | KEEP | `POST /profile` |
| Username + availability check | `_usernameController` (46); client rules — ≥3 chars (204-206), no spaces (211-213), ≤20 (215-217), `^[a-z0-9_]+$` (221-223); server check only when changed (236-243), sets `_usernameError` on taken | KEEP | `POST /profile/username/check` (`auth_api.dart:347-349` → `profile.ts:330-355`; 409 on update conflict) |
| Bio + 80-char counter | none | NEW | MISSING → `bio` on `POST /profile` + `GET /profile/me`; `ALTER TABLE profiles ADD COLUMN bio TEXT` (`0048`); enforce 80 in client + server |
| Favorite movement chips | none | NEW | MISSING → `favorite_movement_key` on profiles (`0048`); chip options reuse the existing movement preset keys (`RaceCreatePrefill` presets) — flag: needs a defined key list, product decision |

---

## 7. Required checks — verdicts

| Check | Verdict | Evidence |
|---|---|---|
| `GET /users/:id` shape | Returns `{ok, user:{id, displayName, username, memberId, initials, profilePhotoUrl, isPrivate:false (legacy), connectionStatus, level, levelProgress, achievementsEarned, achievementsTotal, featuredAchievements, earnedAchievements, raceStats:{races,wins}, racesWithYou:{total,viewerWins,targetWins,recent[{raceId,title,winnerUserId}]}, lastActiveAt (connected only)}}`. When `canSeeIdentity` fails the identity fields fall back to `@username`/`'Private profile'`, null photo, and null stats (the privacy gate still exists server-side even though no user can set it) | `users.ts:124-202`; parsed `crew_api.dart:107-135`. Absent: bio, favoriteMovement, friendsCount, mutuals, connectedSince, versus extras, friendship badges, activity, passSlug, muted |
| Counts: races / wins / friends | races+wins ✓ (`raceStats`); **friends count MISSING** | above; own stats via `GET /progression` `record` (`profileRecord.ts`) |
| Level | ✓ both own (`/progression`) and public (`level`, `levelProgress` 0..1 only — absolute XP stays private by design) | `progression.ts:30`, `users.ts` |
| Favorite movement | MISSING | no field anywhere |
| Mutual friends | partial — `mutualCount` in `GET /users/search` only | `crew_api.dart:271-283` |
| Head-to-head vs me | partial — `racesWithYou{total,viewerWins,targetWins,recent}`; scoreboard rows Level/Wins/Win rate derivable; **Best streak MISSING; Proofs this week MISSING** | `users.ts`, `crew_api.dart:140-163` |
| Friendship badges (all five) | MISSING | derivable — see §3 |
| Activity map for another user | MISSING | `GET /profile/activity` is self-only (`profile.ts:85+`) |
| Races with you | ✓ | `racesWithYou` + client-side active filter `public_profile_screen.dart:631-665` |
| Mute | MISSING — nothing anywhere | propose `user_mutes` table + `/mutes/*` (§9) |
| Block | ✓ + unblock + list (no UI for list) | `POST/DELETE /reports/blocks/:id`, `GET /reports/blocks` (`reports.ts:89-115`, `crew_api.dart:332-336`) |
| Report | ✓ user/race/content + 500-char reason sheet | `POST /reports/{users,races,content}/:id` (`reports.ts:35-88`, `crew_api.dart:323-330`, sheet `public_profile_screen.dart:255-310`) |
| Remove friend | ✓ with confirm | `DELETE /crew/:userId` (`crew_api.dart:358-366` → `crew.ts:456`) |
| Username availability | ✓ | `POST /profile/username/check` |
| Bio length limit | MISSING | no bio; v13 80-char counter → enforce server-side too |
| Photo upload endpoint | ✓ signed-URL flow | `POST /profile/photo/upload-url` → `PUT /profile/photo/upload?token=` → `GET /profile/photo/object/*` |
| Badge catalog: rarity + featured (max 3) | ✓ rarity in `metadata_json`; featured via `user_featured_badges`; slot cap is server-owned (1→3 by level via `badge_slot` unlocks, ceiling 3) | `0042_achievements.sql`, `progression.ts:66-85` |
| Notification toggles server-side | ✓ 12 categories × {inApp, push} | `GET/PATCH /notifications/preferences` (`notifications.ts:138-173`) |
| Delete account | ✓ | `DELETE /auth/account`; full cascade `auth.ts:216-289` |
| Sign out | ✓ | `POST /auth/logout` |
| Haptics / sounds / presentation-mode local prefs | presentation ✓ file-backed; haptics MISSING as pref (calls exist, ungated); sounds MISSING entirely | `presentation_demo.dart:37-114`; `nuvo_motion.dart` `NuvoHaptics`; no sound code |

---

## 8. Conflicts vs AGENTS.md / product model — resolutions

1. **"Private profile" settings toggle (v13 Settings > Privacy).**
   `AGENTS.md`: "Private profiles do not exist: everyone is visible, blocking
   is the only privacy control." Backend agrees: `lib/privacy.ts:1-5` — no
   private profile, `canViewFullProfile` only checks blocks; `isPrivate:false`
   / `privateProfile` are legacy keys ignored by `POST /profile`.
   **Resolution: DELETE the toggle.** Replace Privacy with rows that are real:
   "Show my activity map" (new pref), "Who can race me" (new pref, see #2),
   "Blocked accounts" (existing `GET /reports/blocks`), and keep "Help improve
   Nuvo Motion" (existing server consent).

2. **"Challenge [Name]" (v13 public profile CTA).** Product language forbids
   "challenge"; existing code already says **"Race {first}"**
   (`public_profile_screen.dart:681`). **Resolution: keep "Race [Name]"** —
   the shipped wording already resolved this; fix the spec, not the app.

3. **"Who can challenge me" (v13 Settings > Privacy).** Same word.
   **Resolution: rename to "Who can race me"** (values: Everyone / Friends
   only) — a genuinely useful new server pref (`race_invites_from`, `0048`).

4. **"Message" button on non-friend profiles.** No messaging exists; spec
   says the button only "explains you have to be friends" — a dead-end
   control against the no-dead-buttons rule. **Resolution: DELETE.** "Add
   friend"/"Requested"/"Accept" already communicate the model; friend-only
   surfaces (activity map, friendship badges) can show their own gated copy.

5. **"Streaks" badge filter + "[N] day streak" + "Best streak" + "Streak
   buddies".** No day-streak stat exists (only a `streak` race *format*,
   `races.ts:188,198`). **Resolution:** either drop all streak elements from
   v13, or add a server-derived day-streak (computed from `move_logs` verified
   dates — same source as `GET /profile/activity`; cache inside the existing
   `user_progression.stats_json` column so no new table is needed). Needed by
   four v13 elements, so recommend building it once. Flag for product.

6. **"Crew" tab label.** v13 tab bar says "Crew"; product language reserves
   CREW for named groups and calls the person-link tab **Friends** (current
   `bottom_nav.dart:44-49` label "Friends"). v13's Crew page also merges
   friends + crews + requests + feed, which crosses screen-ownership lines
   (Friends = social graph, Crews = group management). **Resolution:** keep
   the "Friends" label; treat the v13 "Crew" page as a merge proposal that
   needs its own spec + product sign-off. Flag, don't implement silently.

7. **"Locked ones dashed" on public profiles.** Current contract is
   deliberately earned-only — locked progress is self-only by design
   (`public_badges_screen.dart:19-21`, `crew_api.dart:96-98`, `privacy.ts`).
   **Resolution:** keep earned-only (recommended), or add a `lockedAchievements`
   array carrying only `{key,name,iconKey,category,threshold}` — never
   progress — so v13's dashed tiles render without exposing how close a
   friend is to anything. Needs product sign-off either way.

8. **"Light mode only for this release" vs existing dark mode.** App ships a
   persisted light/dark pref (`nuvo_theme_mode.dart`) toggled on Profile.
   **Resolution:** build v13 light-first as specified; don't delete the dark
   pref — existing palettes already map to `themeColors`. Keep the
   "Appearance" row (moved into Settings > App per v13).

9. **Featured slot count.** v13 hardcodes "max 3"; server grants slots 2 and
   3 at levels 2 and 7 (capability ladder). **Resolution:** keep server-driven
   `featuredSlots` — v13's cap of 3 is the existing ceiling; the UI should
   render the unlocked slots, not a fixed 3.

10. **Counts label.** Own profile shows `RACING`=active; public shows
    `RACING`=finished; v13 says "Races". **Resolution:** align on finished
    races for both (matches `racesWithYou` semantics) and confirm in the
    visual pass.

---

## 9. Proposed additive API + migration `0048` (no contract changes)

Schema — `server/worker/migrations/0048_v13_profile.sql` (do NOT create in
this phase; all additive/idempotent):

```sql
ALTER TABLE profiles ADD COLUMN bio TEXT;
ALTER TABLE profiles ADD COLUMN favorite_movement_key TEXT;
ALTER TABLE profiles ADD COLUMN activity_map_shared INTEGER NOT NULL DEFAULT 1;
ALTER TABLE profiles ADD COLUMN race_invites_from TEXT NOT NULL DEFAULT 'everyone';

CREATE TABLE IF NOT EXISTS user_mutes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK (target_type IN ('user','crew')),
  target_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_user_mutes_user ON user_mutes(user_id);
```

Endpoints (all additive keys/routes; existing payloads untouched):

- `POST /profile` — accept `bio` (≤80), `favoriteMovementKey`,
  `activityMapShared`, `raceInvitesFrom`; `GET /profile/me` returns them.
- `GET /users/:id` — add optional keys: `bio`, `favoriteMovementKey`,
  `friendsCount`, `connectedSince`, `passSlug` (for Copy/Share profile link),
  `muted`, `mutual:{count,preview[]}`, `versus:{proofsThisWeek:{you,them},
  bestStreakDays:{you,them}}`, `friendship:{connectedSince,badges:[{key,
  unlocked,progress,threshold}]}`, optional `lockedAchievements` (decision §8.7).
- `GET /users/:id/activity?days&tz` — same shape as `GET /profile/activity`;
  `403` if blocked either way; empty map when `activity_map_shared=0`.
- `POST /mutes/users/:id`, `DELETE /mutes/users/:id`,
  `POST /mutes/crews/:id`, `DELETE /mutes/crews/:id`, `GET /mutes` —
  feed/notification fan-out suppresses muted actors (mutes are invisible to
  the target; no notification emitted).
- `GET /progression` `record` — add `friends` (active `crew_connections`
  count), `proofsThisWeek`, `bestStreakDays` (additive keys) so own counts and
  the "vs you" rows share one source.
- Friendship badges: computed display objects, **not** `unlock_definitions`
  rows — they are per-pair, not global achievements. No catalog changes.
- "Passes"/"reminders" notification rows: map to existing categories
  (`crew_connected`, `race_starting`) rather than new categories; a real
  member-pass-scan or generic-reminder category is new fan-out work — flag.

## 10. Current features v13 does not show — adapt / retain / drop

- **Member pass ("My code", member id, pass link, QR, scan):** v13 keeps the
  QR concept via the profile-header QR button + "My Nuvo code" screen. KEEP
  `/my-nuvo` + `/scan`; surface the entry as the header button.
- **Progression plane (level track, next-unlock artifact, XP sources, level
  route):** v13 demotes to plain-text level + Arena XP ring. REPLACE chrome;
  KEEP `GET /progression` and the level-up moment (`level_up_dialog.dart:16`
  — a reward moment, on-brand with v13 confetti rules).
- **"Your Nuvo" action group (My code / Notifications / Appearance /
  Settings):** v13 splits these to header buttons + Settings sections.
  REPLACE rows with the new layout; keep every destination.
- **Notification prefs reach path:** currently Profile row →
  `/settings/notifications`; v13 puts it under Settings > Notifications.
  KEEP screen + API.
- **`_StatsStrip` (active/wins/win rate):** REPLACE with v13
  Races/Wins/Friends.
- **`ActivityHeatmap`:** KEEP, parameterize to 18 weeks.
- **Settings rows "Replay the guide" + "Rive Calibration" (debug):** KEEP —
  group under App/dev; not in v13 but they're dev tooling, not product
  features.
- **"Delete account on the web" + Legal links:** v13 shows only a Support
  section. KEEP legal rows under Support/Legal — App Store requirements.
- **`isPrivate`/`privateProfile` legacy fields:** keep ignored for
  back-compat; never surface.
- **ETag conditional GETs (`GET /crew`, `GET /notifications`), offline
  cache fallbacks (`profileActivityProvider`, `memberPassProvider`):**
  invisible to v13 — KEEP.
- **Presentation/demo fixtures (`presentationDemoProfile`):** public profile
  and badges already resolve demo people locally — KEEP for the protected
  demo; extend fixtures when new fields land.

## 11. No-touch & dependency notes

No-touch files that later phases must consume but never edit:
`auth_api.dart` (hosts `saveProfile`, `checkUsername`,
`uploadProfilePhoto`, `removeProfilePhoto`, `deleteAccount`, `logout`,
`getMotionConsent`, `setMotionConsent`, `attestAge` — all called from
profile/settings code), `auth_repository.dart`, `auth_controller.dart`,
`auth_gate.dart`, `secure_token_store.dart`, `ai_motion_proof_screen.dart`,
`motion_validators.dart`, `pose_detector_service.dart`,
`camera_image_converter.dart`, iOS native files, `server/worker/**` (backend
changes need explicit approval), plus treat `race_api.dart`,
`race_repository.dart`, `race_controller.dart` as do-not-casually-touch.

Packages already in `pubspec.yaml` covering v13 needs: `qr_flutter` (QR),
`share_plus` (Share profile), `image_picker` + `image_cropper` (photo),
`google_fonts` (Manrope), `animations` + `flutter_animate` + `rive`
(springs/rewards), `cached_network_image`, `url_launcher` (support/legal).
**`confetti` is NOT in pubspec** — v13 confetti rewards will need either a
dependency decision (pubspec is a no-touch area — flag) or reuse of the
existing Rive/animate celebration language. `mobile_scanner` is intentionally
absent (ML Kit version pin conflict — documented in pubspec comments; QR
scanning reuses the camera pipeline — don't add it).

## 12. Unverified items

- Whether `NextUpCard` is actually mounted inside `BadgesScreen` (widget
  confirmed at `widgets/next_up_card.dart:15`; the screen body beyond the
  feature/scroll sections wasn't fully re-read).
- Whether any finished-race/trophy list exists elsewhere in the app for
  "race history with medals" — none found in profile feature files.
- Exact `SettingsScreen` visual chrome (Cancel/Done equivalent on Edit
  profile) — the save path is verified, the top bar composition wasn't.
- `GET /profile/me` exact response fields in `profile.ts` (contract doc
  lists `fullName, username, profilePhotoUrl, avatarUrl, privateProfile,
  onboardingComplete`); bio/favorite fields confirmed absent from models.
- Push registration provider wiring (`pushServiceProvider` → `POST /devices`)
  — endpoints verified in `devices.ts`, client call sites not re-read.
