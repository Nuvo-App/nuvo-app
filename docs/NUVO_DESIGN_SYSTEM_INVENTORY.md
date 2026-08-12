# Nuvo Design System Inventory — Phase 1

Implementation document, not marketing copy. Captures the current visual
vocabulary, identifies drift, and proposes the migration plan for Phase 1.

---

## 1. EXISTING FOUNDATIONS

### Colors (`lib/core/theme/app_colors.dart`)

**Centralized:**
- `NuvoColors.navy` (0xFF07152D) — identity, headlines, outlines, nav active
- `NuvoColors.blue` / `actionBlue` (0xFF1264FF) — primary action, progress, chips
- `NuvoColors.page` (0xFFFBFCFF) — page background
- `NuvoColors.surface` / `card` (0xFFFFFFFF) — primary surface
- `NuvoColors.panel` (0xFFE1ECFF) — soft blue tint, active pills
- `NuvoColors.panelLight` (0xFFF0F5FF) — lighter tint
- `NuvoColors.divider` (0xFFDCE3EE) — thin separators
- `NuvoColors.border` (0xFF07152D) — standard dark structural outline
- `NuvoColors.muted` (0xFF5E6C85) — secondary text
- `NuvoColors.textMuted` (0xFF718097) — tertiary text
- `NuvoColors.success` (0xFF66816C) — verified/completed
- `NuvoColors.warning` / `amber` (0xFFB17A43) — attention
- `NuvoColors.amberTint` (0xFFF4E7D8) — warning background
- `NuvoColors.danger` (0xFFB8665E) — destructive
- `NuvoColors.gold` (0xFFC49A52) — 1st place / leader
- `NuvoColors.silver` (0xFFA8A29A) — 2nd place
- `NuvoColors.bronze` (0xFFA97752) — 3rd place
- `NuvoColors.avatarPalette` — 4 muted avatar colors

**Aliases (legacy compat):** `blue2`, `blueInk`, `inkNavy`, `navy2`, `platinum`,
`pageIce`, `pageWarm`, `icyBlue`, `softBlue`, `lavenderRow`, `sectionBlue`,
`bluePale`, `blueSoft`, `navySoft`, `offsetGrey`, `mint`, `prize`. These are
stable and should not be removed, but new code should use the canonical names.

**`AppColors` abstract class** mirrors the canonical colors with semantic
names (`background`, `surface`, `primary`, `primaryDeep`, `textPrimary`, etc.).
Used inconsistently — some files use `NuvoColors`, some use `AppColors`.

### Typography (`lib/core/theme/app_text_styles.dart`)

**Family:** Manrope (via `google_fonts`). Single family throughout. No new font
dependency should be introduced.

**Scale:**
- `displayLarge` 48/w900 — unused in Compete
- `displayMedium` 40/w800 — unused in Compete
- `displaySmall` 34/w800 — unused in Compete
- `headlineLarge` 31/w800 — Compete header uses this with `.copyWith(fontSize: 30)`
- `headlineMedium` 24/w800 — used for empty state title, featured card title (with `.copyWith(fontSize: 20)`)
- `titleLarge` 21/w800 — unused in Compete
- `titleMedium` 17/w700 — race row title (with `.copyWith(fontSize: 15)`)
- `bodyLarge` 17/w500 — unused in Compete
- `bodyMedium` 15/w500 — empty state body
- `bodySmall` 13/w500 — meta lines, summary subtitles (with `.copyWith(fontSize: 12)`)
- `labelLarge` 15/w800 — unused in Compete
- `labelMedium` 13/w800 — Quick Start chip label (with `.copyWith(fontSize: 13)`)
- `labelSmall` 11/w700 — section kickers, "See all" links
- `buttonLabel` 15/w900 — button text
- `statusLabel` 12/w800 — unused in Compete
- `number(size, color, weight)` — tabular figures helper, underused
- `labelUppercase(size, color)` — eyebrow helper
- `eyebrow` — 12/w800 uppercase, unused in Compete

**Drift:** Compete repeatedly uses `.copyWith(fontSize: ...)` to override the
scale values. This is a sign that the scale doesn't have the right semantic
stops for race UI.

### Spacing

**No centralized scale.** Compete uses hardcoded values:
- `22` (page horizontal padding — repeated 3x)
- `16`, `24`, `10`, `8`, `6`, `12`, `14`, `20` (section gaps, paddings)
- `48` (loading vertical padding)

`NuvoBottomNav.bottomPadding(context)` is the only shared spacing helper.

### Radii (`lib/core/theme/app_geometry.dart`)

**Scale:** `xs=12`, `sm=12`, `md=18`, `button=24`, `lg=26`, `hero=32`, `pill=999`.
Note `xs` and `sm` are identical (12).

**Compete usage:** `24` (featured card), `16` (race list container, summary
row), `14` (Quick Start chip), `10` (index badge, icon container). The `10`
and `14` values are off-scale.

### Strokes (`NuvoBorders`)

