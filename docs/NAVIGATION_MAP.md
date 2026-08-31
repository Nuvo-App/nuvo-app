# Nuvo navigation map

The single reference for how the app is wired: every route, who navigates
where, which navigation verb to use, and the rules any future change (human or
AI) must follow. Keep this file current whenever a route or a navigation call
changes.

Router: `lib/app/router.dart` (GoRouter). Redirect guard:
`lib/features/auth/presentation/auth_gate.dart` (`RouterNotifier.redirect`).
Back-button helper: `safePopOrGo(context, fallback)` in
`lib/core/navigation/nuvo_navigation.dart`.

---

## 1. The core principle

**Every "open a race" tap in the entire app goes to one screen: `/race/:id`
(the race page / leaderboard).**

Verifying, logging progress, inviting crew, and settings are all *actions on
that screen*, reached from it — never a separate destination that a list tap
lands on. A user must never be surprised about where a race opens.

If you are adding a control that references a race, its tap target is
`/race/:id`. Do not deep-link a list/card tap straight to `/race/:id/proof`,
`/race/:id/settings`, etc.

---

## 2. Route table

| Path | Screen | Page transition | Params | Notes |
|---|---|---|---|---|
| `/splash` | `SplashScreen` | none | — | Entry. Restores session, then `go`es to `/arena` or `/welcome/intro`. |
| `/welcome/intro` | `WelcomeRaceBuilderScreen` | cupertino | — | Pre-auth race builder / demo. |
| `/welcome` | `WelcomeAuthScreen` | cupertino | — | Sign-in (email / Google / Apple). |
| `/auth/email` | `EmailStartScreen` | cupertino | — | |
| `/auth/verify` | `EmailVerifyScreen` | cupertino | `extra: String email` | On success sets auth state; router redirects. |
| `/onboarding/profile` | `OnboardingScreen` | cupertino | — | |
| `/onboarding/member-pass` | `OnboardingMemberPassScreen` | cupertino | — | |
| **ShellRoute** (`MainShell` + bottom nav) | | | | Tabs below. Switch with `context.go`. |
| `/arena` | `ArenaScreen` | none (tab) | — | Home. "Your next move". |
| `/pass` | `PassScreen` | none (tab) | — | Crew / member pass. |
| `/compete` | `CompeteScreen` | none (tab) | — | Start / join / your races. |
| `/move` | `MoveScreen` | none (tab) | — | "Verify" — ready / completed / recent. |
| `/profile` | `ProfileScreen` | none (tab) | — | Identity, history, settings. |
| `/races/new` | `RaceComposerScreen` | cupertino | `extra: RaceCreatePrefill?` | 5-step composer. On create → `go` to race/invite. |
| `/races/join` | `JoinRaceScreen` | cupertino | — | Invite-code entry. On join → `go` to race. |
| `/internal/teach-movement` | `TeachMovementScreen` | slide-up | `?fixture=ready` (debug) | Custom movement capture. |
| `/race/:id` | `RaceDetailScreen` | detail slide | `id` | **The race page / leaderboard.** Active vs completed layouts. |
| `/race/:id/settings` | `RaceSettingsScreen` | cupertino | `id` | "Edit race" (owner only). |
| `/race/:id/edit` | → redirect | — | `id` | **Legacy alias** → `/race/:id/settings`. Do not add a screen here. |
| `/race/:id/invite` | `InviteCrewScreen` | cupertino | `id` | |
| `/race/:id/proof` | `SubmitProofScreen` | slide-up | `id` | Camera pre-verify OR manual "Log progress". |
| `/race/:id/proof/ai-motion` | `AiMotionProofScreen` | slide-up | `id` | Live camera verification. |
| `/race/:id/board-moved` | `BoardMovedScreen` | cupertino | `extra: BoardMovedArgs` | Celebration / result. Reached by `pushReplacement`. Exits with `go('/race/:id')`. |
| `/race/:id/proofs/:proofId` | `ProofReviewScreen` | cupertino | `id`, `proofId` | Owner reviews a submitted proof. |
| `/proof/:id` | `ProofScreen` | none | `id` | Thin shim: immediately `go`es to `/race/:id/proof`. Deep-link/notification target only. |
| `/profile/edit` | `EditProfileScreen` | cupertino | — | |

