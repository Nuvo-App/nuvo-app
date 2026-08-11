# Nuvo Design System

Source of truth for Nuvo's visual language. Extracted from the approved
implementation at commit `1691fc3` (tagged `nuvo-ui-checkpoint-2026-08-10`).

This document is NOT a new aesthetic. It formalizes what already works.

---

## 1. COLOR SYSTEM

### Brand core

| Token | Hex | Usage |
|-------|-----|-------|
| `navy` | `0xFF07152D` | Identity. Headlines, outlines, nav active, offset shadows, primary deep |
| `blue` / `actionBlue` | `0xFF1264FF` | Primary action. CTAs, progress, chips, links, selected states |

### Surfaces

| Token | Hex | Usage |
|-------|-----|-------|
| `page` | `0xFFFBFCFF` | Page background (cool off-white) |
| `surface` / `card` | `0xFFFFFFFF` | Primary surface for cards, sheets, buttons |
| `panel` | `0xFFE1ECFF` | Light blue tint. Active pills, soft backgrounds |
| `panelLight` | `0xFFF0F5FF` | Lighter tint. Elevated surface, ink wash |

### Text

| Token | Hex | Usage |
|-------|-----|-------|
| `textPrimary` / `navy` | `0xFF07152D` | Primary text, headlines |
| `textSecondary` / `muted` | `0xFF5E6C85` | Secondary text, body copy |
| `textMuted` | `0xFF718097` | Metadata, captions, labels |
| `textDim` | `0xFF929CAD` | Disabled, placeholder, dimmed |
| `textInverse` / `white` | `0xFFFFFFFF` | Text on dark surfaces |

### Lines

| Token | Hex | Usage |
|-------|-----|-------|
| `divider` | `0xFFDCE3EE` | Thin separators between list rows |
| `border` | `0xFFCBD3DE` | Standard stroke on outlined surfaces |
| `borderStrong` / `paleSlate` | `0xFF929CAD` | Strong stroke, disabled text |

### Semantic — race state

| Token | Hex | Usage |
|-------|-----|-------|
| `raceLive` / `blue` | `0xFF1264FF` | Active race state |
| `crewWaiting` / `warning` | `0xFFB17A43` | Waiting-for-crew state |
| `crewWaitingTint` / `amberTint` | `0xFFF4E7D8` | Crew-waiting background tint |
| `raceFinished` / `success` | `0xFF66816C` | Finished race state |

### Semantic — placement

| Token | Hex | Usage |
|-------|-----|-------|
| `position1` / `gold` | `0xFFC49A52` | 1st place |
| `position2` / `silver` | `0xFFA8A29A` | 2nd place |
| `position3` / `bronze` | `0xFFA97752` | 3rd place |

### Semantic — status

| Token | Hex | Usage |
|-------|-----|-------|
| `success` / `mint` | `0xFF66816C` | Success, finished, verified |
| `danger` | `0xFFB8665E` | Destructive, error |
| `warning` / `amber` | `0xFFB17A43` | Warning, crew-waiting |

### Avatar palette

| Token | Hex |
|-------|-----|
| `avatarTerracotta` | `0xFFBE7B54` |
| `avatarOchre` | `0xFFC79A44` |
| `avatarDustyBlue` | `0xFF5E82A8` |
| `avatarSage` | `0xFF6E8F6C` |

### Rule

No future screen may invent a new blue, gray, or navy. Use the tokens above.
If a new semantic color is needed, add it to `app_colors.dart` with a name
that describes its purpose, not its hex value.

---

## 2. TYPOGRAPHY SYSTEM

### Font family

**Manrope** (via `google_fonts`). Single family for all text.

### Roles

