# Nuvo UI Reference — exact tokens & patterns

No file lists — just the numbers and rules.

---

## Color tokens

### Brand core (`NuvoColors`)

| Token | Hex | Use |
|---|---|---|
| `navy` / `inkNavy` / `border` | `#07152D` | Headlines, outlines, nav active, dark surfaces |
| `blue` / `actionBlue` / `royalBlue` | `#1264FF` | Primary action, progress, chips, CTA |
| `blueLight` | `#E1ECFF` | Light blue tint |
| `orange` | `#FF6B21` | CTA accent, accent shadows only |

### Page & surfaces

| Token | Hex | Use |
|---|---|---|
| `page` / `pageIce` / `background` | `#FBFCFF` | Main page background |
| `surface` / `card` / `white` | `#FFFFFF` | Cards, interactive surfaces |
| `panel` / `softBlue` | `#E1ECFF` | Active pills, "you" row highlight |
| `panelLight` / `icyBlue` / `inkWash` | `#F0F5FF` | Lighter tint |
| `platinum` | `#EFF3FA` | Legacy alias |
| `trackBg` / `divider` | `#DCE3EE` | Thin separators, tracks |

### Semantic

| Token | Hex | Use |
|---|---|---|
| `success` / `mint` / `raceFinished` | `#66816C` | Finished, verified, completed |
| `danger` | `#B8665E` | Destructive |
| `warning` / `amber` | `#B17A43` | Attention, crew waiting |
| `amberTint` / `crewWaitingTint` | `#FFF4E7D8` | Warning background |
| `gold` | `#C49A52` | 1st place / leader (legacy `NuvoColors`) |
| `brightGold` | `#FACC15` | Bright gold accent |
| `silver` | `#A8A29A` | 2nd place (legacy `NuvoColors`) |
| `bronze` | `#A97752` | 3rd place (legacy `NuvoColors`) |
| `muted` | `#5E6C85` | Secondary text |
| `textMuted` | `#718097` | Tertiary text |
| `textDim` | `#929CAD` | Disabled / locked text |
| `paleSlate` | `#929CAD` | Disabled state |
| `disabledSurface` | `#EEF1F5` | Disabled fill |
| `disabledText` | `#929CAD` | Disabled text |

### `NuvoTokens` semantic overrides

| Token | Hex | Use |
|---|---|---|
| `gold` | `#F6B73C` | 1st place (Competition Ring) |
| `silver` | `#AEB7C7` | 2nd place (Competition Ring) |
| `bronze` | `#B67A44` | 3rd place (Competition Ring) |
| `green` | `#23B26D` | Finished / verified |
| `red` | `#F04F59` | Passed by opponent, recording, warning |
| `orange` | `#FF8C3A` | Almost finished |

### Grays (`NuvoTokens`)

| Token | Hex |
|---|---|
| `gray900` | `#1E1E22` |
| `gray800` | `#34363C` |
| `gray700` | `#545861` |
| `gray600` | `#6E727B` |
| `gray500` | `#8F949E` |
| `gray400` | `#B8BDC7` |
| `gray300` | `#D9DDE3` |
| `gray200` | `#EBEEF2` |
| `gray100` | `#F4F6F8` |

### Avatar palette

| Token | Hex |
|---|---|
| `avatarTerracotta` | `#BE7B54` |
| `avatarOchre` | `#C79A44` |
| `avatarDustyBlue` | `#5E82A8` |
| `avatarSage` | `#6E8F6C` |

---

## Typography

- **Font**: Manrope (via `google_fonts`)
- **Tabular figures** used for numbers

### `AppTextStyles` scale

