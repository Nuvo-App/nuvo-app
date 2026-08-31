# Screen reference — every UI surface, current state

One row/section per screen: **route · file · the question it answers · the ONE
primary action · states it must render · shared widgets · data source.**

This describes the tree **as it is now** (after the overhaul in commits
`dcbaae1 … 890c67b`). For the historical defect list and severities see
[`../FULL_APP_AUDIT_2026-08.md`](../FULL_APP_AUDIT_2026-08.md) §4. For routing
verbs see [`../NAVIGATION_MAP.md`](../NAVIGATION_MAP.md).

Legend for **Q**: `what is this? / am I winning? / what do I tap?`

---

## Quick table

| Route | Screen | File | Primary action |
|---|---|---|---|
| `/splash` | Splash | `splash/presentation/splash_screen.dart` | none (restores session → routes); offline → retry |
| `/welcome/intro` | Pre-auth race builder | `auth/.../welcome_race_builder_screen.dart` | "Build a race" (demo) |
| `/welcome` | Sign in | `auth/.../welcome_auth_screen.dart` | "Continue with Email" |
| `/auth/email` | Email entry | `auth/.../email_start_screen.dart` | "Send code" |
| `/auth/verify` | Code entry | `auth/.../email_verify_screen.dart` | "Verify" |
| `/onboarding/profile` | Name + username | `onboarding/.../onboarding_screen.dart` | "Continue" |
| `/onboarding/member-pass` | Pass intro | `onboarding/.../member_pass_screen.dart` | "Continue" |
| `/arena` | Arena (home tab) | `arena/.../arena_screen_fixed.dart` | "Submit proof" on the next-move board |
| `/pass` | Crew (tab) | `pass/.../pass_screen.dart` | "Share pass" / add crew |
| `/compete` | Compete (tab) | `compete/.../compete_screen_fixed.dart` | featured race card CTA (or "Create a race" when empty) |
| `/move` | Verify (tab) | `move/.../move_screen.dart` | "Start verification" on the up-next card |
| `/profile` | Profile (tab) | `profile/.../profile_screen.dart` | none dominant — history + settings |
| `/races/new` | Race composer | `races/.../race_composer_screen.dart` | "Next" / "Create race" |
| `/races/join` | Join by code | `races/.../join_race_screen.dart` | "Join race" |
| `/race/:id` | **Race detail / leaderboard** | `race_detail/.../race_detail_screen.dart` | pinned "Verify progress" / "Log progress" |
| `/race/:id/settings` | Edit race (owner) | `races/.../race_settings_screen.dart` | "Save changes" |
| `/race/:id/edit` | → redirect to `/settings` | `app/router.dart` | — |
| `/race/:id/invite` | Invite crew | `races/.../invite_crew_screen.dart` | "Share invite" |
| `/race/:id/proof` | Submit proof | `races/.../submit_proof_screen.dart` | "Begin" (camera) / "Log progress" (manual) |
| `/race/:id/proof/ai-motion` | Live camera verify | `races/.../ai_motion_proof_screen{_io,_web}.dart` | implicit (the count) |
| `/race/:id/board-moved` | Celebration / result | `races/.../board_moved_screen.dart` | "View race" |
| `/race/:id/proofs/:proofId` | Proof review (owner) | `races/.../proof_review_screen.dart` | accept / needs-review / reject |
| `/proof/:id` | Deep-link shim | `proof/.../proof_screen.dart` | (immediately `go`es to `/race/:id/proof`) |
| `/profile/edit` | Edit profile | `profile/.../edit_profile_screen.dart` | "Save" |
| `/internal/teach-movement` | Teach a movement (debug) | `races/.../custom_pose/teach_movement_screen.dart` | capture flow |

---

## Tabs (the shell)

