# Widget & token cookbook — use the library, don't reinvent it

Practical "how do I…" recipes for Nuvo's shared UI. For the exhaustive token
tables (every hex, every radius) use [`../UI_STRUCTURE.md`](../UI_STRUCTURE.md);
for pattern rules (anatomy / forbidden) use
[`../NUVO_PATTERN_LIBRARY.md`](../NUVO_PATTERN_LIBRARY.md). This file is the
day-to-day reference.

**Rule: search `lib/core/widgets/` and `lib/core/theme/` before you build
anything.** A new one-off `Container` with hand-mixed colours is almost always
wrong.

---

## 1. Colour — `lib/core/theme/app_colors.dart`

### Semantic meaning is fixed

| Role | Token family | Means | Never means |
|---|---|---|---|
| **blue** | `NuvoColors.blue` / `actionBlue` | brand, primary action, neutral info, progress fill, "live" | success or failure |
| **green** | `NuvoColors.success*` | verified / finished / celebration / "you're ahead" | anything neutral |
| **red** | `NuvoColors.danger*` | rejected / failed / destructive / "you're behind" | a warning |
| **orange/gold** | `NuvoColors.warning*`, `goldWarn`, `gold` | needs attention, in-review, waiting-for-crew; `gold` also = 1st place | success |
| **tan** | `NuvoColors.accent*` | warm highlight, member-pass / premium surfaces | success/failure |
| **navy** | `NuvoColors.navy` | text, borders (the "ink edge"), nav active | a fill for large areas |

### Each semantic role has 6 stops

`base` (fill) · `Shadow` (darker same-hue, for the hard offset) · `Bright`
(glow/progress) · `Surface` (pale tint bg) · `Border` (mid tint) · `On` (text on
the surface tint).

```dart
// tinted "info" chip
Container(
  decoration: BoxDecoration(
    color: NuvoColors.successSurface,
    borderRadius: BorderRadius.circular(NuvoRadii.badge),
    border: Border.all(color: NuvoColors.successBorder),
  ),
  child: Text('Verified', style: TextStyle(color: NuvoColors.successOn)),
)
```

### Prefer the theme extension in new code

```dart
final roles = context.semanticColors;      // NuvoSemanticColors
roles.success.base / .surface / .border / .on / .shadow / .bright
roles.success.hardShadow()                 // List<BoxShadow> tinted to the role
```

### Avatars — deterministic, never random, never a gradient

```dart
NuvoAvatar(
  initials: user.initials,
  photoUrl: user.profilePhotoUrl,
  size: NuvoAvatarSizes.md,               // xs24 sm32 md44 lg56 xl72 profile96
  bgColor: nuvoAvatarColorFor(user.id),   // stable colour from the 8-hue palette
  textColor: NuvoColors.white,
)
```

### Forbidden

- `Color(0xFF…)` literals in a screen. Add a token if one is missing.
- `withOpacity` / `withValues(alpha:)` to invent a "lighter green" — use the
  role's `Surface`/`Border` stop.
- blue for a success/error signal; green/red for anything non-semantic.

---

## 2. Depth — `lib/core/theme/app_shadows.dart`

**A hard-offset shadow means "you can tap this."**

| Use | Token |
|---|---|
| button, small tappable card | `AppShadows.hardSmall` (navy, `Offset(3,3)`, 0 blur) |
| primary CTA, hero action | `AppShadows.hardMedium` (`Offset(5,5)`) |
| rare oversized hero surface | `AppShadows.hardLarge` (`Offset(7,7)`) |
| dialog / bottom sheet only | `AppShadows.softSubtle` |

**Content stays flat.** Leaderboards, podiums, progress cards, list rows,
standings, section sheets → navy 2px border, **no shadow**. If it isn't
tappable, it doesn't get a hard shadow.

---

## 3. Geometry — `lib/core/theme/app_geometry.dart`

