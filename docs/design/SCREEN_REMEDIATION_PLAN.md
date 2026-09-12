# Screen-by-screen remediation plan — Nuvo App Design Guide

Planning document only — **no implementation in this doc.** Companion to
[`DESIGN_GUIDE_AUDIT_2026-09.md`](DESIGN_GUIDE_AUDIT_2026-09.md) (what's
wrong, with evidence) and
[`DESIGN_SYSTEM_GOVERNANCE.md`](DESIGN_SYSTEM_GOVERNANCE.md) (how we keep
new screens from drifting again). This doc turns the audit into one row per
screen so nothing gets skipped and work can be picked up in any order without
losing track of what's left.

Signals per screen come from four greps run against `lib/features` on
2026-09-11: raw `Color(0x...)` literals outside the theme, `Colors.white`/
`Colors.black` presence, raw Material buttons (`ElevatedButton`/`TextButton`/
`OutlinedButton`/`FilledButton`), `.animate()` presence, and raw
`BorderRadius.circular(N)` count. "Clean" means the grep found nothing for
that screen — not that the screen has been manually reviewed end-to-end.

Batch numbers indicate suggested execution order (highest emotional-impact /
highest-traffic screens first), not priority ranking within a batch — screens
in the same batch can be done in any order or split across people.

---

## Legend

- 🎨 = off-palette / raw color literal present
- ⚪ = pure white/black used as a primary surface fill (not just text/scrim)
- 🔲 = raw Material button bypassing `NuvoButton` family
- 🎬 = zero `.animate()` usage
- 📐 = raw `BorderRadius.circular()` count (token drift signal, not inherently wrong)

---

## Batch 1 — Reward & first-impression moments (highest leverage)

These are the screens the guide's "Overall Emotion" section is explicitly
about — the reward moment and the first 30 seconds of the app.

| Screen | Signals | What to plan |
|---|---|---|
| [`board_moved_screen.dart`](../../lib/features/races/presentation/board_moved_screen.dart) | ⚪🔲📐2 | Celebration CTA is a raw `FilledButton` — swap to `NuvoSuccessButton`. Already has confetti + `.animate()`; audit whether the "not verified" state undersells the guide's "rewarding" mandate too (calm ≠ punished). |
| [`splash_screen.dart`](../../lib/features/splash/presentation/splash_screen.dart) | 🎨📐1 | Off-palette blue-family gradient (`#618DDE`/`#6E9FF0`/`#79A8FF`/`#C5D9FA`/`#3F83FF`). First frame the user ever sees. Plan: extract into a shared ambient-glow component (see Batch 2) built from palette tokens only. |
| [`welcome_auth_screen.dart`](../../lib/features/auth/presentation/welcome_auth_screen.dart) | 🎨⚪📐3 | Third-party brand colors (Google "G") are a legitimate exception — plan should explicitly carve those out so nobody "fixes" them. Everything else on the screen should be plain palette. |
| [`welcome_race_builder_screen.dart`](../../lib/features/auth/presentation/welcome_race_builder_screen.dart) | 🎨⚪📐8 | Duplicates the same off-palette gradient as splash — this is the strongest case for a shared component instead of two hand-copies drifting further apart. |
| [`onboarding_screen.dart`](../../lib/features/onboarding/presentation/onboarding_screen.dart) | ⚪📐2, has `.animate()` | Mostly fine — spot-check the `Colors.white`/`black` sites are text/icon-on-fill (legitimate) and not a raw surface fill. |
| [`first_use_guide.dart`](../../lib/features/onboarding/presentation/first_use_guide.dart) | 🔲📐2 | Raw `TextButton` for guide dismissal → `NuvoTertiaryButton` (2D, low emphasis is correct here). |

---

## Batch 2 — Shared components (fix once, inherited everywhere)

Not screens — but the highest-leverage items in the whole plan, because every
screen below inherits the fix for free.

| Component | Plan |
|---|---|
| `NuvoAmbientGlow` (new) | Extract the splash/welcome-builder gradient glow into one widget parameterized by `NuvoColors.blue` at varying alpha stops. Kills the off-palette blue-family drift in two files at once and stops a third copy ever being hand-rolled. |
| `NuvoLoadingIndicator` (new) | Brand-colored, subtly animated replacement for bare `CircularProgressIndicator()`. ~30 call sites app-wide; swap is mechanical once the component exists. Directly serves the guide's "no part of the app that doesn't feel responsive... even simple loading screens should feel thought out." |
| `NuvoConfirmDialog` (new, or a documented pattern) | Standardize the "Cancel (2D) / Confirm-destructive (3D Danger)" dialog pair used by profile, edit-profile, and race-settings today with raw `TextButton` pairs. One helper instead of three hand-rolled dialogs. |
| `nuvo_button.dart` — Primary/Secondary outline color (Phase 7 from the audit) | **Needs your call, not a plan step**: keep navy outline (current "ink edge" identity) vs. switch to blue-shadow to literally match the guide's per-role example (Success/Danger already do this). Flag for a decision before Batch 5 touches these buttons, since every 3D button on every screen inherits whichever answer is chosen. |