| Style | Size | Weight | Height | Default color | Notes |
|---|---|---|---|---|---|
| `displayLarge` | 48 | w900 | 1.02 | textPrimary | |
| `displayMedium` | 40 | w800 | 1.04 | textPrimary | |
| `displaySmall` | 34 | w800 | 1.08 | textPrimary | |
| `headlineLarge` | 31 | w800 | 1.10 | textPrimary | |
| `headlineMedium` | 24 | w800 | 1.15 | textPrimary | |
| `titleLarge` | 21 | w800 | 1.22 | textPrimary | |
| `titleMedium` | 17 | w700 | 1.28 | textPrimary | |
| `bodyLarge` | 17 | w500 | 1.5 | textPrimary | |
| `bodyMedium` | 15 | w500 | 1.45 | textPrimary | |
| `bodySmall` | 13 | w500 | 1.4 | textSecondary | |
| `labelLarge` | 15 | w800 | 1.15 | textPrimary | |
| `labelMedium` | 13 | w800 | 1.2 | textPrimary | |
| `labelSmall` | 11 | w700 | 1.2 | textMuted | |
| `buttonLabel` | 15 | w900 | 1.05 | textPrimary | Button text |
| `statusLabel` | 12 | w800 | 1.1 | textMuted | |
| `eyebrow` / `sectionKicker` | 12 | w800 | — | textMuted | `letterSpacing: 0.8`, uppercase |
| `sectionTitle` | 14 | w700 | 1.2 | navy | |
| `screenTitle` | 30 | w800 | 1.10 | navy | `letterSpacing: -0.8` |
| `raceRowTitle` | 15 | w700 | 1.25 | textPrimary | |
| `raceRowMeta` | 12 | w500 | 1.3 | textMuted | |
| `featuredRaceTitle` | 20 | w800 | 1.15 | white | |

### `NuvoTokens` type constants

| Token | Value |
|---|---|
| `type40` | 40 |
| `type32` | 32 |
| `type28` | 28 |
| `type24` | 24 |
| `type20` | 20 |
| `type18` | 18 |
| `type16` | 16 |
| `type14` | 14 |
| `type12` | 12 |

### Weights

| Token | Value |
|---|---|
| `weightBold` | w700 |
| `weightSemiBold` | w600 |
| `weightMedium` | w500 |
| `weightRegular` | w400 |

---

## Spacing

### `NuvoTokens` spacing

| Token | Value |
|---|---|
| `space4` | 4 |
| `space8` | 8 |
| `space12` | 12 |
| `space16` | 16 |
| `space24` | 24 |
| `space32` | 32 |
| `space48` | 48 |
| `space64` | 64 |
| `margin` | 24 |
| `cardGap` | 16 |
| `sectionGap` | 32 |

### `NuvoSpacing`

| Token | Value |
|---|---|
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `lg` | 16 |
| `xl` | 20 |
| `xxl` | 24 |
| `xxxl` | 32 |
| `pageHorizontal` | 22 |

---

## Radii

### `NuvoRadii`

| Token | Value | Use |
|---|---|---|
| `xs` | 12 | |
| `sm` | 12 | |
| `md` | 18 | Inputs, small buttons, modals, snackbar |
| `button` | 24 | Buttons |
| `lg` | 26 | Cards, surfaces |
| `hero` | 32 | Hero cards |
| `pill` | 999 | Pills, chips, avatars |
| `badge` | 10 | Small icon/number containers |
| `card` | 16 | Lists, summary rows, surfaces |

### `NuvoTokens` radii aliases

| Token | Resolved value |
|---|---|
| `radius12` | 12 |
| `radius18` | 18 (`NuvoRadii.md`) |
| `radius20` | 20 |
| `radius24` | 24 (`NuvoRadii.button`) |
| `radius26` | 26 (`NuvoRadii.lg`) |
| `radius28` | 28 |
| `radius32` | 32 (`NuvoRadii.hero`) |
| `radiusPill` | 999 |

### Material theme radii

| Element | Radius |
|---|---|
| Card | `NuvoRadii.lg` = 26 |
| Filled / Outlined button | `NuvoRadii.button` = 24 |
| Text button | `NuvoRadii.md` = 18 |
| Input | `NuvoRadii.md` = 18 |
| Snackbar | `NuvoRadii.md` = 18 |
| Bottom sheet (top) | 28 |
| Dialog | `NuvoRadii.lg` = 26 |
| Chip | `NuvoRadii.pill` = 999 |

---

## Borders / outlines

### `NuvoBorders`

| Token | Color | Width | Hex |
|---|---|---|---|
| `quiet` / `subtle` | `NuvoColors.border` | 1.25 | `#07152D` |
| `selected` | `NuvoColors.actionBlue` | 2 | `#1264FF` |
| `hero` / `action` / `brand` | `NuvoColors.navy` | 2 | `#07152D` |
| `chip` | `NuvoColors.actionBlue` at 0.45 alpha | 1.5 | `#1264FF` 45% |
| `subtleDivider` | `NuvoColors.divider` | 1 | `#DCE3EE` |

### `NuvoTokens` border constants

