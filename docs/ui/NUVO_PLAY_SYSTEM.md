# NUVO PLAY SYSTEM — Interaction & Motion Vocabulary

> **STATUS: Phase 1 IMPLEMENTED (physical press foundation, button shadow
> compression, NuvoToggle, generic-widget cleanup). Phase 2 IMPLEMENTED
> (NuvoPop reactions, NuvoStateMorph CTAs, leaderboard FLIP reorder +
> entering, feed keyed insertion, NuvoShake, NumberFlow on reaction count +
> rank, Join→Verify bar morph). Remaining concepts PROPOSED — see markers.**
>
> Source of truth for: how objects in Nuvo respond to touch, selection,
> navigation, change, reward, and error.

Nuvo is already halfway physical: thick navy borders, offset navy shadows,
blue action surfaces, and a real motion-token file (`NuvoMotion`,
`NuvoHaptics`, `NuvoPressable`, `NuvoTabStack`, `NuvoReorderColumn`) plus
`NuvoNumberFlow`, `NuvoRepPulse`, and `_PhysicalButtonShell`. What is missing
is *coverage*: the good primitives are not wired everywhere, and a handful of
stock widgets leak through.

---

## 1. Philosophy

Every interaction must answer:

1. What did I touch?
2. Did it react immediately?
3. Did it feel physical?
4. Did something change?
5. Did that change have weight / energy / consequence?

The governing metaphor: **the navy offset shadow is the floor; the surface is
the object.** Pressing an object moves it *toward its shadow*, not merely
smaller. Releasing lets it spring back into place.

Motion with no interaction meaning is banned. Motion must communicate touch,
selection, hierarchy, cause/effect, progress, success, failure, or spatial
relationship — nothing else.

---

## 2. Physical model

| Object | Rest | Pressed | Release |
|---|---|---|---|
| Filled button (hard shadow) | y=0, shadow offset +5 | y=+4, shadow offset ≈1 | spring −overshoot→0 |
| Bordered card (quiet/no shadow) | y=0 | y=+2, scale .98 | settle to 0 |
| Chip / reaction | scale=1 | scale .93, tiny y+1 | easeOutBack |
| Selected item | lift −2, accent ink | — | slides into place |

Existing reference implementations:

- `_PhysicalButtonShell` (`nuvo_button.dart`) — already does
  translate(+4,+4) + shadow removal on press. This is the Nuvo Press for
  buttons; it needs a spring settle and (PROPOSED) shadow *compression*
  instead of shadow *deletion*.
- `NuvoPressable` (`nuvo_motion.dart`) — translateY 2 + scale .97,
  controller-based, haptic-aware. Exists but is **not wired anywhere**;
  `PressableScale` (scale-only) is the one in use everywhere.

---

## 3. The primitives (grammar, not a zoo)

### 3.1 NuvoPress — IMPLEMENTED: `NuvoPressable` is the default surface

Pointer down: translateY +3 ([NuvoMotion.pressTranslateY], sized to the
3px `hardSmall` shadow) + scale .97–.99. Release: `NuvoMotion.spring`
(easeOutBack — tiny dip past rest). Reduced motion: instant state, no travel.

Hierarchy now:

```
NuvoPressable              ← the physical press (translate + scale + spring)
    ├── PressableScale     ← compat shim; ~45 legacy call sites ride it
    ├── _PhysicalButtonShell ← every Nuvo*Button: translate +4 AND shadow
    │                          offset compresses ×(1−0.6t) — 5px → 2px,
    │                          never deleted
    └── NuvoToggle          ← press-compress + spring-sliding knob
```

### 3.2 NuvoLift

Selected/dragged/active objects rise: translateY −2…−4, scale 1.01–1.03,
shadow expands. Used on drag start (carousel cards are PageView, not
draggables — applies to any future reorder/drag), and to the "active racer"
treatment. **No current implementation — Phase 2.**

### 3.3 NuvoSelect

Selection moves, it doesn't repaint. Existing real examples:

- `_SegmentedControl` (Verify) — sliding pill via `AnimatedAlign`. ✅ keep.
- Bottom nav — `TweenAnimationBuilder` color/lerp + lift −2 + haptic. ✅ keep.
- `NuvoTabStack` — directional root-tab slide. ✅ keep.
- Crew `_CrewTabs` — check: switches content instantly. PROPOSED: slide.

### 3.4 NuvoPop — IMPLEMENTED