---

## Batch 3 — Raw-button sweep (mechanical, screen-isolated, low risk)

Every remaining file with a raw Material button, one row each so each can be
landed independently:

| Screen | Line(s) | Plan |
|---|---|---|
| [`profile_screen.dart`](../../lib/features/profile/presentation/profile_screen.dart) | 63, 67 | Confirm-dialog pair → `NuvoConfirmDialog` (Batch 2) once it exists, else `NuvoTertiaryButton` + `NuvoDangerButton` directly. |
| [`edit_profile_screen.dart`](../../lib/features/profile/presentation/edit_profile_screen.dart) | 169, 173 | Same pattern as above. |
| [`race_settings_screen.dart`](../../lib/features/races/presentation/race_settings_screen.dart) | 174, 178 | Same pattern as above. This screen is also the app's one clear "settings page" — see Batch 4's 2D-tier note. |
| [`race_composer_screen.dart`](../../lib/features/races/presentation/race_composer_screen.dart) | 1027, 1256 | Composer step actions — check emphasis first (is this a "skip"/"back" action? → 2D. Is it "confirm this step"? → 3D). Has the highest raw-radius count in the app (22) — worth a full pass, not just the buttons, while in this file. |
| [`notifications_screen.dart`](../../lib/features/notifications/presentation/notifications_screen.dart) | 72 | "Mark all read" → `NuvoTertiaryButton` or a chip. |
| [`teach_movement_screen.dart`](../../lib/features/races/presentation/custom_pose/teach_movement_screen.dart) | 1721 | Check emphasis of the action before picking 2D vs 3D. |
| [`track_view_screen.dart`](../../lib/features/arena/presentation/track_view/track_view_screen.dart) | 306, 614 | Also has its own off-palette navy/blue (`#071B35`? — verify against `bottom_nav.dart`'s constants, may share the same source). Bundle the button fix with a palette check while in this file. |

---

## Batch 4 — The "2D-appropriate" pass (settings-style screens)

The guide's own example for the 2D tier is "a settings page" — right now no
screen in the app demonstrates that tier deliberately. Plan: once Batch 2/3
land, revisit every row-level action on these screens and downgrade
`NuvoPrimaryButton`/raw controls to `NuvoTertiaryButton` where the action is
routine, not a highlight:

- [`race_settings_screen.dart`](../../lib/features/races/presentation/race_settings_screen.dart)
- [`notification_prefs_screen.dart`](../../lib/features/notifications/presentation/notification_prefs_screen.dart)
- [`edit_profile_screen.dart`](../../lib/features/profile/presentation/edit_profile_screen.dart)

Each of these three currently trips the `Colors.white`/`Colors.black` grep
too — worth a combined color + button + emphasis pass rather than three
separate touches.

---

## Batch 5 — Scanner & sheet chrome (pure black/white surfaces)

| Screen | Plan |
|---|---|
| [`qr_scan_screen.dart`](../../lib/features/social/presentation/qr_scan_screen.dart) | Chrome (top bar, toast, paste-bar, framing accent) → navy/brand instead of black. Camera preview itself stays black (it's a live feed, not a fill choice). |
| [`my_qr_sheet.dart`](../../lib/features/social/presentation/my_qr_sheet.dart) | Check whether the QR code's own white background is a legitimate technical requirement (QR codes need light/dark contrast to scan) vs. a stylistic default — if technical, document the exception rather than "fixing" it. |
| [`race_share_sheet.dart`](../../lib/features/social/presentation/race_share_sheet.dart) | Spot-check `Colors.white`/`black` usage; likely just text-on-fill (legitimate). |

---

## Batch 6 — Trackside / Arena (custom-painted surfaces, higher risk)

These screens hand-roll their own colors because they're doing custom
painting (`CustomPainter`, track geometry), not because someone forgot the
token system — treat differently from the mechanical sweeps above.

| Screen | Signals | Plan |
|---|---|---|
| [`bottom_nav.dart`](../../lib/core/widgets/bottom_nav.dart) | 🎨 `_kTrackNavy`/`_kTrackActiveBlue` | Shared nav — used everywhere, so this is actually high-leverage despite being one file. Replace the two custom constants with `NuvoColors.navy`/`NuvoColors.blue` and confirm the "trackside" nav mode still reads correctly against the arena's dark background (may need `NuvoColors.blueBright` instead of a literal swap — check contrast before committing to the exact token). |
| [`track_view_world.dart`](../../lib/features/arena/presentation/track_view/track_view_world.dart), [`track_view_racer.dart`](../../lib/features/arena/presentation/track_view/track_view_racer.dart) | 🎨 | Custom-painted track/racer visuals. Plan: audit which literals are palette-adjacent (should become tokens) vs. genuinely bespoke (lighting/gradient effects a flat token can't express) before mass-replacing — a track-lighting gradient is not the same violation as a stray off-brand blue. |
| [`arena_screen_fixed.dart`](../../lib/features/arena/presentation/arena_screen_fixed.dart) | ⚪📐5 | Spot-check white/black usage; likely mixed legitimate/illegitimate, needs a manual pass rather than a mechanical sweep. |
| [`nuvo_character_painter.dart`](../../lib/features/races/presentation/widgets/nuvo_character_painter.dart), [`arm_raises_animation.dart`](../../lib/features/races/presentation/widgets/arm_raises_animation.dart) | 🎨 | Character/animation painters — same "bespoke vs. should-be-token" triage as track_view above. |
| [`ai_motion_proof_screen_io.dart`](../../lib/features/races/presentation/ai_motion_proof_screen_io.dart) | 🎨⚪📐9 | Camera overlay UI — do **not** touch anything related to the ML/pose validation logic itself (locked, per project constraints); this plan is strictly about the chrome/overlay colors and radii layered on top of the camera feed. |
| `nuvo_board_components.dart`, `nuvo_rep_pulse.dart`, `trackside_layout_diagnostics.dart` (core widgets) | 🎨 | Same bespoke-vs-token triage; these are shared components so a fix here is high-leverage but also higher-risk (used across Arena/Move/Compete). |

---

## Batch 7 — Animation coverage sweep (the 46 screens with zero `.animate()`)

Not every screen needs choreography — a settings toggle doesn't need a
staggered entrance. Plan: triage into three groups before touching anything.

**Already-animated (skip)** — `email_start_screen`, `email_verify_screen`,
`member_pass_screen`, `onboarding_screen`, `edit_profile_screen`,
`ai_motion_proof_screen_io`, `board_moved_screen`, `create_race_screen`,
`invite_crew_screen`, `join_race_screen`, `proof_review_screen`,
`race_composer_screen`, `submit_proof_screen`.

**High-value, currently static — add entrance/empty-state motion:**
- `compete_screen.dart` / `compete_screen_fixed.dart` — main tab, list entrance.
- `arena_screen.dart` / `arena_screen_fixed.dart` — main tab.
- `pass_screen.dart`, `notifications_screen.dart`, `race_detail_screen.dart`,
  `move_screen.dart`, `profile_screen.dart` — high-traffic, currently a flat
  list/column with no reveal.
- `notification_prefs_screen.dart`, `public_profile_screen.dart`,
  `invite_screen.dart`, `qr_scan_screen.dart`, `race_settings_screen.dart`,
  `proof_screen.dart`, `teach_movement_screen.dart` — secondary but worth the
  same 3-line entrance pattern once it exists as a mixin/extension.

**Low-value / leave alone (functional or ML-adjacent, motion is a distraction
or out of scope):**
- `ai_motion_proof_screen.dart`/`_web.dart` (platform shims), `track_view_*`
  (custom-painted, already animated via `CustomPainter` ticks, not
  `flutter_animate`), diagnostics/dev-only widgets.

**Plan for the mechanism, not just the list**: write one `NuvoEntrance`
extension (`.nuvoEnter()` → `fadeIn().slideY()` with the standard duration/
curve from `NuvoTokens`) so the "high-value" rollout above is a one-line
change per screen instead of hand-writing `.animate()` chains 15 times.

---

## Batch 8 — Token-drift sweep (`BorderRadius.circular`, spacing)

Deferred to last on purpose: doing this before Batches 1-7 land would mean
re-touching every file twice. Once the button/color/animation passes are
done, do one mechanical sweep converting the remaining raw
`BorderRadius.circular(N)` (~62 sites, worst offenders: `race_composer_screen`
22, `race_detail_screen` 11, `ai_motion_proof_screen_io` 9) to `NuvoRadii.*`,
and spot-check `SizedBox`/`EdgeInsets` magic numbers in the same files against
`NuvoSpacing.*`.

---

## Explicitly out of scope for this plan

- ML pose validators, camera bridge, native code, Worker/backend logic — no
  design change in this plan touches them, even in files that also contain UI
  chrome (e.g. `ai_motion_proof_screen_io.dart` — only the overlay/chrome is
  in scope).
- Third-party brand marks (Google "G", Apple logo) — never recolor to match
  the palette; that's a platform requirement, not a design choice.
- `docs/design/NUVO_DESIGN_SYSTEM.md`'s typography/spacing/radius/depth
  sections — still accurate, not being replaced by this plan.

## Suggested execution order

Batch 2 (shared components) → Batch 1 (reward/first-impression) → Batch 3
(raw-button sweep) → Batch 5 (scanner/sheets) → Batch 4 (2D pass) → Batch 7
(animation) → Batch 6 (trackside/arena, needs the most care) → Batch 8
(token drift, mechanical cleanup last).

Batch 2 first because Batches 1, 3, 4, and 7 all consume the components it
creates — building them first means later batches are one-line swaps instead
of hand-rolled fixes that need redoing.