| Role | Token | Size | Weight | Height | Letter spacing | Usage |
|------|-------|------|--------|--------|----------------|-------|
| display | `displayLarge` | 48 | w900 | 1.02 | 0 | Hero numbers (rare) |
| display | `displayMedium` | 40 | w800 | 1.04 | 0 | Large stats |
| display | `displaySmall` | 34 | w800 | 1.08 | 0 | Onboarding headlines |
| pageTitle | `headlineLarge` | 31 | w800 | 1.10 | -0.5 | Screen titles ("Compete", "Verify", "Profile") |
| sectionTitle | `headlineMedium` | 24 | w800 | 1.15 | 0 | Section headers |
| cardTitle | `titleLarge` | 21 | w800 | 1.22 | 0 | Card titles |
| cardTitle | `titleMedium` | 17 | w700 | 1.28 | 0 | Row titles, compact card titles |
| body | `bodyLarge` | 17 | w500 | 1.50 | 0 | Primary body text |
| body | `bodyMedium` | 15 | w500 | 1.45 | 0 | Standard body text |
| body | `bodySmall` | 13 | w500 | 1.40 | 0 | Secondary body, summaries |
| metadata | `raceRowMeta` | 12 | w500 | 1.30 | 0 | Race row meta, muted info |
| label | `labelLarge` | 15 | w800 | 1.15 | 0 | Strong labels |
| label | `labelMedium` | 13 | w800 | 1.20 | 0 | Section kickers, badges |
| label | `labelSmall` | 11 | w700 | 1.20 | 0 | Nav labels, "See all", captions |
| button | `buttonLabel` | 15 | w900 | 1.05 | 0 | Button text |
| caption | `statusLabel` | 12 | w800 | 1.10 | 0 | Status badges |
| numeric/stat | `statLarge(size)` | varies | w800 | 1.00 | -0.5 | Tabular figures for rank/score/percent |
| numeric/stat | `placementLabel()` | 13 | w800 | 1.10 | 0 | Placement labels ("1st", "2nd") |
| eyebrow | `eyebrow` | 12 | w800 | 1.20 | 0.8 | Uppercase section kickers |
| brand | `brandLabel` | 13 | w900 | 1.00 | 0 | Brand labels, member ID |

### Rule

Every `Text` widget should use a named role from `AppTextStyles`. Avoid
inline `fontSize:` / `fontWeight:` overrides unless a one-off adjustment
is genuinely needed. The `statLarge` and `placementLabel` helpers use
tabular figures for numeric alignment.

---

## 3. SPACING SYSTEM

### Scale (derived from actual usage)

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4 | Tight gaps (icon-to-text, badge padding) |
| `sm` | 8 | Small gaps (between meta lines, chip spacing) |
| `md` | 12 | Standard gap (card padding, row spacing) |
| `lg` | 16 | Section gap (between sections within a screen) |
| `xl` | 20 | Large gap (header padding, featured card padding) |
| `xxl` | 24 | Extra-large gap (between major screen sections) |
| `xxxl` | 32 | Hero gap (between featured card and next section) |
| `pageHorizontal` | 22 | Standard horizontal page padding on all screens |

### Rule

Use `NuvoSpacing.*` tokens for all `SizedBox` and padding values. Avoid
raw numbers. The only exception is `1` for `Divider` height and values
inside component internals that are tightly coupled to a specific
component's geometry.

---

## 4. SHAPE SYSTEM

### Corner radius scale

| Token | Value | Usage |
|-------|-------|-------|
| `badge` | 10 | Small icon/number badges, position badges |
| `xs` / `sm` | 12 | Small surfaces, chips, quick-start tiles |
| `card` | 16 | List containers, summary rows, race rows |
| `md` | 18 | Medium surfaces, small buttons |
| `button` | 24 | Standard buttons |
| `lg` | 26 | Large cards, featured surfaces |
| `hero` | 32 | Hero cards, featured race card |
| `pill` | 999 | Pills, avatar rings, circular elements |

### Border widths