| Token | Value |
|---|---|
| `borderColor` | `NuvoColors.border` = `#07152D` |
| `borderWidth` | 1.25 |
| `borderInkWidth` | 2 |
| `borderInk` | `NuvoBorders.brand` (2px navy) |
| `borderAction` | `NuvoBorders.action` (2px navy) |

### Theme outline defaults

| Element | Border |
|---|---|
| Card | `NuvoColors.border`, 1px |
| Outlined button | `NuvoColors.navy`, 2px |
| Chip | `NuvoColors.border`, 1.25px |
| Input enabled | `NuvoColors.border`, 1px |
| Input focused | `NuvoColors.blue`, 2px |
| Input error | `NuvoColors.danger`, 1px |
| Dialog | `NuvoColors.border`, 1px |
| Bottom sheet | `NuvoColors.border`, 1px |

---

## Shadows

### Hard offset (`AppShadows`)

| Token | Color | Blur | Offset | Use |
|---|---|---|---|---|
| `hardSmall` | navy `#07152D` | 0 | (3, 3) | Compact controls |
| `hardMedium` | navy | 0 | (5, 5) | Buttons, action cards |
| `hardLarge` | navy | 0 | (7, 7) | Hero surfaces |
| `hardMediumOrange` | orange `#FF6B21` | 0 | (5, 5) | Orange CTA |
| `hardLargeOrange` | orange | 0 | (7, 7) | Orange hero CTA |

### Soft / ambient (`AppShadows`)

| Token | Color | Blur | Spread | Offset |
|---|---|---|---|---|
| `softSubtle` | navy `#07152D` at 0.08 | 18 | -10 | (0, 8) |
| `brandGlow` | blue at 0.10 × intensity | 14 × intensity | — | (0, 4) |
| `victoryGlow` | mint at 0.12 × intensity | 14 × intensity | — | (0, 4) |
| `hotGlow` | warning at 0.10 × intensity | 12 × intensity | — | (0, 3) |

### `NuvoTokens` shadow aliases

| Token | Maps to |
|---|---|
| `hardSmall` | `AppShadows.hardSmall` |
| `hardMedium` | `AppShadows.hardMedium` |
| `hardLarge` | `AppShadows.hardLarge` |
| `hardShadow3` | `hardSmall` |
| `hardShadow4` | `hardMedium` |
| `hardShadow5` | `hardLarge` |
| `hardShadow` | `hardMedium` |
| `shadow1` | `hardShadow3` |
| `shadow2` | Soft sheet (0, 8) blur 24 |
| `shadow3` | Soft nav (0, 12) blur 32 |

---

## Animation

| Token | Value |
|---|---|
| `duration220` | 220ms |
| `duration320` | 320ms |
| `curveEase` | `Curves.easeOutCubic` |
| `curveSpring` | `Curves.easeOutBack` |

### Pattern motion rules

| Type | Duration | Curve | Use |
|---|---|---|---|
| Micro | 220ms | ease | Button presses, pill switches |
| Object | 320ms | spring | Ring expansion, row entrance, count-up |
| Page | 400ms | ease | Nav transitions |

- Ring progress animates from previous value.
- Numbers count, do not jump.
- Leaderboard rows cascade with 40ms stagger.
- Avatars scale on selection with spring.

---

## Component specs

### `CompetitionRing`

Source: `lib/core/widgets/competition_ring.dart`

| Size | Diameter | Ring thickness | Marker size | Avatar size | Label size |
|---|---|---|---|---|---|
| `small` | 96 | 5 | 18 | 18 | 12 |
| `medium` | 160 | 8 | 28 | 28 | 14 |
| `large` | 240 | 10 | 40 | 40 | 18 |

**Colors**
- Track: `NuvoTokens.inkNavy` (`#07152D`)
- Progress arc: `NuvoTokens.actionBlue` (`#1264FF`), thickness = 0.72 × ring thickness
- Leading dot: blue with white core
- Marker ring:
  - 1st = `gold` `#F6B73C`
  - 2nd = `silver` `#AEB7C7`
  - 3rd = `bronze` `#B67A44`
  - Current user = `royalBlue` `#1264FF`
  - Everyone else = `borderColor` `#07152D` at width 2
- Center label: navy, bold, 2 lines max
- Ticks: 60 around track, alpha 0.18, stroke 1.2

**Layout**
- Marker padding = `markerSize × 0.35`
- Usable diameter = `diameter - 2 × markerPadding`
- Initials font = `markerSize × 0.42`
- Animation duration default = 320ms