`NuvoPop(trigger, intensity, child)` replays `1 → 1+0.2·i → 0.98 → 1`
(260ms) whenever `trigger` changes. Reduced motion: skipped. Wired into
`_ReactionChip` — emoji glyph pops full-strength when a reaction is added,
half-strength on removal; the count rolls via `NuvoNumberFlow`. The feed
card itself never moves.

### 3.5 NuvoCount — EXISTS: `NuvoNumberFlow`

Digit-roll odometer, direction-aware. Exists; partially adopted
(`TweenAnimationBuilder` count-up in Profile `_HeaderStat` should become
`NuvoNumberFlow` so score/stat motion is identical everywhere — PROPOSED).

### 3.6 NuvoSlide — EXISTS: `NuvoTabStack`

Direction-aware 24px/250ms travel. Reuse the same curve/distance for
in-screen content swaps (Verify segment switcher already approximates it;
unify constants).

### 3.7 NuvoSnap

Drag-follows-finger, velocity-aware spring to snap. Arena hero carousel is a
`PageView.builder` — PROPOSED: tune `PageScrollPhysics` feel only (already
native-good); no custom drag system.

### 3.8 NuvoSuccess

Rep counted / proof accepted / finish line crossed: `NuvoRepPulse` (+1 punch
+ haptic, EXISTS in verification + teach flows), border pulse, count jump.
No confetti for ordinary reps. Level-3 moments only (see §13).

### 3.9 NuvoError / "Nope" — IMPLEMENTED as `NuvoShake`

`NuvoShake(trigger, amplitude: 5, child)`: damped sine, 2.5 wiggles in
280ms, replays on trigger change, skipped under reduced motion (pair the
same trigger with a color/border cue). Wired: composer goal stepper —
decrement at the floor shakes the minus button instead of silently doing
nothing. Not for backend failures or camera-readiness states.

### 3.10 NuvoMorph — IMPLEMENTED as `NuvoStateMorph`

`NuvoStateMorph(stateKey, child)`: `AnimatedSize` (NuvoMotion.settle) +
keyed `AnimatedSwitcher` (fade + 0.94→1 scale). The slot eases between
footprints so Add→Sent / Accept→In-crew reads as one object changing
state, not widget replacement. Wired into `add_crew._cta` and
`public_profile._cta` (all four `CrewConnectionStatus` branches).

### 3.11 NuvoFlip — EXISTS: `NuvoFlipCard`

A two-faced card where the flip is the seam between two semantic layers —
identity ↔ competition. Controlled (`flipped`), card-tap + mandatory
labelled affordance, 400ms moderate-perspective rotateY, spring settle,
fixed footprint (explicit height, or sizes to the taller face), crossfade
under reduced motion. Used by the person card inside `_PersonSheet` and
the featured race card on Compete; see §13.4 for the semantic-sides rule.

### 3.12 NuvoCopy — EXISTS: `NuvoCopyButton`

Local copy confirmation (`nuvo_button.dart`): outline-tier button that
morphs link→check + label→"Copied" on a success tint, confirm haptic,
2.5s auto-reset — the surface is the response, never a SnackBar.

### 3.13 NuvoRipple — EXISTS: `NuvoRippleSurface`

Touch feedback for flat icon controls (`nuvo_ripple_surface.dart`):
Nuvo-blue circular ink from the touch point, 44px hit floor, splash
suppressed under reduced motion. Ripple OR physical depth — never both.

### 3.14 NuvoPagePill — EXISTS: `NuvoPagePill`

Animated pagination (`nuvo_page_pill.dart`): active slot morphs into a
wide blue pill, inactives stay small navy-outline circles, on
`NuvoMotion.select`. Indicator only — it never owns the `PageController`.

---

## 4. Native / generic widget inventory

