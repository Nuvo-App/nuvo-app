# Visual & Interaction Redesign — Complete

_Last updated: 2026-07-01_

Source of truth: `nuvo_humanized.html` prototype (Manrope type system, navy/blue
color tokens, custom hand-drawn icon set, Race Ring leaderboard, motion spec).
This was a phased, incrementally-verified redesign — each phase below was its
own scoped change, confirmed with `flutter analyze` (0 issues throughout) and
on-device navigation on a physical iPhone before moving to the next.

---

## What changed, by file

### Design-system foundation
- `lib/core/theme/app_colors.dart` — `NuvoColors` token values replaced with
  the prototype's palette (navy `#0F1E33`, blue `#4F8EF7`/`#2F6FE0`, sky
  `#EDF4FE`, offwhite `#F7F6F3`, gold/silver/bronze rank tiers, amber streak
  color, flat muted avatar palette). Token *names* were kept stable so every
  existing call site picked up the new palette without further edits.
- `lib/core/theme/app_text_styles.dart` + `app_theme.dart` — one font family
  (Manrope via `google_fonts`, already a dependency) everywhere, replacing the
  prior Space Grotesk + Plus Jakarta Sans pairing. Added `AppTextStyles.number()`
  for tabular-figure stat/score text.
- `lib/core/widgets/nuvo_icons.dart` (new) — Nuvo's 17-icon custom set
  (flag, crown, fire, trend-up, check, checkcircle, camera, hand, users, user,
  plus, lock, bolt, bell, close, arrow, back), rendered via `CustomPainter`
  with an SVG path-data parser that reads the prototype's `<defs>` `d` strings
  verbatim — no `flutter_svg` dependency needed (pubspec is no-touch per
  `AGENTS.md`). Covered by `test/nuvo_icons_test.dart`.