### `NuvoPrimaryButton`

| State | Height | Radius | Fill | Border | Shadow | Text |
|---|---|---|---|---|---|---|
| Default | 56 | `NuvoRadii.button` = 24 | `actionBlue` `#1264FF` | `navy` 2px | `hardMedium` (5,5) navy | white 15/w900 |
| Small | 46 | `NuvoRadii.md` = 18 | `actionBlue` | `navy` 2px | `hardMedium` | white |
| Disabled | 56/46 | — | `disabledSurface` `#EEF1F5` | `border` 2px | none | `disabledText` `#929CAD` |
| Flat | — | — | `actionBlue` | `navy` | none or `softSubtle` if `subtleLift` | white |

- Horizontal padding: 24
- Press offset: 4px down/right
- Press duration: 90ms
- Disabled opacity: 0.58
- Icon size: 17
- Icon gap: 8
- Leading widget gap: 9
- Loading: 19×19 spinner, stroke 2

### `NuvoOutlineButton` / `NuvoSecondaryButton`

| State | Height | Radius | Fill | Border | Shadow | Text |
|---|---|---|---|---|---|---|
| Default | 56 | `NuvoRadii.button` = 24 | `surface` white | `navy` 2px | `hardSmall` (3,3) navy | `navy` 15/w900 |
| Small | 46 | `NuvoRadii.md` = 18 | white | `navy` 2px | `hardSmall` | navy |
| Disabled | — | — | `surface` | `border` | none | `border` |
| Flat | — | — | `surface` | `navy` | none | navy |

- `iconOnly`: centered 22×22 icon

### `NuvoGhostButton`

- Height: 50 (default), 42 (small)
- Radius: `button` = 24 (default), `md` = 18 (small)
- Fill: transparent
- Border: none
- Text: navy 15/w900

### `NuvoDangerButton`

- Height: 54 (default), 44 (small)
- Radius: `button` = 24 / `md` = 18
- Fill: `danger` at 9% alpha
- Border: `danger` 2px
- Text: `danger` 15/w900

### `NuvoBackButton`

- 46×46 circle
- Fill: white
- Border: `navy` 2px
- Shadow: `hardSmall` (3,3)
- Icon: `Icons.arrow_back_rounded`, size 20, color navy

### `NuvoIconAction`

- 42×42 circle
- Fill: `panelLight` `#F0F5FF`
- Border: `border` 1.25px
- Icon: 19, color `navy` or custom
- Badge: 7×7 coral circle with white 1.2px border

### `NuvoAvatar`

Sizes (`NuvoAvatarSizes`):

| Size | Value |
|---|---|
| `xs` | 24 |
| `sm` | 32 |
| `md` | 44 |
| `lg` | 56 |
| `xl` | 72 |
| `profile` | 96 |

- Shape: circle
- Background: `panel` `#E1ECFF` or `bgColor`
- Border: optional, default width 1.5
- Text: initials, font = `size × 0.36` clamped 7–20, weight w800, color navy/white
- Fallback priority: `localBytes` > `photoUrl` > `photoAsset` > initials

### `NuvoCompetitorAvatar`

- Role borders:
  - `currentUser`: `blue` 3px
  - `leader`: `gold` 2px (`NuvoColors.gold` `#C49A52`)
  - `standard`: `white` 2px
- Status dot: `blue` circle, `size × 0.22` clamped 7–10, white 1.5px border

### `NuvoAvatarStack`

- Default size: 36
- Overlap: `size × 0.32` clamped 8–13
- Max visible: 4 (overflow shown as `+N`)
- Border color: white
- Ring width: 1.5 (xs), 2.0 (larger)
- Overflow bubble: `panel` fill, white border, navy text, font `size × 0.3` clamped 6–10

### `NuvoCard` / `NuvoBentoCard`

| Token | Default |
|---|---|
| Padding | 20 (`BentoCard` 16) |
| Radius | `NuvoRadii.lg` = 26 |
| Fill | `card` white |
| Border | `border` 2px |
| Shadow | `hardMedium` (5,5) navy if `elevated` |
| Press scale | 0.985 |

### `NuvoChip`

- Padding: 14 horizontal, 7 vertical
- Radius: 100 (pill)
- Border: 2px
  - Selected: accent color (default `actionBlue`)
  - Unselected: `NuvoColors.border`