| Widget | Site | Verdict |
|---|---|---|
| `Switch` (stock) | `profile_screen` demo row, `notification_prefs` matrix | **REPLACED** with `NuvoToggle`. Only `onboarding_screen`'s `Switch.adaptive` remains — intentionally untouched this phase |
| `InkWell` (default ripple) | was 15 sites | **REPLACED** — all converted to `NuvoPressable` (micro press, no haptics). `welcome_race_builder` retained for the onboarding exclusion |
| `GestureDetector` (bare) | ~55 sites | Feature-level taps converted to `NuvoPressable` (~25 sites); kept: drag handlers (segment swipe), long-press stepper wrapper, onboarding/auth/camera surfaces, widget internals |
| `AnimatedSwitcher` | `move_screen.dart` (segment content — directional, good), `welcome_race_builder_screen.dart:1414` (verified ↔ count fade — should pop/morph) | 1 of 2 needs upgrade |
| `SnackBar` (stock gray) | 22 files | Keep behavior, reskin: `NuvoToast` — navy surface, ice text, quiet border, slide-up |
| `showModalBottomSheet` | 5 sites (person sheet, QR, share, edit profile, board) | Keep; propose consistent radius + drag-follow |
| `Switch`-adjacent prefs matrix | `notification_prefs_screen` grid | `NuvoToggle` with Nuvo ice track + navy knob border |
| `Slider` | `rive_calibration_screen` (dev tool) | Leave |
| `DropdownButtonFormField` | `race_settings_screen:622` (proof mode) | Leave — settings gear |
| `RefreshIndicator` | 6 screens | Stock pull-to-refresh, already blue-tinted — acceptable; optional custom spinner later |
| `Hero` | 14 files (member pass, my_nuvo, race surfaces) | Already meaningful shared-element transitions ✅ |
| `PageView` | Arena carousel, composer, onboarding | Keep; tune physics feel only |
| `Checkbox` | 1 site | Leave |

---

## 5. Motion tokens (proposed; existing values are real)

| Token | Value | Status |
|---|---|---|
| pressIn | 80ms | EXISTS (`NuvoMotion`) |
| pressOut | 220ms | EXISTS |
| tabSwitch | 250ms | EXISTS |
| select | 200ms | EXISTS |
| reorder | 300ms | EXISTS |
| settle curve | Cubic(0.22,1,0.36,1) | EXISTS |
| spring curve | easeOutBack | EXISTS |
| tabTravel | 24px | EXISTS |
| buttonPressDepth (button w/ shadow) | 4px | IMPLEMENTED |
| pressTranslateY (card/quiet) | 3px | IMPLEMENTED |
| pressScale (card) | .97 | IMPLEMENTED |
| pressScale (chip/icon) | .94 | IMPLEMENTED per-call-site |
| shadowCompress | offset ×(1−0.6t) → 5px keeps 2px | IMPLEMENTED |
| pop scale | .85→1.08→1, 180ms | PROPOSED |
| shake | ±5px ×2, 240ms | PROPOSED |
| lift | −3px, scale 1.02 | PROPOSED |

---

## 6. Screen-by-screen plan

### Arena
- Hero card tap: `PressableScale` → `NuvoPressable` (+shadow compress — it
  carries `hardLarge`). **High.**
- Submit proof / New / Join row: buttons already use `_PhysicalButtonShell`
  (translate+shadow-drop) — upgrade to shadow *compress* + spring settle. **High.**
- Carousel: keep PageView physics; dots already fine. **Done.**
- Leaderboard rows: `NuvoReorderColumn` when standings re-rank (it exists,
  unwired). **Medium.**
- Score numerals: `NuvoNumberFlow` if not already. **Medium.**

### Compete
- Quick Start tiles: `PressableScale` → `NuvoPressable` + translate toward
  quiet border. **High.**
- Waiting/Finished summary rows: chevron already `AnimatedRotation`; add
  micro press. **Low.**
- Start/Join header buttons: same shell upgrade as Arena. **High.**

### Verify
- Segmented control: sliding pill ✅; tab labels get `NuvoPressable`. **Low.**
- Up next hero + Start verification: `NuvoPressable` + shell compress. **High.**
- Also-ready rows: micro press (translate 1–2 + icon-well compress). **Medium.**
- Segment content switcher: already directional — unify on NuvoMotion
  constants. **Low.**

### Crew
- `_CrewHeroCard`, `_LiveRaceCard` (adapter over `NuvoLiveRaceCard`,
  §13.6), feed cards: `NuvoPressable`. **High.**
- `_ReactionChip`: add NuvoPop on `mine` flip + keep morph. **Medium.**
- `_RaceCrewChips` / people strip avatars: micro press. **Medium.**
- Request Accept/Decline → "Connected" morph (`NuvoMorph`). **Medium.**
- `_CrewTabs` selection: sliding indicator (NuvoSelect). **Medium.**