- `lib/core/widgets/race_ring.dart` (new) — the signature Arena visual: an
  animated circular progress arc with racer avatar markers plotted at their
  real progress angle (`angle = -90 + progress*360`, clockwise from 12
  o'clock), a pulsing ring on the current user's marker. Angle math is a pure
  function (`ringPointForProgress`) covered by `test/race_ring_test.dart`
  (10 tests: cardinal points, clamping, distance-from-center, and a literal
  check against the prototype's formula).
- `lib/core/widgets/animations.dart` — `AnimatedProgressBar` now supports a
  delayed fill-from-0 start and a continuous shimmer sweep at rest (via the
  already-present `shimmer` package).
- `lib/core/widgets/nuvo_shared_components.dart` — `NuvoRaceLane` (used by
  Compete, Race Detail, and Profile) gained the same delayed-fill + shimmer
  treatment, so all three screens' progress bars animate consistently.
- `lib/core/widgets/pressable_scale.dart` — press-release curve tuned
  (`Curves.easeOutCubic`, 200ms). An earlier `easeOutBack` attempt overshoots
  past the target scale before settling, which — applied to every pressable
  element app-wide, including a bottom nav tapped constantly — read as a
  visible wobble on-device. Reverted after on-device testing.
- `lib/core/widgets/nuvo_avatar.dart` — added `nuvoAvatarColorFor(id)`, a
  deterministic flat-color picker from the muted avatar palette (never a
  gradient, never generic navy-for-everyone).

### Screens
- `lib/features/arena/presentation/arena_screen.dart` — hero card is now the
  blue gradient moment (was navy) with a real blinking live-dot, a bell that
  opens a notifications sheet wired to real `ArenaActivity` data (previously
  a permanently-static "no updates yet" — this also resolves a pre-existing
  known issue from `BASELINE_BEFORE_PRODUCT_SKELETON.md`: "dead notifications
  bell"). Added the Race Ring to the focus board card, a crew activity feed
  section (real `ArenaActivity`, previously fetched but never rendered
  anywhere), and gold/silver/bronze rank coloring + a crown on #1 in the
  leaderboard rows.
- `lib/features/compete/presentation/compete_screen.dart` — flat navy icon
  square (was a coral/sunshine gradient, which conflicted with the "gradients
  only on hero/pass/profile" rule), staggered card entrance, custom icons.
- `lib/features/race_detail/presentation/race_detail_screen.dart` — added the
  Duolingo-style vertical checkpoint path (new; didn't exist before).
  Checkpoints are derived at 25/50/75/100% of the race's real target/progress
  — no invented milestone data.
- `lib/features/move/presentation/move_screen.dart` — flat navy header icon,
  staggered race rows, removed a third duplicate progress-bar implementation
  (`_MiniRaceLane`) in favor of the shared `NuvoRaceLane`.
- `lib/features/pass/presentation/pass_screen.dart` — member pass card now has
  a `dark: true` variant (solid navy, matching the prototype) used only here
  — the onboarding screen's existing light pass card is untouched. Added a
  real crew-comparison track: cross-references the user's active races against
  crew membership to find the closest real race/crew-member pairing and plots
  both progress percentages on a track with a finish flag. Section is omitted
  entirely when no such real overlap exists.
- `lib/features/profile/presentation/profile_screen.dart` — flat navy header
  (was a 3-stop gradient), count-up animation on the four real stats.
- `lib/features/races/presentation/board_moved_screen.dart` — this was
  already the "after proof submission" screen with real
  rank/peoplePassed/leader data; restyled to the prototype's full-screen navy
  celebration (checkmark badge, old-rank → new-rank row, "moved up N spots"
  copy, white CTA).
- `lib/features/races/presentation/submit_proof_screen.dart` — now threads the
  actual submitted proof's `rankBefore`/`rankAfter`/`peoplePassed` and the
  race's real chase context through to the celebration screen (previously
  these fields were left null on the manual-submit path even though the UI
  supported them).
- `lib/core/widgets/bottom_nav.dart` — reworked to match the prototype: navy
  pill background on the active tab (was a light-blue tint), a subtle
  `AnimatedScale` icon pop when a tab becomes selected, and a breathing pulse
  ring behind the center FAB (previously a static gradient square) — the ring
  now runs for 4 breaths then settles rather than pulsing forever (see below).
  An earlier version stacked a second, separate hand-rolled bounce
  AnimationController on top of `PressableScale`'s own press feedback; on a
  frequently-tapped element like nav items, two overlapping scale animations
  read as jitter on-device. Simplified to one.
- `lib/features/shell/presentation/main_shell.dart` / `lib/app/router.dart` —
  tab switches are an **instant cut** (`NoTransitionPage`), same as before
  this redesign. I tried two animated approaches and both regressed on a
  physical device:
  1. Wrapping the shell's live `child` in a widget-level `AnimatedSwitcher`
     caused a **Duplicate GlobalKey** crash on every tab switch, since
     go_router's shell content carries a key tied to its Navigator that can't
     be mounted twice simultaneously (which is inherent to how
     `AnimatedSwitcher` crossfades — old and new children are both mounted
     during the transition).
  2. Moving the transition to the route level via `CustomTransitionPage`
     (the pattern this app already uses for auth/onboarding routes, so it's
     key-safe) fixed the crash, but this app's `ShellRoute` doesn't preserve
     each tab's widget state across switches — every tab switch already does
     a full screen rebuild (real data providers, entrance animations, etc.),
     and animating over that exposed the rebuild cost as visible lag.
  Net: this `ShellRoute` (not a `StatefulShellRoute.indexedStack`) rebuilding
  every tab from scratch is pre-existing architecture, not introduced here.
  An instant cut sidesteps it entirely, and matches how native iOS tab bars
  actually behave (no crossfade) — reverting to it was the correct answer,
  not a compromise.

### On-device performance pass
Three animations that ran indefinitely once mounted were made finite instead,
since a screen with several running at once (shimmer on every progress bar +
Race Ring pulse + FAB breathing ring) is a real, compounding cost, not just a
debug-mode artifact:
- `AnimatedProgressBar` / `NuvoRaceLane` shimmer: now `loop: 3` (a few sweeps
  after fill, then rests) instead of forever.
- Race Ring's current-user pulse ring: `count: 3` instead of forever.
- Bottom nav FAB breathing ring: `count: 4` instead of forever.

The Arena hero's blinking live-dot was left as a genuine indefinite repeat —
it's a cheap opacity tween on a 6x6 dot (not a shader effect like shimmer),
and it represents an actual ongoing "live" status rather than a one-time
entrance flourish, so continuous is the correct semantic here.

Separately: on-device testing over a debug build with wireless debugging
produced inconsistent lag/jank reports across iterations even as changes only
*reduced* animation load — which pointed at the testing conditions rather
than the code. Confirmed by testing a `flutter run --release` build (no
JIT/debug overhead, no wireless debug channel): performance was reported as
fine. If perceived sluggishness resurfaces, retest with a release build
before assuming it's a code regression — debug mode on iOS is genuinely much
slower than what ships.

---

## Data-model gaps flagged (per "never fake activity" — omitted, not mocked)

These prototype elements have **no real backing field today**. Per your
direction, the components were **omitted entirely** rather than rendered with
invented numbers:

| Prototype element | Missing field | Where it would live |
|---|---|---|
| "PR" ribbon on a leaderboard row | Personal-best flag on `RaceParticipant` | `lib/features/races/data/race_models.dart` |
| 7-dot streak week calendar | Streak day-history on `AuthUser` | `lib/features/auth/data/auth_models.dart` |
| Weekly recap bar chart | Per-day verified-activity counts | new endpoint or derived from `RaceProof.createdAt` history |
| Achievement badges (locked/unlocked) | Badge/achievement unlock state | new model, no current equivalent |
| Per-row trend triangle (up/down) on Arena's mini-leaderboard | No per-participant rank-delta at snapshot time (only exists per-proof via `rankBefore`/`rankAfter`) | `ArenaMiniLeaderboardRow` |

One thing that *did* have real data already and is now used: `RaceProof`
already carries `rankBefore`/`rankAfter`/`peoplePassed` — the rank-up
celebration and the Arena rank pill use these directly.

## Known pre-existing issue (not introduced by this work)

`test/widget_test.dart`'s smoke test fails with "A Timer is still pending
even after the widget tree was disposed." Confirmed via `git stash` that this
fails identically on the unmodified code before this redesign — an existing
timer-disposal issue (likely the 5s arena/race-detail auto-refresh timers),
not something introduced here.

## Verification performed

- `flutter analyze`: 0 issues after every phase and at completion.
- `flutter test`: 14/15 pass (the 1 failure is the pre-existing issue above).
- New tests: `test/nuvo_icons_test.dart` (icon parser + all 17 icons render),
  `test/race_ring_test.dart` (10 cases on the Race Ring's angle math).
- Ran on a physical iPhone (not simulator — Google ML Kit's pose-detection pod
  lacks an arm64 simulator slice, a pre-existing, unrelated environment
  constraint) and navigated the real app to confirm each screen after its
  phase; auth restore, arena snapshot fetch, and real board data all loaded
  successfully with no runtime exceptions in the device log.