```dart
NuvoRadii.badge  10   // number/icon badges
NuvoRadii.card   16   // list containers, grouped surfaces
NuvoRadii.md     18   // small buttons, chips
NuvoRadii.button 24   // standard button
NuvoRadii.lg     26   // outlined sheets
NuvoRadii.hero   32   // hero cards
NuvoRadii.pill   999

NuvoSpacing.xs4 sm8 md12 lg16 xl20 xxl24 xxxl32
NuvoSpacing.pageHorizontal 22   // standard screen side padding

NuvoBorders.hero   // Border.all(navy, 2)  — the signature ink edge
NuvoBorders.divider // Border.all(divider, 1)
```

---

## 4. Responsive — `lib/core/theme/nuvo_responsive.dart`

The app was authored at 390px logical width with fixed pixels. Scale anything
size-like so it holds on 320px → tablet.

```dart
height: context.rs(56),                         // px * clamped factor (0.90–1.18)
padding: context.rsInsets(const EdgeInsets.all(16)),
style: AppTextStyles.titleLarge.scaled(context), // font size tracks device
context.isCompactWidth   // width < 360
context.isLargeWidth     // width >= 600
```

- Text also scales for OS accessibility, clamped to `[0.85, 1.30]` by
  `NuvoTextScaleScope` (installed once in `app.dart`). Don't re-pin `TextScaler`
  anywhere.
- Fixed-height controls (`nuvo_button.dart`) only grow ≥430px wide and cap at
  1.10× — so 800×600 test surfaces keep exact designed heights.

---

## 5. Buttons — `lib/core/widgets/nuvo_button.dart`

**Every tier is filled + shadowed. There are no transparent buttons.** A bare
`Text` in a `GestureDetector` is not a button — use one of these.

| Widget | Look | Use for |
|---|---|---|
| `NuvoPrimaryButton` | blue fill, navy border, `hardMedium` | the ONE primary action on a screen |
| `NuvoOutlineButton` (`= NuvoSecondaryButton`) | white fill, navy border, `hardSmall` | secondary actions; `iconOnly: true` for a square icon button |
| `NuvoTertiaryButton` (`NuvoGhostButton` is an alias) | gray-100 fill, gray-300 border, `hardSmall` | low-emphasis ("Show less", "Skip") |
| `NuvoSuccessButton` | green tint (or `solid: true` = solid green) | confirm a positive action |
| `NuvoDangerButton` | red tint (or `solid: true`) | destructive confirm |
| `NuvoBackButton` | circular, navy border, `hardSmall`, `Semantics(label:'Back')` | manual back button — wire to `safePopOrGo` |
| `NuvoIconAction` | circular icon button, optional `badge` | header actions (settings, notifications) |

Common props: `label`, `onPressed` (null = disabled, drops the shadow),
`icon` / `leadingWidget`, `expand` (fill width), `small`, `loading`
(shows a spinner). `NuvoSuccess/DangerButton` also take `solid`.

```dart
NuvoPrimaryButton(label: 'Submit proof', icon: Icons.camera_alt_outlined,
  expand: true, onPressed: () => context.push('/race/$id/proof'))
```

**Labels auto-shrink, never truncate.** `_buttonContent` wraps the label in
`FittedBox(fit: BoxFit.scaleDown)`, so a narrow button scales the text down
instead of showing `Submit…`. Don't add your own `overflow: ellipsis` to a
button label; don't restructure a layout just to fit a label.

---

## 6. Empty states — `lib/core/widgets/nuvo_empty_state.dart`

**Never render a blank area or "Nothing here."** Every empty/zero state uses
`NuvoEmptyState` and tells the person exactly what to tap.

```dart
NuvoEmptyState(
  icon: Icons.flag_rounded,
  title: 'No races yet',
  body: 'Create one to set a finish line, then pull in your crew.',
  ctaLabel: 'Create a race',   onCta: () => context.push('/races/new'),
  secondaryLabel: 'Join with a code', onSecondary: () => context.push('/races/join'),
  accent: NuvoColors.blue,      // tints the icon tile (blue/success/warning/danger)
  align: TextAlign.start,       // .center for a full-screen state
  compact: true,                // smaller, for inline-in-a-section use
)
```