### Profile
- `_ActiveRaceTile`/`_ResultTile`: already `PressableScale` → `NuvoPressable`. **Low.**
- `_HeaderStat` `TweenAnimationBuilder` count-up → `NuvoNumberFlow`. **Low.**
- Demo-mode `Switch` → `NuvoToggle`. **High** (native widget).
- See all / Edit: micro press. **Low.**

### Composer
- Activity/format pickers: already `AnimatedContainer` + `PressableScale` —
  migrate to `NuvoPressable` + NuvoSelect indicator. **Medium.**
- PageView step changes: keep. Validation: `NuvoShake` on incomplete step. **Medium.**

### Notifications / Settings
- `Switch` ×N → `NuvoToggle`. **High.**
- `InkWell` rows → `NuvoPressable`. **Medium.**
- Mark-all-read / destructive: `NuvoConfirmDialog` exists ✅.

### Onboarding
- Verified↔count `AnimatedSwitcher` → NuvoPop/count morph. **Low.**
- Flip text + guide coach marks: already bespoke ✅.

### Camera / verification
- `NuvoRepPulse` exists ✅ — ensure identical across screens.
- Rejected framing → `NuvoShake`/`NuvoError` states. **Medium.**

---

## 7. Motion intensity levels

| Level | Feel | Examples |
|---|---|---|
| 1 — Micro | fast, quiet, no overshoot | row tap, icon, See all, chevron |
| 2 — Action | physical press + shadow | Submit proof, Start race, Rematch, Accept |
| 3 — Moment | overshoot, pulse, reward | win, PB, overtake, proof accepted, reaction received |

Level 3 is rationed — a full-screen pulse belongs to things that matter.

---

## 8. Haptics map (extends existing `NuvoHaptics`)

| Intent | Call | Where |
|---|---|---|
| selection | `NuvoHaptics.select()` | tabs, chips, toggles, nav |
| press | `NuvoHaptics.press()` | primary CTAs |
| confirm | `NuvoHaptics.confirm()` | proof accepted, reaction, rank up |
| error | `HapticFeedback.mediumImpact` (PROPOSED `NuvoHaptics.error()`) | rejected proof, invalid input |
| none | — | list rows, decorative |

---

## 9. Reduced motion

Every primitive degrades to: keep opacity/color + small scale (≤.98) +
instant translate (0). `NuvoPressable`, `NuvoTabStack`, `NuvoStaggerIn`
already honor `MediaQuery.disableAnimationsOf` where implemented — the
check must become a `NuvoMotion.reduceMotion(context)` helper used by ALL
new primitives so no call site decides ad hoc.

---

## 10. Performance rules

- Implicit animations (`AnimatedContainer`, `TweenAnimationBuilder`) for
  decoration-only changes; a single `AnimationController` per interactive
  widget for press (already the `NuvoPressable` pattern).
- Never animate `boxShadow` list identity per frame on large surfaces —
  interpolate offset via `BoxShadow.lerp` in the same AnimatedBuilder that
  drives the transform (cheap, single repaint of one card).
- `RepaintBoundary` only around camera/live surfaces, not cards.
- No per-row controllers inside long lists for passive entrance — use
  `NuvoStaggerIn` (stateless TweenAnimationBuilder).

---

## 11. Top 10 highest-impact changes

1. Migrate `PressableScale` → `NuvoPressable` everywhere (~15 files) —
   every card/row/tile gains the physical press.
2. `_PhysicalButtonShell`: shadow delete → shadow compress + spring settle —
   every button becomes the arcade button.
3. `NuvoToggle` replacing the 2 stock `Switch` sites (settings grid has
   the most).
4. `InkWell` rows (add-crew, notifications, settings, composer) →
   `NuvoPressable` micro press — kills the last Material ripples.
5. Bare `GestureDetector` taps (See all, chevrons, chips) → press feedback.
6. `NuvoNumberFlow` in Profile `_HeaderStat` + Arena score.
7. Reaction chips: NuvoPop on toggle.
8. Crew tabs → sliding selection indicator.
9. `NuvoReorderColumn` wired to standings lists.
10. `NuvoToast` reskin for the 22 SnackBar sites.

## 12. Phase 1 (IMPLEMENTED)

- `PressableScale` → compat shim over `NuvoPressable` (~45 call sites
  upgraded at once; haptic-free, preserving silent row behavior).
- `_PhysicalButtonShell` — shadow compress (×0.6 residual) + easeOutBack
  spring release, every `Nuvo*Button` inherits.