---

## 3. Navigation graph (who links where)

```
splash ──► arena (restored)  |  welcome/intro (no session)

welcome/intro ──► welcome ──► auth/email ──► auth/verify ──► (router) ─┐
welcome ──► [Google/Apple] ──► (router) ──────────────────────────────┤
                                                                      ▼
                              onboarding/profile ──► onboarding/member-pass ──► arena
                                              (or straight to /compete if guideFirstRace)

┌──────────── bottom-nav tabs (context.go, never push) ────────────┐
│  arena   pass   compete   move   profile                          │
└──────────────────────────────────────────────────────────────────┘
   │        │        │        │        │
   │        │        │        │        └─► /profile/edit
   │        │        │        │        └─► /race/:id            (history rows)
   │        │        │        │        └─► /pass                (pass shortcut)
   │        │        │        │
   │        │        │        └─► /race/:id                     (up-next card, rows)
   │        │        │        └─► /race/:id/proof               (openVerification → then reloads)
   │        │        │        └─► /races/new
   │        │        │
   │        │        └─► /race/:id           ★ featured card + every row (was inconsistent — fixed)
   │        │        └─► /races/new  ·  /races/join
   │        │
   │        └─► (crew management — in-screen)
   │
   └─► /race/:id                             ("See race board" + board tap + quick action)
   └─► /races/new  ·  /races/join

/race/:id ─► /race/:id/proof ─► /race/:id/proof/ai-motion ─(pushReplacement)─► /race/:id/board-moved ─(go)─► /race/:id
/race/:id ─► /race/:id/settings          (owner "Edit race")
/race/:id ─► /race/:id/invite            (owner "Invite crew")
/race/:id ─► /race/:id/proofs/:proofId   (owner taps a move-log entry)
/race/:id ─► /arena                       ("Leave race" → go)

/races/new  ─(go on create)─► /race/:id/invite  or  /race/:id
/races/join ─(go on join)───► /race/:id
```

★ = the fix in this pass. Compete's featured card used to open `/race/:id/proof`
when the user had no progress yet; every other race tap opened `/race/:id`.
Now unified.

---

## 4. Which navigation verb