- Background:
  - Selected: `panel` `#E1ECFF`
  - Unselected: `white`
- Text: `labelMedium` 13/w800
- Color:
  - Selected: accent
  - Unselected: `navy`
- Duration: 180ms

---

## Pattern library (exact rules)

### 01 Hero

- Height: 200–260px on iPhone; max 40% of screen
- Background: navy gradient or solid blue
- No borders, no shadows, no cards inside
- One interactive element besides profile/notification
- Greeting (first name), 1 status indicator, 1 primary action

### 02 Live Race card

- Surface: elevated card on background
- Radius: 24
- Padding: 22 all sides
- Internal gaps: 16 vertical
- Competition Ring: medium (160) centered

### 03 Competition Ring

- Track: gray200 `#EBEEF2`
- Progress arc: royal blue `#1264FF`
- Start: 12 o'clock, clockwise
- Marker sizes: small 18, medium 28, large 40
- Ring thickness: small 5, medium 8, large 10
- Marker ring colors:
  - 1st gold, 2nd silver, 3rd bronze
  - Current user outside top 3 = blue
  - Others = border color
- Center label: bold navy, 1–2 lines
- Max 6 markers on small ring

### 04 Leaderboard Row

- Full width, 52px height
- Horizontal padding: 24
- Rank pill: 28px circle or bare number
- Avatar: 32px
- Progress: right-aligned, monospaced
- Top 3 ranks: gold/silver/bronze rank color
- Row backgrounds stay neutral

### 05 Race Rail

- Fixed width: 260
- Height: 130–150
- Gap between rails: 12
- Radius: 20
- Progress strip at bottom: 3px

### 06 Verification

- Camera fills safe area
- UI overlays bottom/edges
- Instruction: display size, white
- Counters: body size, white 70% opacity
- No live rep progress bars

### 07 Crew

- Avatar size: 48 default, 40 dense
- Stack overlap: -8px
- Names below, 1 line
- Invite: circular avatar with "+"

### 08 Timeline

- Left rail: 24
- Right: actor, action, object
- Time: meta color, 12
- Row height: 44–52
- No cards, no dividers between items

### 09 Profile

- Avatar: 80
- Stats: horizontal, equal width, no icons
- Recent races: Race Rail pattern
- Settings: list rows, not cards

### 10 Section Header

- Height: 40
- Title: section size (18 semibold), navy, left
- Action: body size (14–16), blue, right
- Optional divider: 1px border color

### 11 Status Pill

- Height: 22
- Horizontal padding: 8
- Radius: 99
- Text: label size (12), semibold
- Background: semantic color at 10% opacity
- Text color: semantic color full

| State | Color |
|---|---|
| Live | blue |
| Finished | green |
| Solo | gray |
| Waiting | orange |

### 12 Buttons (pattern)

- Primary: 52 height, royal blue fill, white 16/w600, 20px icon leading
- Secondary: same height, transparent, royal blue text, 1px royal blue border
- Danger: red text, transparent
- Max 1 primary button per module
- No shadows on buttons

### 13 Surfaces

| Surface | Color token | Use |
|---|---|---|
| Background | `NuvoTokens.background` | 70% of screen |
| Elevated | `NuvoTokens.card` | Hero modules, primary objects |
| Overlay | navy at 85% opacity | Dialogs, sheets, camera overlays |
| Navigation | `NuvoTokens.card` | Floating nav |

### 14 Typography hierarchy

| Level | Size | Weight | Use |
|---|---|---|---|
| Display | 32 | Bold | Ring value, rank hero |
| Page | 28 | Bold | Screen titles, greeting |
| Section | 18 | Semibold | Headers, race titles |
| Body | 14–16 | Regular | Context, leaderboard names |
| Label | 12 | Semibold | Pills, timestamps, meta |

- Line height: 1.2 display, 1.4 body
- Colors: navy primary, gray700 secondary, gray500 meta

### 15 Spacing system

- Screen margin: 24
- Tight: 8
- Standard: 12, 16
- Section break: 24, 32
- Major: 48, 64

---

## Product language (use in copy and docs)

Use: **race, crew, proof, progress, leaderboard, start line, finish line, submit proof, pull in your crew, arena, member pass, AI Motion Proof, invite code**

Never use: challenge, event, journey, unlock, discover, coming soon, needs setup, betting, gambling, crypto, payment, payout, sponsor, investor, SMS, Twilio, Firebase, Supabase.