- `NuvoToggle` — navy-outline pill, ice→blue track, navy→white spring knob,
  press compression + select haptic; live in the prefs matrix + profile demo row.
- 15 `InkWell` sites → `NuvoPressable`; ~25 bare `GestureDetector` taps →
  `NuvoPressable` (see §4 for retained exceptions).
- `NuvoNumberFlow` in Profile `_HeaderStat` (RACING / WINS / WIN RATE).
- Tokens: `pressTranslateY=3`, `buttonPressDepth=4`, `shadowCompress=0.6`;
  release curve `NuvoMotion.spring`; `disableAnimationsOf` honored by
  `NuvoPressable`, button shell, `NuvoToggle`.

## Phase 2 (PARTIALLY IMPLEMENTED)

- IMPLEMENTED: `NuvoPop` on reaction emoji + `NuvoNumberFlow` count;
  `NuvoStateMorph` on crew connect CTAs; `NuvoReorderColumn` wired into
  race-detail `_LeaderboardGroup` (keyed rows + dividers folded into slots)
  and Arena `miniLeaderboard`; new-key rows enter with 14px rise + fade;
  rank numeral rolls via `NuvoNumberFlow`; `NuvoHaptics.confirm()` fires
  only when the viewer's own rank improves. Reduced motion skips all of it.
- IMPLEMENTED (2.5): `NuvoShake` + stepper-floor site; keyed feed insertion
  on the For-you live + social lists (`NuvoReorderColumn` keyed on item id —
  a real new event enters, displaced tiles travel, nothing replays on plain
  refreshes); Join→Verify bar morph in `race_detail._VerifyBar`; reorder
  edge-case coverage (removal, re-add, score-only change, reduced motion).
- PROPOSED: `NuvoToast` SnackBar reskin (audit found ~70 sites, ~85% are
  correct global-async-failure usage — no repeated need for a new system;
  2 success toasts may become redundant where the CTA now morphs),
  Crew-tab sliding indicator, onboarding motion, camera success/fail
  choreography, Level-3 win/finish moments beyond `board_moved_screen`.

---

## 13. External interaction references — audited against the codebase

> Evaluation of React/Animate-UI behavior patterns translated into Nuvo's
> navy-outline / physical-shadow language. The IDEA is assessed, never the
> web implementation: no Framer Motion, no hover, no Radix/shadcn styling.
> Audit + proposal only — nothing in this section is implementation-queued
> without review.

### 13.1 Alert dialog — IMPLEMENTED in `showNuvoConfirmDialog`

**Reference** — modal interruption: directional spring entrance, explicit
Cancel/Action, motion communicates seriousness.

**Good Nuvo use cases** — already covered: `showNuvoConfirmDialog` owns all
six destructive/confirm sites (delete account `profile_screen`,
discard edits `edit_profile_screen`, remove crew `public_profile_screen`,
abandon proof `submit_proof_screen`, race settings, delete custom motion
`teach_movement_screen`). Coverage is done; the gap is the *presentation*.

**Bad Nuvo use cases** — non-destructive info ("code sent", "link copied" —
those are surface-feedback jobs, not modal jobs); anything Level 1.

**Nuvo adaptation** — keep the API (`showNuvoConfirmDialog`), change its
interior: navy outline + subtle offset shadow on the `Dialog` (today it's
bare `RoundedRectangleBorder`), barrier dims quickly (~150ms), dialog enters
with a small y+scale spring (~24px rise, `NuvoMotion.spring` at reduced
overshoot), action buttons already physical. Destructive cadence stays
quiet — no playful bounce.

**Proposed primitive** — `NuvoAlertDialog` internals under
`showNuvoConfirmDialog` (`showGeneralDialog` + custom transition). One file;
all six call sites inherit.

**Shipped** — same API, new interior: navy-45% scrim, navy 2px outline +
`hardMedium` offset shadow on a surface-white card, 180ms entrance
(20px rise + 0.96→1 scale on `NuvoMotion.settle`), plain fade under
reduced motion. All six destructive sites inherit; motion stays Level 2 —
a serious arrival, not a reward bounce.

**Motion intensity** — Level 2 / serious.

**Accessibility fallback** — reduced motion: fade only, no slide/scale;
barrier is labelled and dismisses.

### 13.2 Copy button — IMPLEMENTED as `NuvoCopyButton`

**Reference** — tap → surface itself morphs icon/label to "Copied",
auto-resets. Replaces tap → SnackBar.