| Verb | When | Examples |
|---|---|---|
| `context.go(path)` | Switching **tabs**; landing after a flow **completes** and the flow's screens must leave the stack; resetting after auth. | tab switches in `MainShell`; `/races/new` → `/race/:id` after create; celebration → `/race/:id`; "Leave race" → `/arena`. |
| `context.push(path)` | Opening a **detail or sub-screen** the user will back out of to return to where they were. | list row → `/race/:id`; `/race/:id` → `/race/:id/settings`; `/race/:id` → `/race/:id/proof`. |
| `context.pushReplacement(path)` | Replacing the **current** screen in a linear step flow where returning to the replaced screen makes no sense. | `ai-motion` → `board-moved` (you can't "go back" to a finished recording). |
| `safePopOrGo(context, fallback)` | **Every manually-placed back button.** Pops if there's a stack, else `go`es to a sensible home. Never call `context.pop()` bare from a screen reachable as a deep link. | all `NuvoBackButton` handlers. |
| `context.pop()` | Only inside **dialogs / bottom sheets** (`showDialog`, `showModalBottomSheet`), never a route back button. | `edit_profile_screen` photo sheet; confirm dialogs. |

**Rule:** after a create/join/complete flow, use `go` (or `pushReplacement`) so
the user cannot swipe back into a stale draft, a finished recording, or a
celebration. After opening a detail screen to *look at*, use `push`.

---

## 5. Canonical flows

**Create a race:** `/compete` or `/arena` → `push /races/new` → composer steps
→ on create `go /race/:id/invite` (if `invite_code`) or `go /race/:id`. Invite
screen → `safePopOrGo(/race/:id)`.

**Join a race:** `push /races/join` → enter code → `go /race/:id`.

**Submit camera proof:** `/race/:id` (pinned "Verify now") → `push
/race/:id/proof` → (if a demo exists, pre-verify; else auto) `push
/race/:id/proof/ai-motion` → record → `pushReplacement /race/:id/board-moved`
→ "View race" `go /race/:id`.

**Log manual proof (non-camera goal):** `/race/:id` (pinned "Log progress") →
`push /race/:id/proof` → `_ManualLogCard` + "Log progress" →
`pushReplacement /race/:id/board-moved` → `go /race/:id`.

**Edit a race:** `/race/:id` → owner "Edit race" → `push /race/:id/settings` →
Save → `go /race/:id`. (Archive / Cancel / Delete → `go /race/:id` or
`go /arena`.)

**Review a proof (owner):** `/race/:id` move log row → `push
/race/:id/proofs/:proofId` → decide → `go /race/:id`.

---

## 6. Rules for future changes (READ BEFORE ADDING NAVIGATION)

1. **A race opens at `/race/:id`. Always.** A list/card/row tap that represents
   a race navigates to `/race/:id` and nothing else. Actions (verify, invite,
   settings) are reached *from* that screen.
2. **One route per screen.** If two paths should show the same screen, one is a
   `redirect`, not a second `pageBuilder` (see `/race/:id/edit`).
3. **Tabs use `go`.** Never `push` a shell tab — it stacks tabs on tabs.
4. **Flows end with `go`.** Creating/joining/finishing must not leave the flow's
   screens back-swipeable.
5. **Back buttons use `safePopOrGo`.** Screens are deep-link reachable; a bare
   `pop()` crashes when there's nothing to pop.
6. **`extra:` is not durable.** A route that only works with `extra` (e.g.
   `/race/:id/board-moved` needs `BoardMovedArgs`, `/auth/verify` needs the
   email) must have a safe fallback when `extra` is null (both do — keep it).
   Prefer path/query params for anything that must survive a cold deep link.
7. **Protected routes.** Anything under `/arena|/pass|/compete|/move|/profile|
   /race/|/races/|/proof/|/onboarding/` is gated by `auth_gate.dart`. New
   protected areas must be added to `_isProtected` there.
8. **Post-auth routing is provider-agnostic.** `auth_gate.dart` decides the
   landing screen from `onboardingComplete` + `guideFirstRace` only — never
   from which route sign-in started on. Email, Google and Apple must always
   land in the same place. Do not reintroduce a `loc.startsWith('/auth/')`
   branch.
9. **Don't invent transitions.** All pushed routes use one of the existing
   `_authPage` / `_detailPage` / `_cameraPage` / `_tabPage` builders in
   `router.dart`.
10. **Update this file** in the same change that adds/moves/removes a route or
    changes a navigation verb.

---

## 7. Known remaining issues (backlog)

- `race_settings_screen.dart` uses `context.go('/race/:id')` for its "Back to
  race" button and error-retry (lines ~246, ~391) where `safePopOrGo` would be
  lighter. Harmless (same destination) but inconsistent.
- `/proof/:id` (`ProofScreen`) is a redirect-in-disguise — it renders a screen
  that immediately `go`es. Could be a real `redirect:` in the router instead.
- `create_race_screen.dart` (`CreateRaceScreen`) still exists and is
  camera-only; the live composer is `RaceComposerScreen`. `CreateRaceScreen`
  appears unused as a route — verify and delete, or wire it as the non-camera
  path. (`RaceCreatePrefill` is defined in that file and *is* used — keep it or
  move it.)
- Arena boards come from `ArenaSnapshot` (`ArenaBoard.id`), Compete/Move from
  `raceControllerProvider` (`Race.id`). Both feed `/race/:id`. If an
  `ArenaBoard.id` ever doesn't correspond to a fetchable `Race`,
  `RaceDetailScreen` shows its error state — acceptable, but the arena API
  contract should guarantee the ids match.