- `quiet` / `subtle` — 1.25px border color
- `selected` — 2px action blue
- `hero` / `action` / `brand` — 2px navy
- `chip` — 1.5px action blue at 0.45 alpha

**Outline rule:** use `NuvoColors.border` / `NuvoColors.navy` for structural
outlines on cards, fields, chips, and controls. Reserve `NuvoColors.divider`
for thin separators inside lists. Grey borders should not frame surfaces.

### Shadows (`lib/core/theme/app_shadows.dart`)

- `hardSmall` — 3,3 offset (compact controls)
- `hardMedium` — 5,5 offset (action cards, buttons)
- `hardLarge` — 7,7 offset (hero surfaces)
- `softSubtle` — ambient sheet shadow
- Legacy aliases: `hardShadow3/4/5`, `actionShadow`, `heroShadow`, `card`,
  `selectedShadow`, `dockShadow`, `sheetShadow`

**Compete usage:** `hardMedium` on the Continue Competing card. No other
shadows. This is correct — the signature shadow is reserved.

---

## 2. EXISTING SHARED COMPONENTS

### Buttons (`nuvo_button.dart`)
- `NuvoPrimaryButton` — blue fill, navy border, hardMedium shadow, press offset
- `NuvoOutlineButton` / `NuvoSecondaryButton` — white fill, navy border, hardSmall
- `NuvoGhostButton` — transparent, no border
- `NuvoDangerButton` — danger fill
- `NuvoBlueButton` — alias of Primary
- `NuvoBackplateButton` — alias of Primary

**Status: GOOD. Reuse as-is.**

### Avatars (`nuvo_avatar.dart`)
- `NuvoAvatar` — circle, photo/initials fallback, deterministic color
- `NuvoCompetitorAvatar` — adds role outlines (currentUser=blue, leader=gold)
- `NuvoAvatarStack` — overlapping stack with +N overflow
- `NuvoAvatarSizes` — xs/sm/md/lg/xl/profile

**Status: GOOD. Reuse as-is. Underused in Compete.**

### Race track (`nuvo_shared_components.dart`)
- `NuvoRaceLane` — horizontal progress track, static, onDark variant, dot at
  progress position, success color at 100%

**Status: GOOD. Reuse as-is. Underused in Compete (only on featured card).**

### Icons (`nuvo_icons.dart`)
- Custom hand-drawn set: flag, crown, fire, trendUp, check, checkCircle, camera,
  hand, users, user, plus, lock, bolt, bell, close, arrow, back
- Rendered via CustomPainter, no SVG dependency

**Status: GOOD. Reuse as-is.**

### Other
- `PressableScale` — tap scale animation
- `NuvoErrorState` — friendly error with retry
- `NuvoBottomNav` — bottom navigation dock

**Status: GOOD. Reuse as-is.**

---

## 3. CURRENT HARDCODED DRIFT

### Compete screen (`compete_screen_fixed.dart`)

| Location | Value | Should be |
|---|---|---|
| Header padding | `fromLTRB(22, 22, 22, 0)` | `NuvoSpacing.pageHorizontal` + `NuvoSpacing.lg` |
| Header title | `fontSize: 30, letterSpacing: -0.8` | semantic style |
| Featured card padding | `all(20)` | `NuvoSpacing.lg` |
| Featured card radius | `24` | `NuvoRadii.lg` |
| Featured title | `fontSize: 20, height: 1.15` | semantic style |
| Race list container radius | `16` | `NuvoRadii.md` (18) or new `NuvoRadii.card` |
| Race row padding | `horizontal: 14, vertical: 12` | `NuvoSpacing.sm` + `NuvoSpacing.md` |
| Index badge | `30x30, radius: 10` | `NuvoSpacing.md` size, `NuvoRadii.sm` |
| Quick Start chip radius | `14` | `NuvoRadii.sm` (12) |
| Quick Start chip border | `1.25` | `NuvoBorders.quiet` |
| Quick Start icon container | `30x30, radius: 10` | shared with index badge |
| Section kicker | `letterSpacing: 0.8` | `AppTextStyles.eyebrow` |
| Summary icon container | `32x32, radius: 10` | shared pattern |

**Pattern:** Three different "small square icon/badge container" sizes (30, 30,
32) with two different radii (10, 10). Should be one shared pattern.

---

## 4. DUPLICATED CONCEPTS

### "Small square container with icon/number"
Appears 3x in Compete with near-identical structure:
1. Race row index badge (30x30, radius 10, panel bg)
2. Quick Start icon container (30x30, radius 10, panel bg, border)
3. Summary row icon container (32x32, radius 10, tinted bg)

### "Section kicker label"
`labelSmall.copyWith(color: textMuted, fontWeight: w800, letterSpacing: 0.8)`
repeated for "Your races", "Quick starts". This is exactly `AppTextStyles.eyebrow`.

### "Compact race row"
`_CompactRaceRow` is used in both `_CappedRaceList` and `_SummaryExpansionList`.
Same widget, same presentation — active races and finished races look identical.

### "Bordered surface container"
`Container(decoration: BoxDecoration(color: surface, borderRadius: 16, border: divider))`
repeated for race list, summary row, expansion list. No shared surface primitive.