**Good Nuvo use cases** — the five user-facing copy→SnackBar sites:
`my_nuvo_screen.dart` (`_copy` — member code + invite link, two call
sites), `race_share_sheet.dart` ("Link copied."), `my_qr_sheet.dart`
("Link copied."), `invite_crew_screen.dart` ("Invite code copied."),
`member_pass_screen.dart` ("Link copied to clipboard." — onboarding, so
adoption waits for that ownership window). Dev/debug copies
(`race_composer_screen` debug report, `teach_movement_screen` logs) are
optional — they're tools, but the same primitive fits.

**Bad Nuvo use cases** — actions that are not copying (don't stretch the
primitive into a generic success button); flows where the copied artifact
needs explanation (keep a sheet there).

**Nuvo adaptation** — REST: `[copy glyph] Copy code` on the existing quiet
chip style; PRESS: `NuvoPressable` micro press; SUCCESS: glyph pops to a
check (`NuvoPop`), label morphs "Copied" (`AnimatedSwitcher` or the
`NuvoMorph` approach), `NuvoHaptics.confirm()`-light; auto-reset ~2.5s.
No SnackBar — the surface carries the confirmation.

**Proposed primitive** — `NuvoCopyButton(label, text, {onCopied})`.

**Shipped** — `NuvoCopyButton` in `nuvo_button.dart`: outline-tier chrome,
`Clipboard.setData` → `NuvoHaptics.confirm()`, icon pops link→check and
label morphs to "Copied" on a success-tinted surface, 2.5s auto-reset.
Converted all five user-facing sites: `my_qr_sheet`, `race_share_sheet`,
`my_nuvo_screen` (link button + `_CodeChip`, which carries the same
self-confirm internally), `invite_crew_screen`, `member_pass_screen`.
Errors stay global — the button only confirms real success.

**Motion intensity** — Level 1 with a Level-3-pop *accent* (the glyph only).

**Accessibility fallback** — reduced motion: the AnimatedSwitcher swap
still occurs (state change is informative); haptic unchanged.

### 13.3 Ripple — IMPLEMENTED as `NuvoRippleSurface`

**Reference** — localized ripple from touch point + slight scale.

**Good Nuvo use cases** — surfaces with no offset shadow where physical
press would look wrong: top icon controls (Crew header Search / QR /
notifications bell, notification-screen icon actions), ghost/quiet
secondary actions, flat chips too light for a shadow press. The audit's
11 `InkWell` files are mostly *row* taps → those get `NuvoPressable`
(press, not ripple). `NuvoRippleSurface` covers only the residue: true
icon-only circular controls.

**Bad Nuvo use cases** — every signature CTA and shadow-carrying card:
physical depth is the metaphor there. Never stack ripple + bounce +
shadow compress on one control — hierarchy picks ONE touch metaphor.

**Nuvo adaptation** — subtle Nuvo-blue/ice radial ink from the down-event
position (~180ms, low alpha), clipped to the control's circle/rounded
shape; micro `NuvoPressable` translate may accompany it but no scale-pop.
Not a gray Material ripple — implement via `CustomPaint`/`InkResponse`
with Nuvo colors, not `Theme.splashFactory`.

**Proposed primitive** — `NuvoRippleSurface(child, onTap, shape)`.

**Shipped** — `nuvo_ripple_surface.dart`: `InkResponse` tinted
actionBlue-14% splash / 7% highlight, circular, 44px hit floor.
Applied to the flat header icons — Crew Search + member-code QR
(`pass_screen`) and `NotificationBell`. Shadow-carrying controls
(Quick Starts, CTAs, `NuvoIconAction` chips) keep physical press —
one touch metaphor per control.

**Motion intensity** — Level 1.

**Accessibility fallback** — reduced motion: `NoSplash` + quiet
highlight only.

### 13.4 Flip card — APPROVED for the compact competitor card / REJECTED for full Profile

> **AMENDED** — the earlier audit rejected this outright because
> `_PersonSheet` "already showed the same information in one scrolling
> sheet." Product direction then clarified a semantic two-sided model that
> gives the flip a real reason to exist: **the flip is the seam between
> relationship info and competitive info.** Front = "who is this person to
> me?" Back = "how do we compete?" That is two genuinely different layers,
> not one sheet split arbitrarily.

**Reference** — card flips in 3D to reveal alternate info on its back.