`MainShell` (`features/shell/presentation/main_shell.dart`) hosts the five tabs
with `NuvoBottomNav`. Switch tabs with `context.go`, never `push`. The shell does
**not** preserve per-tab scroll/state across switches (pre-existing) — each tab
rebuilds; that's why tab transitions are instant (`_tabPage` = `NoTransitionPage`).

---

## Arena — `/arena`

- **Q:** yes / yes / yes. **Owns:** "what needs my attention now?" — nothing else.
- **Primary:** "Submit proof" on the top next-move board (opens `/race/:id`).
  Quick actions below: one-row `NuvoPrimaryButton` (Submit proof, flex 4) + two
  icon-only `NuvoOutlineButton` (New race, Join — flex 2 each).
- **States:** loading (skeleton) / error (`NuvoErrorState`) / empty
  (`NuvoEmptyState`, centred) / loaded / `preview: true` (used by
  `welcome_race_builder`).
- **Leaderboard:** `NuvoPodium` + `_OutlinedSheet` for ranks 4+, built from
  `serverRankedParticipants(raceById[board.id])` — the **same** data + widget as
  Race Detail (they must match).
- **Data:** `arenaControllerProvider` (`ArenaSnapshot` → `ArenaBoard`s) +
  `raceControllerProvider` (`raceById` map for the authoritative standings).
- **Watch out:** the custom `Stack`+nav overlay in `main_shell.dart` branches on
  `isArena`; header greeting is time-aware.

## Crew / Pass — `/pass`

- **Q:** partial — mixes the member pass (identity) with crew management.
- **Primary:** "Share pass" / search + add crew.
- **Sections:** member pass hero (`MemberPassCard`), "Find people" search,
  "Closest race" card (colour-coded green/red/amber by ahead/behind/tied),
  "Your crew" list. Section labels have a coloured accent tick.
- **States:** loading / error (`NuvoErrorState`) / empty crew (`_EmptyNote`).
- **Data:** `authControllerProvider` (pass) + local `_crew` from
  `raceRepository.getCrew()`; `_closestCrewRace` derived from
  `raceControllerProvider`.

## Compete — `/compete`

- **Q:** yes / yes / yes. **Owns:** start or join a race — nothing else.
- **Primary:** the featured "continue competing" card
  (`NuvoFeaturedRaceCard`, opens `/race/:id`). Header has "Start" + "Join";
  empty state's CTA is "Create a race".
- **Sections:** compact header · featured card · capped active list
  (`NuvoRaceRow`, cap 3, "See all") · `NuvoWaitingCrewSummary` ·
  `NuvoFinishedSummary` · Quick starts (horizontal chips).
- **States:** `_CompeteSkeleton` (shimmer, keyed `compete-skeleton`) /
  `NuvoErrorState` / `NuvoEmptyState` ("No races yet") / loaded / first-run guide
  coach-mark.
- **Self-heals:** `initState` calls `loadRaces(force:false)` when cold.
- **Data:** `raceControllerProvider` (all races, camera + manual — no filter).

## Verify / Move — `/move`

- **Q:** yes / yes / yes. **Primary:** "Start verification" on the up-next card.
- **Segmented control:** Ready / Completed / Recent — tabs coloured blue / green
  / amber.
- **States:** `NuvoEmptyState` ("Nothing to verify yet") global + per-segment
  (`compact` empty state) / loaded.
- **Data:** `raceControllerProvider` (all races, no camera filter). Recent proofs
  use `proof_status.dart` presentation.

## Profile — `/profile`

- **Q:** yes / partial / yes. **Owns:** identity, member pass, race history,
  settings.
- **Header stats:** Active / Finished / Moves / Avg — coloured
  blue / green / amber / gold.
- **Sections:** avatar + name, stat row, member pass shortcut, race history rows
  (→ `/race/:id`), settings list, sign-out.
- **Data:** `authControllerProvider` + `raceControllerProvider` (history).

## Race Detail — `/race/:id` (the important one)