| Token | Width | Usage |
|-------|-------|-------|
| `divider` | 1 | Thin separator stroke |
| `quiet` / `subtle` | 1.25 | Standard outlined surface |
| `chip` | 1.5 | Chip border (blue at 45% alpha) |
| `selected` | 2 | Selected state border (blue) |
| `hero` / `action` / `brand` | 2 | Strong border (navy) for interactive surfaces |

### Rule

Use `NuvoRadii.*` and `NuvoBorders.*` tokens. The relationship between
radii is intentional: badges < cards < buttons < hero. Do not create
surfaces with arbitrary radii between these steps.

---

## 5. DEPTH / BORDER SYSTEM

Nuvo uses a distinctive hard-offset shadow style (navy, zero blur, positive
offset) on important interactive surfaces. This is NOT applied to everything.

### Depth levels

| Level | Shadow | Border | Usage |
|-------|--------|--------|-------|
| flat | none | `divider` (1px) | List containers, dividers |
| outlined | none | `quiet` (1.25px) | Standard outlined surfaces, quick-start tiles |
| soft | `softSubtle` | `quiet` | Sheets, docks (soft drop shadow) |
| selected | `hardSmall` (3,3) | `selected` (2px blue) | Selected nav items, selected chips |
| raised | `hardSmall` (3,3) | `hero` (2px navy) | Secondary buttons, small interactive surfaces |
| action | `hardMedium` (5,5) | `hero` (2px navy) | Primary buttons, standard interactive surfaces |
| hero | `hardLarge` (7,7) | `hero` (2px navy) | Featured race card, hero surfaces |

### Rule

- Flat and outlined surfaces: no shadow. Used for content containers.
- Raised/action/hero surfaces: hard-offset shadow + navy border. Used for
  interactive surfaces where the shadow communicates pressability.
- The offset direction (positive x and y) creates a "pushed-down" feel
  when pressed (the `PressableScale` widget translates the surface).
- Do NOT put hard-offset shadows on list rows, summary containers, or
  non-interactive surfaces. The shadow means "you can tap this."

---

## 6. ICONOGRAPHY

### Icon family

**Material Icons** (rounded variants). Single family for consistency.

### Standard sizes

| Size | Usage |
|------|-------|
| 11 | Inline stat icons (active races, streak) |
| 14 | Compact row icons |
| 16 | Section icons, inline status icons |
| 18 | Card icons, nav icons (dark mode) |
| 20 | Section header icons |
| 22 | Empty-state icons |
| 24 | Nav icons, large card icons |

### Icon containers

| Container | Size | Radius | Usage |
|-----------|------|--------|-------|
| Badge | 30-34 | `badge` (10) | Position badges, status badges |
| Small icon tile | 34 | `badge` (10) | Quick-start movement icons |
| Medium icon tile | 44 | `md` (18) | Row leading icons |
| Large icon tile | 52 | `md` (18) | Empty-state icons |

### Rule

Use rounded icon variants (`Icons.*_rounded`). Maintain consistent visual
weight by using the standard sizes above. Active/inactive treatment:
active = `blue` or `navy`, inactive = `textMuted` or `textDim`.

---

## 7. VISUAL HIERARCHY RULES

The screen should NOT give every piece of information equal visual weight.

### Level 1 — Primary action / primary moment

The single most important thing on the screen.

- **Color**: deep navy surface, electric blue accents
- **Typography**: `featuredRaceTitle` (20/w800), `headlineLarge` (31/w800)
- **Depth**: `hero` — hard-offset shadow (7,7) + 2px navy border
- **Composition**: large, full-width, prominent
- **Examples**: Featured race card, page title, primary CTA button

### Level 2 — Important content

Content the user came to see, but not the single most important thing.

- **Color**: surface white, navy text, blue accents
- **Typography**: `raceRowTitle` (15/w700), `titleMedium` (17/w700)
- **Depth**: `outlined` — 1.25px border, no shadow
- **Composition**: full-width rows, compact cards
- **Examples**: Race rows, summary rows, "Up next" card

### Level 3 — Supporting content

Content that provides context but isn't the main focus.