**Good Nuvo use cases** — the compact person/competitor card inside
`_PersonSheet` (`pass_screen.dart`), opened from Crew avatars, leaderboard
avatars, race participants, and social-feed people.

**Bad Nuvo use cases** — the full Profile screen (stays normal); any
surface where front/back aren't semantically distinct layers; rotating
the whole bottom sheet.

**Nuvo adaptation — shipped in `_PersonSheet`:**
- `NuvoFlipCard` (`nuvo_flip_card.dart`) flips only the central card —
  sheet handle, the `Stats ↻`/`About ↻` affordance, and the
  Race/Profile actions are stable chrome outside the card.
- FRONT (identity): avatar, name, handle, "Racing now" pill,
  "N races together".
- BACK (competition): `{FIRST} VS YOU` scoreboard (`theirs — mine`),
  shared-race count + "racing together now", best matchup (canonical
  activity grouping), RECENT rows from final standings.
- Explicit affordance in both directions (card tap is a bonus, not the
  only doorway), 400ms rotateY with moderate perspective (0.0012) +
  `NuvoMotion.spring` settle, fixed 288px footprint so the sheet never
  jumps, haptic select on flip.
- Empty back: clean "No races together yet" — never fabricated stats.

**Proposed primitive** — `NuvoFlipCard` ✅ exists.

**Motion intensity** — Level 2.

**Accessibility fallback** — `MediaQuery.disableAnimationsOf` → crossfade +
slight slide (`AnimatedSwitcher`), labelled flip control always present.

**The general rule — a flip is allowed only when front/back answer two
distinct questions.** A flip is a semantic seam, not a way to hide overflow.
Approved pairs so far:

| Surface | Front question | Back question |
|---|---|---|
| Person card (`_PersonSheet`) | Who are they to me? | How do we compete? |
| Featured race (Compete) | What race is this / what can I do? | What's happening inside it? |

**Experiment — featured race flip (Compete, shipped as prototype):**
`NuvoFlipCard` wraps `NuvoFeaturedRaceCard` in `compete_screen_fixed`.
- FRONT is unchanged action orientation (title, lane, progress, CTA) plus
  a quiet `Updates ↻` affordance in the title row's trailing slot
  (`RaceHero.headerAction` — additive param, no geometry change).
- BACK (`_FeaturedRaceStatusFace`) answers "what's happening inside?"
  from canonical data only: `serverRankedParticipants` top-3 + the
  viewer's own row if below, `viewerContext` for the position line
  ("N reps behind Riley" / "You lead" / "Tied at the front"), latest
  `recentProofs` event (fallback: `updatedAt` age), `N racing` + the same
  `Open race` CTA in the strip. No proofs → "Waiting for the first
  proof" — never fabricated events.
- Affordances only: card tap still opens the race (`onFlip` not wired);
  flip belongs to `Updates ↻` / `Race ↻` so action zones never collide.
- `NuvoFlipCard` with no fixed height sizes to the taller face and holds
  that footprint — the section below never shifts.
- Explicitly NOT applied: waiting/finished summaries, quick starts,
  Profile rows, Arena cards — novelty stays rare by design.

### 13.5 Motion carousel — polish pagination, keep `PageView`

**Reference** — drag/snap carousel: active slide scales ~1.0, neighbors
shrink ~.96, pagination morphs into a pill for the active item.

**Good Nuvo use cases** —
- **Arena hero carousel** (`arena_screen_fixed.dart` — `PageView.builder`
  `viewportFraction: 1` + static `_PageDots`): pill-morph pagination is the
  real delta; neighbor *peek* would need `viewportFraction < 1` (~.92), a
  layout call, not a widget swap. Note: Arena is Agent-1-owned — proposal
  only, no edits from this side.
- **Onboarding cinematic pager** (`welcome_race_builder_screen`) — pages
  are gated scenes, not browsable cards; only pagination animation would
  apply, and onboarding is outside Phase-1 ownership anyway.
- **Composer `PageView`** — a step wizard, not a carousel; excluded.

**Bad Nuvo use cases** — the composer wizard (step flow must not "peek"),
any single-item pager (nothing to communicate), any place where peeking a
cut-off card would read as clipped content rather than spatial depth.