---

## 5. COMPONENTS WORTH PRESERVING

- `NuvoPrimaryButton` / `NuvoOutlineButton` — solid, well-built
- `NuvoAvatar` / `NuvoCompetitorAvatar` / `NuvoAvatarStack` — good race vocabulary
- `NuvoRaceLane` — good progress track, underused
- `NuvoIcon` — unique hand-drawn identity
- `PressableScale` — good tactile feedback
- `NuvoErrorState` — good error pattern

---

## 6. COMPONENTS THAT SHOULD BE REPLACED

### `_CompactRaceRow` → `NuvoRaceRow` (product component)
Currently a generic list row. Should encode race state (active/finished) and
show progress + position, not just "N racers · X%".

### `_ContinueCompetingCard` → `NuvoFeaturedRaceCard` (product component)
Currently a navy rectangle with text. Should show competition: avatars, rank,
progress lane, distance-to-go.

### `_SummaryRow` (Waiting) → `NuvoWaitingCrewSummary` (product component)
Currently a generic row with group_add icon. Should structurally show missing
crew slots.

### `_SummaryRow` (Finished) → `NuvoFinishedSummary` (product component)
Currently a generic row with checkmark. Should emphasize placement/results.

### `_QuickStartChip` → `NuvoQuickStart` (product component)
Currently a generic bordered chip. Should lead with movement identity.

---

## 7. MIGRATION PLAN

1. **Extend foundations** — add semantic color aliases, spacing scale, stat
   typography, stroke tokens. Do NOT remove existing tokens.
2. **Build race product components** in a new file
   `lib/core/widgets/nuvo_race_components.dart`.
3. **Rebuild Compete** using the new components, preserving IA.
4. **Add focused tests** for components and Compete visual differentiation.
5. **Do NOT migrate other screens** in this phase.

---

## 8. PROPOSED FOUNDATION API

### Color additions (`NuvoColors`)
```dart
// Semantic aliases for race states (map to existing canonical colors)
static const Color crewWaiting = warning;      // amber — crew/incomplete
static const Color crewWaitingTint = amberTint;
static const Color raceLive = blue;            // active/live
static const Color raceFinished = success;     // completed
static const Color position1 = gold;           // 1st place
static const Color position2 = silver;         // 2nd place
static const Color position3 = bronze;         // 3rd place
```

### Spacing (`NuvoSpacing` in `app_geometry.dart`)
```dart
abstract final class NuvoSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double pageHorizontal = 22;  // existing Compete value
}
```

### Radius additions (`NuvoRadii`)
```dart
static const double card = 16;   // surfaces, list containers
static const double badge = 10;  // small icon/number containers
```

### Stroke additions (`NuvoBorders`)
```dart
static Border subtleDivider = Border.all(color: NuvoColors.divider, width: 1);
```

### Typography additions (`AppTextStyles`)
```dart
static TextStyle get sectionKicker => eyebrow;  // alias
static TextStyle statLarge(double size, {Color? color}) => number(size, color: color, weight: FontWeight.w800);
static TextStyle get raceRowTitle => titleMedium.copyWith(fontSize: 15);
static TextStyle get raceRowMeta => bodySmall.copyWith(fontSize: 12);
```

---

## 9. PROPOSED PRIMITIVE API

**No new generic primitives needed.** The existing button/avatar/icon/progress
primitives are sufficient. The gap is in race-specific product components.

---

## 10. PROPOSED RACE PRODUCT COMPONENTS

### `NuvoRacePositionBadge`
- **Product concept:** placement in a race (1st, 2nd, 3rd, Nth)
- **States:** 1st (gold), 2nd (silver), 3rd (bronze), Nth (neutral)
- **Why not a generic card:** understands ordinal color coding and visual weight

### `NuvoRacerStack`
- **Product concept:** the people in a race
- **States:** filled avatars, empty slots, overflow count
- **Why not a generic card:** understands that missing participants = waiting state

### `NuvoRaceProgressLane`
- **Product concept:** progress toward finish line with context
- **States:** active (blue dot), complete (success), dark variant
- **Wraps:** `NuvoRaceLane` + target/distance labels
- **Why not a generic card:** combines track + target into one race concept

### `NuvoWaitingCrewSummary`
- **Product concept:** race exists but crew is incomplete
- **States:** collapsed (count + empty slot icons), expanded (race rows)
- **Why not a generic card:** structurally shows empty slots, not just text

### `NuvoFinishedSummary`
- **Product concept:** race is over, results matter
- **States:** collapsed (count + placement emphasis), expanded (result rows)
- **Why not a generic card:** emphasizes placement, not progress

### `NuvoQuickStart`
- **Product concept:** start a specific movement race immediately
- **States:** movement identity + target
- **Why not a generic card:** leads with exercise identity, not a generic icon

### `NuvoFeaturedRaceCard`
- **Product concept:** the one race that matters most right now
- **States:** active competition with opponents
- **Why not a generic card:** shows avatars, rank, progress, distance-to-go