- **Q:** yes / yes / yes. **Owns:** one race's leaderboard room.
- **Primary:** pinned bottom bar — "Verify progress" (camera) or "Log progress"
  (manual), key `FirstRaceGuideKeys.racePrimary`.
- **Active layout:** `_LiveRaceHeader` (title + inline `subtitle · racers` muted
  line + circular back/settings) · `NuvoPodium` (flat) · `_LeaderboardGroup`
  (`_OutlinedSheet` + flat compact rows, ranks 4+) · `_YourProgressCard` (focal,
  outlined; accent green when leading/done else blue) · `_MoveLogGroup`
  (`_OutlinedSheet`, flat rows — no cards-in-cards) · pinned `_VerifyBar`.
- **Completed layout:** `_RaceSummaryCard` + `_FinalStandingsGroup`.
- **Owner menu:** single "Edit race" → `/race/:id/settings`; "Invite crew";
  "Leave race" → `go('/arena')`.
- **States:** loading / error (bad id → error state) / active / completed / board
  empty (`NuvoEmptyState`, `compact`).
- **Data:** `raceControllerProvider` → the `Race` for `:id`; ranks via
  `serverRankedParticipants` / `positionalRank` / `rankForUser`.

## Race Composer — `/races/new`

- **5 steps:** name → activity → goal → racers → review. Per-step "Next", final
  "Create race" → `context.go('/race/:id/invite')` or `/race/:id`.
- **Activity step:** Movement (camera) vs Custom goal toggle (`_GoalKindToggle`);
  custom collects name + unit (`RaceGoalKind.manual` on the draft).
- **Data:** `_composerDraftProvider` (autoDispose `RaceDraft`);
  `createRaceForComposerDraft` → `raceController.createRace` /
  `createCustomRace`.

## Submit Proof — `/race/:id/proof`

- **Camera race:** pre-verify screen (movement demo) → "Begin" →
  `push('/race/:id/proof/ai-motion')`.
- **Manual race:** `_ManualLogCard` (value + note) + bottom bar "Log progress" →
  `submitProof(proofType: 'manual')` →
  `pushReplacement('/race/:id/board-moved', extra: BoardMovedArgs(...))`.
- **Data:** `raceControllerProvider`.

## AI Motion Proof — `/race/:id/proof/ai-motion`

- **Platform split:** `_io` (real camera + ML Kit) / `_web` (stub). Router
  imports `ai_motion_proof_screen.dart` which conditionally exports.
- **NO-TOUCH** for UI tasks — see `AGENTS.md` and `07-…md` §11.
- On completion both submit paths →
  `pushReplacement('/race/:id/board-moved', extra: BoardMovedArgs(..., status))`.

## Celebration / Board Moved — `/race/:id/board-moved`

- **Verified:** fully green view — `_CheckMedallion`, `_RankReveal` (count-up),
  `_Burst` confetti, second haptic tick. **Primary:** "View race" →
  `go('/race/:id')`.
- **Pending:** amber "under review". **Not verified:** calm light view.
- **No `args`:** renders a neutral state — **never a fake green success**.
- Reached only by `pushReplacement`; exits only with `go`.

## Proof Review — `/race/:id/proofs/:proofId`

- Owner reviews one submitted proof: accept / needs-review / reject. Status
  colours from `proof_status.dart`.

## Invite Crew / Join Race

- Invite: share sheet + copyable code, `/race/:id/invite`.
- Join: code field → `joinRaceByCode` → `go('/race/:id')`.

## Onboarding / Auth screens

- All use `_authPage` (Cupertino) transitions. Post-auth landing is decided
  **only** by `auth_gate.dart` from `onboardingComplete` + `guideFirstRace` —
  identical for email / Google / Apple (pitfall B2).
- `welcome_auth_screen`: Apple / Google / Email on one `_ProviderButton` shell
  (same height/border/shadow/font). Apple flow is present but needs server
  config to complete (pitfall B3).