**Nuvo adaptation** — keep `PageView`/`PageController` (the brief's rule
stands: don't replace working mechanics). Add: `_PageDots` → active dot
animates into a Nuvo pill (`AnimatedContainer` width + blue fill on the
selected index); optional active-slide scale lerp driven by
`controller.page` if a peek layout is ever approved.

**Proposed primitive** — `NuvoMotionCarousel` is overkill for what exists;
the real deliverable is an animated **`NuvoPagePill`** indicator +
documented scale-lerp recipe.

**Shipped (primitive only)** — `nuvo_page_pill.dart`: the dot→pill morph
(Arena's `_PageDots` shape, standardized to `NuvoMotion.select` +
`NuvoColors.actionBlue`). Integration is Agent-1's call — swap `_PageDots`
for `NuvoPagePill` in `arena_screen_fixed.dart` (~5 lines, same API:
`count` + `selected`).

**Motion intensity** — Level 1 (continuous, follows finger — not a
triggered animation).

**Accessibility fallback** — `PageView` semantics already announce page
position; reduced motion: dots swap without width animation.

---

### 13.6 Live surfaces — IMPLEMENTED as `NuvoLiveRaceCard`

**The principle** — *Live is communicated by state, motion, and accent —
not by flooding the card with a dark color.* The card is content; the
action is the accent. Never swap one giant dark block for a giant
bright-blue one either.

**Shipped** — `nuvo_live_race_card.dart`, consumed by Crew's
`_LiveRaceCard` adapter (feed + Races tab):

- Surface: white/light face, navy type, quiet navy outline, `hardSmall`
  offset depth — the same content-surface language as the rest of Crew.
- Live state: red dot with a breathing halo (the only continuously
  animating element — never the whole card), `LIVE` kicker, canonical
  countdown (`35m left` / `Ending` in danger).
- Scores ride `NuvoNumberFlow` so a live update rolls instead of jumping.
- `primary` shows the head-to-head split for two-racer payloads
  (name/score columns + a proportional share bar + a canonical gap line);
  3+ racers fall back to the ranked matchup line. `compact` keeps two
  rows for secondary live races — Races tab stacks one primary + one
  compact.
- Reactions stay canonical: Crew injects `_ReactionBar` (light mode) into
  the card's `trailing` slot; the card never owns reaction data.
- Reduced motion: the halo freezes; everything else is static layout.

**Canonical-only rule** — gap text ("Noah leads by 2", "You lead",
"Level") is pure rank/score arithmetic on the payload. If a fact isn't in
`live`, it isn't on the card.

---

## 14. Primitive set — re-ranked after the reference audit

| Rank | Primitive | Status / rationale |
|---|---|---|
| **High impact / low risk** | `NuvoPressable` | Phase-1 shipped — press coverage in progress |
| | `NuvoToggle` | Shipped — both `Switch` sites replaced |
| | `NuvoCopyButton` | **Shipped** — all 5 copy→SnackBar sites now self-confirm |
| | `NuvoAlertDialog` | **Shipped** as `showNuvoConfirmDialog` interior — navy chrome + spring entrance, all six sites inherit |
| | `NuvoPagePill` | **Shipped as primitive** — Arena `_PageDots` swap is Agent-1's (~5 lines, same API) |
| | `NuvoLiveRaceCard` | **Shipped** — light-surface live family (primary/compact); Crew's `_LiveRaceCard` adapter feeds it canonical `race_live` payloads (§13.6) |
| **High impact / medium risk** | `NuvoRippleSurface` | **Shipped** — scoped to icon-only residue: Crew header Search/QR + notification bell |
| | `NuvoReaction` (NuvoPop on chips) | Delightful but content-reactive; needs audit of feed density first |
| | `NuvoCountFlow` (= `NuvoNumberFlow` adoption) | Exists; remaining swaps are `_HeaderStat` + Arena numerals — low risk but low visibility |
| **Experimental** | `NuvoRewardMoment` choreography | Level-3 rationing needs product calls on what earns it |
| | `NuvoSegment`, `NuvoToast`, `NuvoShake`, `NuvoMorph` | Phase-2 backlog from §3 — unchanged |
| **Scoped approval** | `NuvoFlipCard` | **Approved + shipped** for the compact competitor card in `_PersonSheet` and (experiment) the featured race card on Compete — flip = semantic seam between two distinct questions. **Rejected for full Profile** (§13.4) |

**Bottom line:** all five references are now closed: `NuvoCopyButton`,
`NuvoAlertDialog` interior, `NuvoRippleSurface`, and `NuvoPagePill` are
implemented; `NuvoFlipCard` is shipped scoped to two semantic-side
surfaces (person card, featured race).
