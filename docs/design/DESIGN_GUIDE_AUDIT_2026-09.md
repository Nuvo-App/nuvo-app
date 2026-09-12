# Nuvo App Design Guide — compliance audit (2026-09)

Audits the current UI against the **Nuvo App Design Guide** (overall emotion,
the 4-6 color rule, and the 3D/2D button system). Supersedes the color/hex
sections of [`NUVO_DESIGN_SYSTEM.md`](NUVO_DESIGN_SYSTEM.md) — that doc's hex
table is stale (predates the current `app_colors.dart`); its typography/
spacing/radius/depth sections are still accurate and this doc doesn't repeat
them.

Method: `grep` sweep of `lib/` for the concrete, checkable rules (raw color
literals, raw Material buttons, token adoption, animation coverage), file:line
evidence for every finding, cross-checked against a working build. Not every
one of the ~35 screens is itemized line-by-line — the goal is every *class* of
violation with enough examples to fix the class, not a line-count trophy.

---

## 0. Where the guide is already true

- **The 6-color palette itself is now correct and centralized**
  ([`app_colors.dart`](../../lib/core/theme/app_colors.dart)) — green
  `#2ECC40`, red `#E72025`, blue `#1264FF`, tan `#EAD0BB`, yellow `#FCCA1D`,
  orange `#F69304`, each with its shadow. One source of truth; every screen
  that uses `NuvoColors.*` picks it up automatically.
- **The 3D/2D button *mechanism* exists** and is centralized in
  [`nuvo_button.dart`](../../lib/core/widgets/nuvo_button.dart): a 3px outline
  in the shadow color, a hard offset shadow underneath for 3D, none for the 2D
  tier (`NuvoTertiaryButton`). `NuvoSuccessButton`/`NuvoDangerButton` already
  color-match their outline+shadow to their own role, which is exactly the
  guide's "shadow color around it" instruction.
- Depth, radius, spacing and typography **token systems exist** and are well
  designed (see `NUVO_DESIGN_SYSTEM.md` §2–5) — the problem below is adoption,
  not the absence of a system.
- The celebration screen (`board_moved_screen.dart`) is green + confetti +
  count-up on a verified result — the reward moment mechanism is in place.

The gap is **adoption**: a real, well-built system that a large fraction of
screens don't use, plus a handful of off-palette colors that predate it.

---

## 1. COLORS — "4-5 colors used for almost everything," never overwhelming

### 1a. Off-palette blues (fragmentation)

The guide's whole point is *one* blue everywhere. Today there are at least
**five different blues** in the app, none of them `#1264FF`:

| File | Color | Used for |
|---|---|---|
| [`bottom_nav.dart:9-10`](../../lib/core/widgets/bottom_nav.dart#L9-L10) | `#071B35` / `#2F7CFF` | Trackside nav mode navy + active blue |
| [`splash_screen.dart:280,292,414,415`](../../lib/features/splash/presentation/splash_screen.dart#L280) | `#1264FF` (ok) but also `#3F83FF`, `#C5D9FA` | Logo glow gradient |
| [`splash_screen.dart:379`](../../lib/features/splash/presentation/splash_screen.dart#L379) | `#618DDE`, `#6E9FF0`, `#79A8FF` | Ambient background gradient |
| [`welcome_race_builder_screen.dart:2233-2271`](../../lib/features/auth/presentation/welcome_race_builder_screen.dart#L2233-L2271) | `#618DDE`, `#6E9FF0`, `#79A8FF`, `#C5D9FA`, `#3F83FF` | Same ambient gradient, duplicated |

**Why this breaks the rule**: a user's very first two screens (splash →
welcome) show three or four blues that are not the brand blue, before the app
even asks them to sign in. It reads as "blue-ish," not "Nuvo blue."

**Elevate**: replace the ad-hoc gradient stops with `NuvoColors.blue` /
`NuvoColors.blueLight` / `NuvoColors.blueShadow` at varying alpha — one hue,
different opacities, which still gives the glow/depth effect without a second
palette. Extract the duplicated gradient into one shared widget
(`NuvoAmbientGlow`) so splash and the welcome builder can't drift apart again.

### 1b. Pure white/black as a primary surface (not just shadows/scrims)

The guide: *"very minimally should things be completely white and black."*
`Colors.black` at low alpha for a modal scrim, or `Colors.white` for text on a
colored fill, is normal and not what this rule is about. The real violations
are places where **black or near-black is the primary background of a whole
screen**:

- [`qr_scan_screen.dart`](../../lib/features/social/presentation/qr_scan_screen.dart#L173) —
  `Scaffold(backgroundColor: Colors.black, ...)`, the entire scanner chrome
  (top bar, toast, paste-bar) is black/white with no brand color at all.
- 244 raw `Colors.white`/`Colors.black` call sites across 49 files
  (`grep -rn "Colors\.white\b\|Colors\.black\b" lib/`). Most are legitimate
  (text-on-fill, scrim alpha) — the ones worth fixing are full-surface fills
  and any `Colors.white`/`Colors.black` that could just as easily be
  `NuvoColors.white`/`NuvoColors.navy` for consistency with the token system
  (today `Colors.white` and `NuvoColors.white` render identically, but the
  raw literal means this screen won't move if the "white" token ever needs to
  shift — e.g., to a warm off-white to feel less clinical).

**Elevate**: give the scanner a navy chrome (matches the celebration/hero
surfaces elsewhere) instead of pure black — camera preview stays black (it has
to, it's the live feed), but the top bar, framing box accent, toast, and paste
bar should read as Nuvo, not a generic camera app. Sweep `Colors.white` →
`NuvoColors.white`, `Colors.black` → `NuvoColors.navy` (or a navy-tinted scrim)
mechanically where used for chrome, not for genuine full-black scrims.

### 1c. Tan used more than "very minimally"

Not found as a violation — `NuvoColors.accent` (tan) has few call sites
(`member_pass_card.dart`, pass-related premium surfaces), which matches the
guide. No action needed here; flagging only so it's checked again after the
remediation below (a common mistake when "fixing" a palette is over-using the
accent color once it's finally the right hex).

---

## 2. SHAPES / BUTTONS — "two types of buttons, 3D and 2D"

### 2a. Raw Material buttons that are neither

`grep -rln "ElevatedButton(\|TextButton(\|OutlinedButton(\|FilledButton("
lib/ --include=*.dart` (excluding the theme/button files themselves) finds
**9 files** with buttons that are flat Material controls — no outline, no
shadow, no brand color, not one of the guide's two types:

| File | Call site | Context |
|---|---|---|
| [`board_moved_screen.dart:222`](../../lib/features/races/presentation/board_moved_screen.dart#L222) | `FilledButton` | **The celebration screen** — the one moment the guide says should "feel significant enough to make someone want to complete" the race. A stock Material `FilledButton` is the single biggest emotional miss in the app relative to this guide. |
| [`track_view_screen.dart:306,614`](../../lib/features/arena/presentation/track_view/track_view_screen.dart#L306) | `FilledButton`, `TextButton` | Trackside race view actions |
| [`profile_screen.dart:63,67`](../../lib/features/profile/presentation/profile_screen.dart#L63-L67) | `TextButton` ×2 | Sign-out / delete-account confirm dialog |
| [`edit_profile_screen.dart:169,173`](../../lib/features/profile/presentation/edit_profile_screen.dart#L169-L173) | `TextButton` ×2 | A confirm dialog |
| [`race_settings_screen.dart:174,178`](../../lib/features/races/presentation/race_settings_screen.dart#L174-L178) | `TextButton` ×2 | A confirm dialog |
| [`race_composer_screen.dart:1027,1256`](../../lib/features/races/presentation/race_composer_screen.dart#L1027) | `TextButton` ×2 | Composer step actions |
| [`notifications_screen.dart:72`](../../lib/features/notifications/presentation/notifications_screen.dart#L72) | `TextButton` | "Mark all read" |
| [`first_use_guide.dart:246`](../../lib/features/onboarding/presentation/first_use_guide.dart#L246) | `TextButton` | Onboarding guide dismissal |
| [`teach_movement_screen.dart:1721`](../../lib/features/races/presentation/custom_pose/teach_movement_screen.dart#L1721) | `TextButton` | Teach Nuvo action |

**Elevate**:
- The confirm-dialog `TextButton` pairs (profile, edit-profile, race-settings)
  are the easiest class to fix: they're all "Cancel" / "Confirm-destructive"
  pairs. Replace with `NuvoTertiaryButton` (2D — "Cancel") +
  `NuvoDangerButton` (3D — the destructive confirm). This is exactly the
  "2D for less emphasis, 3D for the moment that matters" split the guide asks
  for, applied at dialog scale.
- `notifications_screen.dart`'s "Mark all read" and the onboarding-guide
  dismiss are low-emphasis inline actions → `NuvoTertiaryButton` (2D) or a
  chip, not a bare `TextButton`.
- **`board_moved_screen.dart`'s celebration CTA → `NuvoSuccessButton(solid:
  true)` or `NuvoPrimaryButton`**, sized up, is the highest-value single fix
  in this audit: it's the reward moment the guide explicitly calls out.

### 2b. No screen actually classifies itself as "2D-appropriate"

The guide's example use case for 2D is explicit: *"use 2d when there is less
visual emphasis required such as a settings page."* Today `race_settings_
screen.dart` and `notification_prefs_screen.dart` (settings-style screens)
still reach for `NuvoPrimaryButton`/raw `Switch`/`TextButton` rather than
`NuvoTertiaryButton` for their row-level actions — there's no screen in the
app that currently demonstrates the 2D tier as "this is what a calmer screen
looks like." Once 2a is fixed, settings-style screens are the natural home for
`NuvoTertiaryButton` everywhere a `NuvoPrimaryButton` currently appears there.

### 2c. Border/shadow color still navy on the brand-color button

Called out already at the end of the previous turn: `NuvoPrimaryButton`
(blue) and `NuvoOutlineButton` use a **navy** outline, not a blue-shadow
(`#003D71`) outline. The guide's worked example is explicit — "the main color
on top and a 3px outline with **the shadow color** around it" — for every
button, not just Success/Danger. Left unresolved pending your call (see the
open question below); Success/Danger already do this correctly and can be
used as the reference implementation.

---

## 3. OVERALL EMOTION — "fun and playful... rewarding... every part interactive"

### 3a. Animation coverage is thin

Only **13 of 59** presentation files use `.animate()` (`flutter_animate`) at
all (`grep -rl "\.animate()" lib/features`). The guide: *"There should be no
part of the app that doesn't feel responsive or interactive... even simple
loading screens should feel thought out and creative."* The 46 screens with
zero `.animate()` calls include most settings/detail/composer screens — some
of that is legitimately fine (a settings toggle doesn't need choreography),
but loading and empty states are explicitly called out by the guide and are
the cheapest, highest-ROI place to add motion:

- Loading spinners across the app are bare `CircularProgressIndicator()` (grep
  count: 30+ call sites) with no Nuvo treatment — no brand color customization
  beyond the default, no shimmer/skeleton, no personality.
- Compare to the celebration screen and onboarding, which *do* use staggered
  entrance animation (`fadeIn`/`slideY`) — proof the team already knows how to
  do this well; it just isn't applied consistently.

**Elevate**: a `NuvoLoadingIndicator` (brand-blue, maybe a subtle pulse/bounce
matching the "playful" brief) to replace bare `CircularProgressIndicator()`
app-wide is a single-component fix with outsized coverage. Roll the existing
`fadeIn`/`slideY` entrance pattern (already used in `invite_crew_screen.dart`,
onboarding) onto the remaining static list/detail screens as a mechanical
pass — it's the same three lines repeated per screen.

### 3b. "Enticing shapes" — mixed

Where the product-component library is used (podium, board components, race
rows — see `NUVO_DESIGN_SYSTEM.md` §4/§9), shapes are already distinctive:
rounded pills, the podium's stepped layout, hard-offset "physical" cards. The
screens that bypass those components (settings/composer/detail forms, most of
what §2a lists) fall back to plain rectangular `Container`s with a single
`BorderRadius.circular(n)` — functional but not "enticing." **62 raw
`BorderRadius.circular(N)` literals** remain across `lib/features` (not using
`NuvoRadii.*`), which is both a token-drift problem (§4 below) and a symptom
of these screens defaulting to generic rectangles rather than reaching for the
radius scale's more expressive steps (`hero`, `pill`).

---

## 4. TOKEN DRIFT (mechanical, but it's why colors/shapes/spacing keep re-diverging)

`NUVO_DESIGN_SYSTEM.md` already flagged Verify/Profile as "partially
migrated." Confirmed still true and **broader than those two screens**:

- **62** raw `BorderRadius.circular(N)` call sites in `lib/features` (should
  be `NuvoRadii.*`).
- Representative raw `SizedBox`/`EdgeInsets` magic-number counts per screen
  (not exhaustive, illustrative): `move_screen.dart` 12,
  `profile_screen.dart` 13, `notifications_screen.dart` 10,
  `race_settings_screen.dart` 15, `qr_scan_screen.dart` 12.

This matters for the design guide specifically because a raw `Color(0x...)`
or `BorderRadius.circular(14)` is exactly how a *new* off-palette blue or an
off-scale radius gets introduced next time someone edits one of these
screens — the drift in §1a happened one raw literal at a time. Token adoption
is what keeps the "4-5 colors, consistent shapes" rule true going forward, not
just today.

---

## Remediation plan (phased, safest/highest-leverage first)

| Phase | Scope | Risk | Files |
|---|---|---|---|
| **1** | Celebration CTA → `NuvoSuccessButton`; confirm-dialog `TextButton` pairs → `NuvoTertiaryButton` + `NuvoDangerButton` (5 files) | low — isolated widgets, no layout restructuring | board_moved, profile, edit_profile, race_settings |
| **2** | Canonicalize stray blues (splash + welcome_race_builder ambient gradients) into one `NuvoAmbientGlow` widget using palette tokens | low — visual-only, same effect different hex | splash_screen, welcome_race_builder_screen, new shared widget |
| **3** | QR scanner chrome → navy/brand instead of black; sweep `Colors.white`/`Colors.black` → `NuvoColors.*` in chrome contexts | low-medium — visual only, scanner is new code from this session | qr_scan_screen + a mechanical sweep |
| **4** | Remaining raw `TextButton`/`FilledButton` sites (composer, notifications, teach-movement, trackside) → Nuvo 2D/3D | medium — some are mid-flow actions, needs a quick look at each context | 4 files |
| **5** | `NuvoLoadingIndicator` component + roll out to replace bare `CircularProgressIndicator()` app-wide | medium — touches ~30 call sites, but it's one component swapped in everywhere | app-wide |
| **6** | Token migration sweep — `BorderRadius.circular(N)` → `NuvoRadii.*`, remaining raw spacing → `NuvoSpacing.*` | medium — mechanical but high file count (60+ sites) | app-wide |
| **7** (needs your call) | Primary/Secondary button outline+shadow: navy → blue-shadow, matching the guide's literal example and Success/Danger's existing pattern | **visual identity decision** — changes the app's signature "navy ink edge" look | nuvo_button.dart |

Phases 1-3 are ready to execute now with no open questions. Phase 7 is a real
design-direction fork (navy ink edge vs. color-matched-per-role edge) and
should be your call, not mine, before I touch it.

Say the word and I'll start on Phase 1.