- **Color**: surface white, muted text, soft tints
- **Typography**: `raceRowMeta` (12/w500), `bodySmall` (13/w500)
- **Depth**: `flat` — 1px divider, no shadow
- **Composition**: compact rows, wrap layouts
- **Examples**: Quick-start tiles, "Also ready" rows, meta lines

### Level 4 — Metadata

Supplementary information that should not compete with primary content.

- **Color**: muted text, dim icons
- **Typography**: `labelSmall` (11/w700), `statusLabel` (12/w800)
- **Depth**: none
- **Composition**: inline labels, captions, nav labels
- **Examples**: "See all" links, nav labels, status pills, counts

---

## 8. COMPONENT VARIATION RULES

### Principle: DATA MODEL != VISUAL COMPONENT

A race is a single data object (`Race`). But it appears differently depending
on context and user intent. The presentation is chosen by the screen, not
by the data model.

### Race presentation variants

| Variant | Component | Context | Visual treatment |
|---------|-----------|---------|------------------|
| FEATURED | `NuvoFeaturedRaceCard` | Compete — the one loud surface | Navy surface, hero shadow, racer stack, rank, progress lane, CTA |
| ACTIVE ROW | `NuvoRaceRow` | Compete — "Your races" list | Position badge, title, racer count, opponent avatars, progress percent |
| WAITING | `NuvoWaitingCrewSummary` | Compete — waiting-for-crew section | Amber tint, crew-slot icon, empty dashed avatars, expandable |
| FINISHED SUMMARY | `NuvoFinishedSummary` | Compete — finished section | Green tint, result icon (crown/check), win count, expandable |
| FINISHED ROW | `NuvoFinishedRaceRow` | Compete — expanded finished list | Position badge, title, placement label (NOT progress percent) |
| VERIFY ITEM | `_UpNextCard` / `_AlsoReadyRow` | Verify — Ready segment | Action-oriented, "Start verification" CTA, camera/proof context |
| RECENT ACTIVITY | `_RecentProofRow` | Verify — Recent segment | Person + action + result, time-ago, status badge |
| PROFILE HISTORY | `_RaceHistoryRow` | Profile — race history | Timeline treatment, movement icon, rank, score, meta line |

### Rule

Do NOT create a single "RaceCard" component that tries to handle all
contexts. Each variant exists because it serves a different user intent.
The same race object can appear as a featured card on Compete, a verify
item on Verify, and a history row on Profile — each with a different
visual treatment appropriate to that screen's purpose.

---

## 9. COMPONENT LIBRARY

### Existing building blocks

#### Buttons
- `NuvoPrimaryButton` — navy border, blue fill, hard-offset shadow, pressable
- `NuvoOutlineButton` — navy border, white fill, small hard-offset shadow
- `NuvoIconButton` — circular, navy border, surface fill

#### Race product components (`nuvo_race_components.dart`)
- `NuvoRacePositionBadge` — placement badge (crown for 1st, number for others)
- `NuvoRacerStack` — avatar stack with empty crew slots
- `NuvoRaceProgressLane` — progress bar with score + distance-to-go
- `NuvoWaitingCrewSummary` — expandable waiting-for-crew section
- `NuvoFinishedSummary` — expandable finished section with result icon
- `NuvoQuickStart` — movement identity tile with target
- `NuvoFeaturedRaceCard` — the one loud "continue competing" surface
- `NuvoRaceRow` — active race row with position, racers, progress
- `NuvoFinishedRaceRow` — finished race row with placement (not progress)

#### Shared primitives
- `NuvoAvatar` — circular avatar with initials/photo, configurable ring
- `NuvoRaceLane` — progress bar with dot marker
- `NuvoIcon` — custom brand icons (crown, flag, etc.)
- `PressableScale` — tap-to-scale animation wrapper
- `NuvoErrorState` — error message + retry button
- `NuvoBottomNav` — floating dock navigation with Verify center action