Used on: Compete, Move, Arena, Race Detail (board), Crew. Match the pattern.

---

## 7. Error states — `lib/core/widgets/nuvo_error_state.dart`

```dart
NuvoErrorState(
  message: "Couldn't load your races.",   // friendly — NEVER the raw backend/exception string
  onRetry: () => ref.read(xProvider.notifier).load(),
)
```

Show it when `error != null && data.isEmpty`. If you have stale data, keep
showing it and surface the error more quietly.

---

## 8. Leaderboard — `nuvo_podium.dart` + `nuvo_board_components.dart`

```dart
NuvoPodium(
  top: [ for (final (i, p) in serverRankedParticipants(race).take(3).indexed)
    NuvoPodiumEntry(
      rank: i + 1,                         // positional — ties render as 1,2,3 not 2,2
      name: p.userId == me ? 'You' : p.displayName,
      statLabel: raceProgressLabel(race, p),
      avatarSeedId: p.userId, photoUrl: p.profilePhotoUrl,
      isCurrentUser: p.userId == me,
    ) ],
  rest: outlinedSheetOfRows,               // ranks 4+ — a flat bordered sheet, no shadow
)
```

Podium is **flat** — avatars + placement badges, #1 raised. No pedestal blocks,
no shadows. Arena and Race Detail must render the **same** podium from the
**same** `serverRankedParticipants(race)` so "see board" and the race page match.

---

## 9. Race cards/rows — `nuvo_race_components.dart`

| Widget | Use |
|---|---|
| `NuvoFeaturedRaceCard` | the one loud "continue this race" card on Compete |
| `NuvoRaceRow` | a row in a capped list of active races |
| `NuvoFinishedRaceRow` | a row in the finished-races list |
| `RacePeople` | overlapping avatar stack + "+N" |
| `NuvoWaitingCrewSummary` / `NuvoFinishedSummary` | collapsible summary sections |

All take formatted strings from `race_display.dart` — don't format progress/rank
inline.

---

## 10. Clipped-corner fix (outlined containers)

`Container(decoration: border, clipBehavior: Clip.antiAlias)` **clips the outer
half of the border at each rounded corner** — the corners look chewed off.

```dart
// WRONG — corners clipped
Container(
  decoration: BoxDecoration(border: NuvoBorders.hero, borderRadius: r),
  clipBehavior: Clip.antiAlias,
  child: rows,
)

// RIGHT — border outside, clip the child inside it
Container(
  decoration: BoxDecoration(color: surface, border: NuvoBorders.hero, borderRadius: r),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(radius - 2),   // inset by the border width
    child: rows,
  ),
)
```

Several screens have a local `_OutlinedSheet` doing exactly this. Reuse that
pattern for any bordered container whose children need clipping (rounded row
lists, images).

---

## 11. Typography — `lib/core/theme/app_text_styles.dart`

Use the named roles; never `GoogleFonts.manrope(...)` or a raw `TextStyle` with
a font size directly.

`displayLarge/Medium/Small` · `headlineLarge/Medium` · `titleLarge/Medium` ·
`bodyLarge/Medium/Small` · `labelLarge/Medium/Small` · `buttonLabel` ·
`screenTitle` · `sectionTitle` · `eyebrow` · `raceRowTitle` · `raceRowMeta` ·
`number(...)` / `statLarge(...)` / `placementLabel(...)` for numerals.

```dart
Text('Compete', style: AppTextStyles.screenTitle)
Text(label, style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted))
```

---

## 12. Navigation helper — `lib/core/navigation/nuvo_navigation.dart`

```dart
safePopOrGo(context, '/arena')   // pop if there's a stack, else go to fallback
```

Use it in **every** manually-placed back button. A bare `context.pop()` crashes
on a deep-linked screen with nothing to pop. Full verb rules:
[`../NAVIGATION_MAP.md`](../NAVIGATION_MAP.md) §4.