#### Screen-specific components (not yet extracted)
- `_SegmentedControl` / `_SegmentTab` (Verify) — Ready/Completed/Recent
- `_UpNextCard` (Verify) — loud verification surface
- `_AlsoReadyRow` (Verify) — compact ready row
- `_RecentProofRow` (Verify) — recent activity row
- `_CompactHeader` (Compete) — title + summary + Start/Join
- `_CappedRaceList` (Compete) — capped list with See all/Show less
- `_RaceHistoryRow` (Profile) — history row with movement icon

### Extraction candidates (Phase 4 future work)

The following patterns appear across multiple screens and could be extracted
into shared components during the visual design phase:

- **NuvoSectionHeader** — kicker text + optional "See all" link (Compete, Verify)
- **NuvoListGroup** — bordered container with divided rows (Compete, Verify, Profile)
- **NuvoStatusPill** — small colored pill with icon + text (race state, verification)
- **NuvoEmptyState** — icon + title + body + CTA (Compete, Verify, Profile)

These should be extracted when the visual design phase needs them, not before.

---

## 10. FLUTTER TOKEN LAYER

### Source files

| File | Contents |
|------|----------|
| `lib/core/theme/app_colors.dart` | `NuvoColors` + `AppColors` — all color tokens |
| `lib/core/theme/app_text_styles.dart` | `AppTextStyles` — all text roles |
| `lib/core/theme/app_geometry.dart` | `NuvoSpacing`, `NuvoRadii`, `NuvoBorders` |
| `lib/core/theme/app_shadows.dart` | `AppShadows` — depth/shadow tokens |
| `lib/core/theme/nuvo_tokens.dart` | Legacy aliases + animation/avatar/layout tokens |

### Architecture

The token layer is a set of `abstract final class` definitions with static
const/getter members. No theme `InheritedWidget` is needed because all
tokens are compile-time constants. Screens and components reference tokens
directly (e.g., `NuvoColors.navy`, `NuvoSpacing.md`, `AppTextStyles.titleMedium`).

### Migration status

- **Compete** (`compete_screen_fixed.dart`): Fully migrated to tokens
- **Verify** (`move_screen.dart`): Partially migrated — still has inline
  `fontSize`, `BorderRadius.circular`, and `SizedBox` magic values
- **Profile** (`profile_screen.dart`): Partially migrated — still has
  inline `fontSize`, `BorderRadius.circular`, and `SizedBox` magic values
- **Race components** (`nuvo_race_components.dart`): Fully migrated
- **Bottom nav** (`bottom_nav.dart`): Fully migrated

### Remaining migration (Phase 7)

The Verify and Profile screens have 100+ and 60+ inline magic values
respectively. These should be migrated to tokens during Phase 7 (repair
current screens using the system). The migration is mechanical:
- `fontSize: 30` → use `AppTextStyles.headlineLarge.copyWith(fontSize: 30)`
  or a dedicated role
- `BorderRadius.circular(16)` → `BorderRadius.circular(NuvoRadii.card)`
- `SizedBox(height: 8)` → `SizedBox(height: NuvoSpacing.sm)`
- `EdgeInsets.symmetric(vertical: 10)` → use `NuvoSpacing` tokens

---

## 11. RULES FOR FUTURE CHANGES

1. **No new colors** without adding a semantic token to `app_colors.dart`
2. **No new font sizes** without checking if an existing role fits
3. **No raw spacing numbers** — use `NuvoSpacing.*`
4. **No raw radii** — use `NuvoRadii.*`
5. **No inline shadows** — use `AppShadows.*`
6. **Hard-offset shadows only on interactive surfaces** — never on passive content
7. **Data model != visual component** — choose presentation by context
8. **One loud surface per screen** — featured card / up-next card / hero
9. **Capped lists with See all** — never unbounded scrolling lists on tab screens
10. **Bottom padding via `NuvoBottomNav.bottomPadding(context)`** — never hardcoded
