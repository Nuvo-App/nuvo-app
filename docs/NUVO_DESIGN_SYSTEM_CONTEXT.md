# Nuvo Current Design System

This document records the UI that is currently wired into the app, based on
the active route graph and the widgets those routes actually build. It is an
implementation reference for future UI work, especially onboarding. It is not
a redesign proposal.

Audit scope: the current Flutter codebase as of 2026-09-21. The route source
is [`lib/app/router.dart`](../lib/app/router.dart). Important active paths are:

| Product surface | Active route | Actual screen |
|---|---|---|
| Arena | `/arena` | `ArenaScreen`, exported by `arena_screen.dart` from `arena_screen_fixed.dart` |
| Compete | `/compete` | `CompeteScreen` from `compete_screen_fixed.dart` |
| Verify tab | `/move` | `MoveScreen` |
| Crew tab | `/pass` | `PassScreen`, despite the file name, with `NuvoBottomNav` label `Crew` |
| Profile | `/profile` | `ProfileScreen` |
| Race detail / leaderboard | `/race/:id` | `RaceDetailScreen` |
| Submit proof | `/race/:id/proof` | `SubmitProofScreen` |
| Camera verification | `/race/:id/proof/ai-motion` | `AiMotionProofScreen` with mobile/web conditional implementation |
| Race creation | `/races/new` | `RaceComposerScreen` |
| Teach Nuvo | `/races/teach` | `TeachMovementScreen` |
| Edit profile | `/profile/edit` | `EditProfileScreen` |

`create_race_screen.dart` is still imported for `RaceCreatePrefill`, but
`CreateRaceScreen` is not the current `/races/new` page. `track_view_screen.dart`
is also not the active Arena route. `arena_screen.dart` and
`compete_screen.dart` are compatibility exports, not separate screen designs.

## Visual identity

Nuvo's current UI is a bright, physical-feeling race interface:

- The canvas is a soft near-white, `NuvoColors.page`.
- Navy is the structural ink for type, outlines, navigation, icons, and dark
  verification surfaces.
- Bright action blue is reserved for primary action, progress, active state,
  and selected controls.
- Surfaces are predominantly white with visible structural outlines.
- The signature depth treatment is a hard, zero-blur offset shadow rather than
  a conventional soft Material elevation.
- Race-specific color carries meaning: green means finished or verified, red
  means failure or destructive action, amber means attention, and gold/silver/
  bronze communicate podium placement.
- The active screens are mostly flat light surfaces with selective physical
  controls. The current Arena hero is a white outlined card with a blue action
  footer, not a full-screen gradient hero.

The product language and information ownership remain defined by
[`docs/NUVO_PRODUCT_MODEL.md`](NUVO_PRODUCT_MODEL.md). In particular, the
leaderboard is the emotional center of a race, Verify owns proof entry, Crew
owns people, and Profile owns identity/history/settings.

## Color system

The primary color source is
[`lib/core/theme/app_colors.dart`](../lib/core/theme/app_colors.dart). The
`AppColors` class in the same file provides semantic aliases. `NuvoSemanticColors`
is the theme extension installed by `AppTheme.light()` and exposes role bundles
through `context.semanticColors`.

### Core tokens

| Role | Token | Value | Current use |
|---|---|---:|---|
| Structural ink | `NuvoColors.navy` / `inkNavy` | `#07152D` | Headings, outlines, dark surfaces, selected navigation, icons |
| Primary action | `NuvoColors.blue` / `actionBlue` | `#1264FF` | Primary buttons, active controls, progress, selected states |
| Page background | `NuvoColors.page` / `pageIce` | `#FBFCFF` | App canvas and shell background |
| Surface | `NuvoColors.surface` / `card` / `white` | `#FFFFFF` | Cards, controls, sheets, form fields |
| Blue panel | `NuvoColors.panel` | `#E1ECFF` | Selected rows, soft panels, active nav background |
| Light blue panel | `NuvoColors.panelLight` | `#F0F5FF` | Quiet tinted surfaces and lighter legacy aliases |
| Divider | `NuvoColors.divider` | `#DCE3EE` | List separators and quiet container edges |
| Secondary text | `NuvoColors.muted` | `#5E6C85` | Supporting copy and metadata |
| Tertiary text | `NuvoColors.textMuted` | `#718097` | Labels, quiet metadata, inactive navigation |
| Dim text | `NuvoColors.textDim` | `#929CAD` | Disabled or very low-emphasis text |

### Semantic role bundles

`NuvoSemanticColors.standard` in `app_colors.dart` groups each role into a
base fill, hard-shadow color, bright accent, tinted surface, border, and
on-surface text color.

| Role | Base | Shadow | Surface | Border | On-surface text |
|---|---|---|---|---|---|
| Neutral / brand | `NuvoColors.neutral` = blue `#1264FF` | `#003D71` | `#E1ECFF` | `#A9C8FF` | navy `#07152D` |
| Success | `#2ECC40` | `#008A43` | `#E7F8E9` | `#9EE0A6` | `#15602B` |
| Danger | `#E72025` | `#8B1917` | `#FCE8E8` | `#F1AFAF` | `#991A1A` |
| Warning | `#F69304` | `#F47603` | `#FBEEDC` | `#EFC996` | `#8A5210` |
| Warm accent | `#EAD0BB` | `#E0B48C` | `#F6EEE4` | `#E0B48C` | navy `#07152D` |

### Race and identity accents

- `NuvoColors.gold` `#E0A72E`, `silver` `#95A0B3`, and `bronze` `#B2703C`
  are used by `NuvoPodium`, `RacePlacement`, and leaderboard rank treatments.
- `NuvoColors.raceLive`, `raceFinished`, `crewWaiting`, and
  `crewWaitingTint` are semantic aliases for the active, finished, and waiting
  race states.
- `NuvoColors.avatarPalette` is the deterministic flat avatar palette used by
  `nuvo_avatar.dart`; it avoids gradients and broken-image states.
- `NuvoTokens` in
  [`lib/core/theme/nuvo_tokens.dart`](../lib/core/theme/nuvo_tokens.dart)
  exposes a parallel token surface and contains some duplicate podium/gray
  values. Existing shared widgets use both `NuvoColors` and `NuvoTokens`. New
  onboarding code should prefer the canonical semantic `NuvoColors` roles and
  the existing shared widget APIs rather than introducing another palette.

## Typography

The app uses Manrope throughout, loaded by `GoogleFonts.manrope()` in
[`lib/core/theme/app_text_styles.dart`](../lib/core/theme/app_text_styles.dart)
and installed globally by `AppTheme.light()`.

### Defined scale

| Style | Size | Weight | Line height | Tracking |
|---|---:|---:|---:|---:|
| `displayLarge` | 48 | 900 | 1.02 | 0 |
| `displayMedium` | 40 | 800 | 1.04 | 0 |
| `displaySmall` | 34 | 800 | 1.08 | 0 |
| `headlineLarge` | 31 | 800 | 1.10 | 0 |
| `headlineMedium` | 24 | 800 | 1.15 | 0 |
| `titleLarge` | 21 | 800 | 1.22 | 0 |
| `titleMedium` | 17 | 700 | 1.28 | 0 |
| `bodyLarge` | 17 | 500 | 1.50 | 0 |
| `bodyMedium` | 15 | 500 | 1.45 | 0 |
| `bodySmall` | 13 | 500 | 1.40 | 0 |
| `labelLarge` | 15 | 800 | 1.15 | 0 |
| `labelMedium` | 13 | 800 | 1.20 | 0 |
| `labelSmall` | 11 | 700 | 1.20 | 0 |
| `buttonLabel` | 15 | 900 | 1.05 | 0 |
| `statusLabel` | 12 | 800 | 1.10 | 0 |

Semantic styles used by current screens include:

- `screenTitle`: 30/w800, navy, 1.10 line height, `-0.8` tracking. Arena,
  Compete, Verify, Crew, and Profile use this tab-title register.
- `sectionTitle`: 14/w700 navy, 1.20 line height. Verify, Compete, and Crew
  use it for section labels.
- `raceRowTitle`: 15/w700, 1.25 line height.
- `raceRowMeta`: 12/w500, muted, 1.30 line height.
- `featuredRaceTitle`: 20/w800 white for a dark race surface.
- `number()` and `statLarge()` use tabular figures and tight line height for
  ranks, counts, and progress values.
- `eyebrow`, `sectionKicker`, and `labelUppercase()` are uppercase, tracked
  utility styles. They are used for compact status or progress labels, not as
  the default heading treatment for every section.

### Current heading hierarchy

1. Screen identity: `AppTextStyles.screenTitle`.
2. Deep-screen or major race title: `displaySmall` or a controlled
   `headlineLarge` override. `RaceDetailScreen._LiveRaceHeader` uses
   `displaySmall` with a responsive 32px size.
3. Major card title: `headlineLarge` or `headlineMedium`.
4. Section title: `sectionTitle` or a screen-private `titleMedium` section label.
5. Supporting copy: `bodyMedium` or `bodySmall` with `NuvoColors.muted`.
6. Metadata/status: `labelMedium`, `labelSmall`, `NuvoPill`, or a semantic
   role label.

There are deliberate screen-level overrides, especially in Arena, Race Detail,
and the composer. Treat them as local composition decisions, not new global
tokens.

## Layout & spacing

### Shared spacing tokens

`NuvoSpacing` in
[`lib/core/theme/app_geometry.dart`](../lib/core/theme/app_geometry.dart)
defines:

| Token | Value |
|---|---:|
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `lg` | 16 |
| `xl` | 20 |
| `xxl` | 24 |
| `xxxl` | 32 |
| `pageHorizontal` | 22 |

`NuvoTokens` also exposes 4/8/12/16/24/32/48/64 and layout values `margin=24`,
`cardGap=16`, `sectionGap=32`. Existing production screens still use a mix of
the two token surfaces and local values.

### Current page composition

- Main-shell tabs use `MainShell` and a single `Scaffold` with
  `extendBody: false`, `SafeArea(bottom: false, child: widget.child)`, and
  the shared `NuvoBottomNav`. The shell reserves the dock's actual height.
- Tab list content generally uses 20 or 22px horizontal margins and appends
  `NuvoBottomNav.bottomPadding(context)` to the scrollable content. That helper
  returns the dock's bottom gap plus a 24px section-sized breathing gap.
- Arena uses a 22px horizontal content margin and responsive density-based
  hero sizing. Verify and Compete use 22px tab margins. Crew, Profile, and
  Race Detail commonly use 18–20px margins.
- Standalone pushed pages use `SafeArea` directly. Composer and Edit Profile
  pin their primary action at the bottom inside a SafeArea-aware layout.
- Vertical rhythm is mostly 8/10/12/16/20/24/28/32px. A 4px token is used
  for tight label relationships.

### Responsive behavior

`NuvoResponsive` in
[`lib/core/theme/nuvo_responsive.dart`](../lib/core/theme/nuvo_responsive.dart)
uses a 390px baseline, clamps the layout factor to 0.90–1.18, and exposes:

- `context.rs(value)` and `context.rsInsets(...)` for size scaling.
- `isCompactWidth` below 360px and `isLargeWidth` at or above 600px.
- `nuvoDensity`, based on usable height after safe areas: compact below 700px,
  regular through 860px, and large above 860px.
- App-wide text scaling clamped between 0.85 and 1.30 by
  `NuvoTextScaleScope` in `app.dart`.

On large web viewports, `_webPreviewBuilder` in `app.dart` centers a maximum
430px phone column. Real mobile-sized viewports up to 600px fill normally.

Do not make a new onboarding layout assume a fixed 390px screen without using
these constraints.

## Borders & radii

`NuvoRadii` in `app_geometry.dart` currently defines:

| Token | Value | Typical meaning |
|---|---:|---|
| `xs`, `sm` | 12 | Small controls, compact surfaces |
| `md` | 18 | Standard cards and controls |
| `button` | 24 | Full-size buttons |
| `lg` | 26 | Cards, grouped surfaces |
| `hero` | 32 | Hero cards and prominent modules |
| `pill` | 999 | Pills and chips |
| `badge` | 10 | Small icon/rank tiles |
| `card` | 16 | List containers and compact grouped surfaces |

`NuvoBorders` defines:

- `quiet` / `subtle`: navy border at 1.25px.
- `selected`: action blue at 2px.
- `hero`, `action`, and `brand`: navy at 2px.
- `chip`: action blue at 1.5px with reduced alpha.
- `divider`: divider color at 1px.

The current shared button shell uses a 3px border by default, which is an
intentional physical-control construction. It should not be inferred from the
1.25px quiet surface border.

## Shadows

`AppShadows` in
[`lib/core/theme/app_shadows.dart`](../lib/core/theme/app_shadows.dart) is the
source for the current offset treatment:

| Token | Offset | Blur | Use |
|---|---:|---:|---|
| `hardSmall` | 3,3 | 0 | Compact controls, back buttons, small rows |
| `hardMedium` | 5,5 | 0 | Primary buttons, action cards |
| `hardLarge` | 7,7 | 0 | Hero cards and large race surfaces |
| `softSubtle` | 0,8 | 18 | Dock, sheets, rare ambient separation |

Pressed controls remove the shadow and translate down/right. This is implemented
by `_PhysicalButtonShell` in `nuvo_button.dart` and `PressableScale` in
[`lib/core/widgets/pressable_scale.dart`](../lib/core/widgets/pressable_scale.dart).
`NuvoHardOffset` in `nuvo_shared_components.dart` provides the same face-plus-
plate construction for compact cards.

Avoid generic Material elevation, blur, and soft drop shadows for ordinary
onboarding surfaces. `AppTheme` intentionally sets most card/dialog elevation
to zero and relies on the explicit Nuvo construction.

## Buttons

The reusable button architecture is in
[`lib/core/widgets/nuvo_button.dart`](../lib/core/widgets/nuvo_button.dart).

| Component | Default height | Small height | Fill | Edge/shadow | Intended role |
|---|---:|---:|---|---|---|
| `NuvoPrimaryButton` | 56 | 46 | action blue, disabled surface when disabled | navy 3px, hardMedium or hardSmall | One primary action |
| `NuvoOutlineButton` / `NuvoSecondaryButton` | 56 | 46 | white | navy 3px, hardSmall | Secondary action |
| `NuvoTertiaryButton` / `NuvoGhostButton` | 52 | 44 | gray100 | gray300 3px, no shadow | Lower-emphasis action |
| `NuvoSuccessButton` | 54 | 46 | success tint or solid success | semantic success border/shadow | Confirmed/verified completion |
| `NuvoDangerButton` | 54 | 44 | danger tint or solid danger | semantic danger border/shadow | Destructive action |
| `NuvoBackButton` | responsive 44–54 | — | white circle | navy 2px, hardSmall | Back navigation |
| `NuvoIconAction` | responsive 42–50 | — | white circle | navy 1.5px, hardSmall | Icon-only action |

The shell shrinks labels with `FittedBox(scaleDown)` rather than truncating
button copy. On widths at or above 430px, height grows only up to 1.10x.
Pressed state uses a short 4px translation and removes the shadow. Disabled
state uses reduced opacity and no active shadow.

`AppTheme` also configures fallback Material button themes, but new onboarding
actions should use `NuvoPrimaryButton`, `NuvoOutlineButton`, or the appropriate
semantic variant directly.

## Cards & surfaces

### Reusable surface primitives

- `NuvoCard` in `nuvo_card.dart`: white face, 26px radius, 2px border, optional
  hardMedium shadow, default 20px padding.
- `NuvoBackplateCard` in `nuvo_shared_components.dart`: white or supplied face,
  24px default radius, 1.25px outline, hardShadow4, default 20px padding.
- `NuvoCompactCard`: compact face-plus-offset wrapper using a 3px offset and
  16px radius.
- `NuvoActionTile`: icon badge, title, optional subtitle/trailing content, and
  an optional arrow. It is the shared settings/proof/action-row pattern.
- `NuvoEmptyState`, `NuvoErrorState`, and `NuvoLoadingIndicator` are state
  primitives, not decorative cards.

### Active race surfaces

- Arena's `_NextMoveHero` in `arena_screen_fixed.dart` is a white 32px hero
  surface, navy 2px outline, hardLarge shadow, and a blue tappable footer.
- `RaceHero` / `NuvoFeaturedRaceCard` in `nuvo_race_components.dart` is the
  reusable race hero used by the active Compete composition.
- `NuvoPodium`, `_OutlinedSheet`, `_YourProgressCard`, and `_RaceSummaryCard`
  in `race_detail_screen.dart` are race-specific compositions. They are not
  generic onboarding cards.
- List groups in current screens are usually white surfaces with a quiet
  divider border, clipped child rows, and 12–18px radii.

Avoid nesting multiple bordered cards for a single thought. Current shared
patterns prefer one surface with internal rows and dividers.

## Icons

Nuvo has a custom hand-drawn icon set in
[`lib/core/widgets/nuvo_icons.dart`](../lib/core/widgets/nuvo_icons.dart).
`NuvoIcon` renders 24x24 path data with a `CustomPainter` and supports:
`flag`, `crown`, `fire`, `trendUp`, `check`, `checkCircle`, `camera`, `hand`,
`users`, `user`, `plus`, `lock`, `bolt`, `bell`, `close`, `arrow`, and `back`.

The current code also uses Material `Icons` extensively for navigation,
movement identity, settings, camera controls, and operational actions. Use
`NuvoIcon` for Nuvo's core brand/race symbols and Material icons for familiar
contextual actions. Do not add an icon package or redraw icons as one-off
painters.

`NuvoAvatar`, `NuvoCompetitorAvatar`, and `NuvoAvatarStack` in
`nuvo_avatar.dart` are the identity system. Avatars are circular, photo-first,
and fall back to deterministic flat-color initials.

## Chips & metadata

- `NuvoPill` in `nuvo_shared_components.dart`: compact status/tag pill, 999px
  radius, 9px horizontal and 4px vertical padding, tinted background, and a
  low-alpha role border.
- `NuvoChip` in `nuvo_chip.dart`: interactive category/tag pill, 14px
  horizontal and 7px vertical padding, 2px border, selected state uses the
  blue panel and accent blue.
- `_StatusPill` in `race_detail_screen.dart`: race-specific blue metadata pill.
- `NuvoMetaItem` and `NuvoMetaRow` in `nuvo_meta_row.dart`: icon plus label and
  optional subline for scannable facts below a hero.
- `NuvoIconBadge` is a rounded-square icon anchor, normally 40px with a 12px
  radius.

Metadata should be grouped into a pill or row rather than rendered as a loose
stack of unexplained gray strings.

## Navigation

### Shared shell and bottom navigation

`MainShell` in `features/shell/presentation/main_shell.dart` owns the tab
Scaffold and revalidation triggers. `NuvoBottomNav` in `core/widgets/bottom_nav.dart`
owns the dock geometry:

- 64px visible dock height.
- 16px horizontal margin.
- 12px radius family through `NuvoRadii.lg`.
- 1px divider outline on white surface.
- Five tabs: Arena, Compete, Verify, Crew, Profile.
- Verify is the distinctive raised center action, rising 10px above the dock.
- Selected standard tabs use blue icon/label plus a soft-blue selected panel;
  inactive tabs use muted text.
- Dark mode is only used by the optional dark track shell path, not the main
  light shell.

The shell uses no transition between tabs (`NoTransitionPage`). Pushed routes
use Cupertino transitions, and camera routes use the same native page type with
camera-specific full-screen composition.

### Headers and back navigation

Active tab screens commonly build their own compact header with
`AppTextStyles.screenTitle`, rather than using an AppBar. Deep screens use
`NuvoBackButton` or `NuvoBackNavRow`. `NuvoTopBar` and `NuvoPage` remain useful
for standalone pages such as notifications and public profile, but they are
not the dominant tab-screen header pattern.

## Progress

Nuvo progress is race progress, not generic completion decoration.

- `RaceProgress` in `nuvo_race_components.dart` is a thin 3px lane with a blue
  fill, a navy-ringed position dot, a quiet 0% start marker, and a green
  finish check at 100%.
- `NuvoRaceLane` in `nuvo_shared_components.dart` is the shared static lane
  used by current race rows and leaderboard content. It deliberately does not
  reanimate on every list rebuild.
- `NuvoProgressBar` is a generic 6px animated bar with a 700ms ease-out curve;
  use only when a standard bar is semantically appropriate.
- `NuvoRacePath` is the active Arena race path. It creates a stable,
  deterministic per-race curved path, animates progress over 700ms, and ends at
  a finish flag.
- `CompetitionRing` is a reusable 96/160/240px circular progress surface with
  animated participant markers. Current Arena and Race Detail compositions
  should be checked before adding a ring to a new screen; the active Arena
  hero currently emphasizes `NuvoRacePath` instead.
- `NuvoPodium` is the top-three leaderboard treatment: flat avatars, colored
  placement marker, no pedestal blocks, and a larger centered first place.

## Race UI

### Arena / Compete

`ArenaScreen` currently comes from `arena_screen_fixed.dart`. It answers “what
needs my attention now?” with:

1. `Arena` plus a time-based greeting.
2. A `Your next move` label.
3. A responsive carousel of `_NextMoveHero` surfaces.
4. A blue footer that opens the race board.
5. Quick actions: `Submit proof`, `New`, and `Join`.
6. A `Leaderboard` preview using podium and outlined rows.
7. `Recent activity` below the first composition.

The active Compete screen is `compete_screen_fixed.dart`. It uses a compact
header with `Start` and `Join`, one featured race surface, capped race rows,
waiting/finished summaries, and a two-column `Quick starts` wrap. It reuses
`NuvoFeaturedRaceCard`, `NuvoRaceRow`, `NuvoFinishedRaceRow`,
`NuvoWaitingCrewSummary`, `NuvoFinishedSummary`, and `NuvoQuickStart` aliases
from `nuvo_race_components.dart`.

### Race details

`RaceDetailScreen` is a standalone SafeArea/ListView page. The active race
header is a back control, optional settings icon, race title, goal, and racer
count. The board appears before progress and secondary management content:

- active races: top three in `NuvoPodium`, remaining racers in an outlined list;
- completed races: final standings through the same podium/list language;
- participant progress: `_YourProgressCard` with value, rank, lane, and chase
  copy;
- proof history: `NuvoMoveLogItem` in `_MoveLogGroup`;
- owner controls: `_ManageGroup` and `_ManageRow`;
- pinned primary action: `_VerifyBar` with a full-width `NuvoPrimaryButton`.

### Race creation

`RaceComposerScreen` is a six-stage PageView composer: name, activity, optional
Teach Nuvo training, goal, racers, and review. `_ComposerTopBar` shows a back
control, `N of total`, and `_ProgressLine`. `_PageShell` owns question/support
copy and the bottom primary CTA. Fields use `_ComposerField` or the focused
`_LargeTextField`; movement selection uses `_TeachNuvoCard`, `_SearchBar`,
`_CategoryTabs`, `_MovementShelf`, and `_ActivityList`.

The composer uses a single primary CTA per stage and makes the next step
explicit. Its local controls are useful references for a multi-step onboarding
flow, but the page-private classes should not be copied as new generic
primitives without checking the shared library first.

## Leaderboard UI

There is no separate leaderboard route. The leaderboard is built into Arena and
Race Detail:

- `NuvoPodium` owns the top-three hierarchy.
- `RacePlacement` communicates rank as a number, not a generic colored badge.
- `NuvoLeaderboardRow` is a reusable full-width row with rank, avatar, name,
  lane, and progress value.
- `RacePeople` / `NuvoAvatarStack` communicate crew participation.
- `_LeaderboardCompactRow` in Race Detail handles rank 4+ and highlights the
  current user with the blue panel.
- `RaceProgress` and `NuvoRaceLane` carry progress semantics.

Top-three color belongs to the placement marker or number, not to an entire
row. Do not turn every participant into a colored card.

## Verify UI

The Verify tab is `MoveScreen`, not the camera page. It uses:

- compact `Verify` header and ready count;
- `_SegmentedControl` for `Ready`, `Completed`, and `Recent`;
- `AnimatedSwitcher` with a short horizontal slide/fade between segments;
- one prominent `_UpNextCard` and capped compact rows;
- `NuvoEmptyState`, `NuvoErrorState`, and `NuvoLoadingIndicator` for states.

The actual camera verification route is `AiMotionProofScreen`. The setup state
uses a light shell with a white header and dark rounded camera panel. Once the
camera is ready, the preview becomes an edge-to-edge black immersive surface:

- camera fills the screen;
- top controls float over scrims;
- status/progress and visibility use compact pills;
- the pose skeleton is drawn over the camera;
- bottom actions use full-width Nuvo buttons;
- result state uses a full navy surface with a central result panel.

Do not copy the camera HUD style into ordinary onboarding. It is intentionally
high-contrast and task-focused.

## Crew UI

The active Crew tab is `PassScreen` at `/pass`. The screen uses:

- `Crew` title, explanatory line, and notification bell;
- `_CrewHero`, a blue-tinted identity surface with avatar stack and crew count;
- one primary `Share pass` button;
- small `My code` and `Copy ID` secondary actions;
- `NuvoSearchField` and a full-width `Scan a code` tertiary button;
- section labels for `Find people`, `Closest race`, `Crew requests`, and
  `Your crew`;
- people rows with `NuvoAvatar`, name/handle, and one compact action;
- a single grouped white surface with dividers for lists.

Crew-specific color uses success or danger only for the crew-count state. It
does not turn the whole people graph green.

## Motion & interaction

Current interaction conventions are short, tactile, and restrained:

- `PressableScale` uses an 80ms press-in and 200ms release animation.
- `_PhysicalButtonShell` uses 90ms positional motion and 120ms opacity motion.
- selected chips/nav items use `AnimatedContainer` around 160–180ms.
- Verify segments use a 280ms in / 220ms out switch with ease-out/ease-in
  curves.
- Progress bars and race paths animate over 700ms with `Curves.easeOutCubic`.
- Profile stats count up over 800ms; `NuvoLoadingIndicator` pulses on an
  1100ms repeating controller.
- Camera result moments use short fade/scale treatments, including a 420ms
  finish-line moment in `ai_motion_proof_screen_io.dart`.
- Cupertino page transitions provide the pushed-route transition; bottom-nav
  tab switches are immediate.

Reduced-motion handling is not a complete global policy. The Rive movement
preview checks `MediaQuery.disableAnimationsOf(context)`, while many other
screens use their own animations. New onboarding motion should check the same
setting and provide a static or instant alternative.

## Responsive layout

Use `NuvoResponsive` rather than device-specific conditionals:

- baseline width: 390px;
- scale clamp: 0.90–1.18;
- text scale clamp: 0.85–1.30;
- compact width: below 360px;
- large width: 600px or wider;
- vertical density: compact below 700px usable height, regular through 860px,
  large above 860px.

Keep button tap targets intact. Current screens adapt by changing gaps, hero
slot height, and content density more often than by shrinking every element.
Arena's hero slot and Quick Actions row are the clearest examples.

## Shared components to reuse

Prefer these active primitives before writing screen-private equivalents:

| Need | Reuse |
|---|---|
| Page canvas / SafeArea shell | `MainShell`, `NuvoPage`, or the current screen's SafeArea composition |
| Screen title | `AppTextStyles.screenTitle` |
| Back navigation | `NuvoBackButton` or `NuvoBackNavRow` |
| Primary action | `NuvoPrimaryButton` |
| Secondary action | `NuvoOutlineButton` |
| Lower-emphasis action | `NuvoTertiaryButton` / `NuvoGhostButton` |
| Success/destructive action | `NuvoSuccessButton` / `NuvoDangerButton` |
| Text field | `NuvoTextInput` or the composer field pattern when its semantics match |
| Surface/card | `NuvoCard`, `NuvoBackplateCard`, `NuvoCompactCard`, or a race-specific component |
| Action/settings row | `NuvoActionTile` |
| Avatar / people | `NuvoAvatar`, `NuvoAvatarStack`, `NuvoCompetitorAvatar` |
| Status/tag | `NuvoPill`, `NuvoChip`, `NuvoMetaItem` |
| Race progress | `RaceProgress`, `NuvoRaceLane`, `NuvoRacePath`, `CompetitionRing` |
| Leaderboard | `NuvoPodium`, `NuvoLeaderboardRow`, `RacePlacement` |
| Loading | `NuvoLoadingIndicator` |
| Error | `NuvoErrorState` or `NuvoOfflineBanner` when cached content remains valid |
| Empty state | `NuvoEmptyState` |
| Confirmation | `NuvoConfirmSheet` or `NuvoConfirmDialog` |
| Tactile press | `PressableScale` |
| Brand icons | `NuvoIcon` |

Use product-specific race components when the content is a race object. Use a
generic card only when the surface is truly generic. Do not create a second
button, avatar, progress, or empty-state system inside onboarding.

## Legacy patterns to avoid

These patterns are present in old files, compatibility aliases, or older
documentation and should not be used as the current design reference:

- Do not use the old `track_view_screen.dart` Arena composition. The active
  Arena is `arena_screen_fixed.dart`.
- Do not route new creation UI through `CreateRaceScreen`. The active page is
  `RaceComposerScreen`; `CreateRaceScreen` currently supplies the prefill type
  used by the composer.
- Do not copy the old transparent meaning of `NuvoGhostButton`. Current code
  maps it to `NuvoTertiaryButton`: gray100 fill, gray300 outline, no shadow.
- Do not assume the older `docs/NUVO_PATTERN_LIBRARY.md` hero guidance is the
  rendered implementation. The active Arena hero is a white outlined card with
  a blue footer and `NuvoRacePath`.
- Do not use the stale color values in older design inventories. The exact
  values in `app_colors.dart` are current.
- Do not create generic Material buttons directly in feature screens when a
  Nuvo button exists.
- Do not use gradients, arbitrary soft shadows, or decorative glass surfaces
  as default onboarding styling.
- Do not make every section a card, nest cards inside cards, or repeat the same
  icon-heading-card grid.
- Do not use a colored full row for every leaderboard rank. Use podium marker
  colors and quiet rows.
- Do not use a blank area, bare “nothing here” message, or dead CTA. Use
  `NuvoEmptyState` and tell the user what to tap.
- Do not add a second bottom-safe inset inside a shell tab. `MainShell` and
  `NuvoBottomNav.bottomPadding(context)` already coordinate that geometry.
- Do not use all-caps tracked copy for ordinary section headings. Current Arena
  and tab screens favor sentence-case structural labels; uppercase is reserved
  for compact status/progress treatments.

## Source-of-truth files

### Theme and tokens

- [`lib/core/theme/app_colors.dart`](../lib/core/theme/app_colors.dart): exact
  colors and semantic role bundles.
- [`lib/core/theme/app_geometry.dart`](../lib/core/theme/app_geometry.dart):
  radii, borders, and primary spacing scale.
- [`lib/core/theme/app_shadows.dart`](../lib/core/theme/app_shadows.dart): hard
  offset and soft sheet/dock shadows.
- [`lib/core/theme/app_text_styles.dart`](../lib/core/theme/app_text_styles.dart):
  Manrope styles and semantic race styles.
- [`lib/core/theme/app_theme.dart`](../lib/core/theme/app_theme.dart): Material
  theme, input fields, fallback button/chip styles, sheets, dialogs, and
  progress defaults.
- [`lib/core/theme/nuvo_tokens.dart`](../lib/core/theme/nuvo_tokens.dart):
  parallel consolidated aliases used by several shared components.
- [`lib/core/theme/nuvo_responsive.dart`](../lib/core/theme/nuvo_responsive.dart):
  layout factor, density, and text scaling.

### Shared visual primitives

- [`lib/core/widgets/nuvo_button.dart`](../lib/core/widgets/nuvo_button.dart)
- [`lib/core/widgets/nuvo_card.dart`](../lib/core/widgets/nuvo_card.dart)
- [`lib/core/widgets/nuvo_shared_components.dart`](../lib/core/widgets/nuvo_shared_components.dart)
- [`lib/core/widgets/nuvo_race_components.dart`](../lib/core/widgets/nuvo_race_components.dart)
- [`lib/core/widgets/nuvo_board_components.dart`](../lib/core/widgets/nuvo_board_components.dart)
- [`lib/core/widgets/nuvo_avatar.dart`](../lib/core/widgets/nuvo_avatar.dart)
- [`lib/core/widgets/nuvo_icons.dart`](../lib/core/widgets/nuvo_icons.dart)
- [`lib/core/widgets/nuvo_empty_state.dart`](../lib/core/widgets/nuvo_empty_state.dart)
- [`lib/core/widgets/nuvo_error_state.dart`](../lib/core/widgets/nuvo_error_state.dart)
- [`lib/core/widgets/nuvo_loading_indicator.dart`](../lib/core/widgets/nuvo_loading_indicator.dart)
- [`lib/core/widgets/bottom_nav.dart`](../lib/core/widgets/bottom_nav.dart)
- [`lib/core/widgets/nuvo_page.dart`](../lib/core/widgets/nuvo_page.dart)
- [`lib/core/widgets/pressable_scale.dart`](../lib/core/widgets/pressable_scale.dart)

### Representative active screens

- [`lib/features/arena/presentation/arena_screen_fixed.dart`](../lib/features/arena/presentation/arena_screen_fixed.dart)
- [`lib/features/compete/presentation/compete_screen_fixed.dart`](../lib/features/compete/presentation/compete_screen_fixed.dart)
- [`lib/features/race_detail/presentation/race_detail_screen.dart`](../lib/features/race_detail/presentation/race_detail_screen.dart)
- [`lib/features/move/presentation/move_screen.dart`](../lib/features/move/presentation/move_screen.dart)
- [`lib/features/races/presentation/ai_motion_proof_screen_io.dart`](../lib/features/races/presentation/ai_motion_proof_screen_io.dart)
- [`lib/features/pass/presentation/pass_screen.dart`](../lib/features/pass/presentation/pass_screen.dart)
- [`lib/features/profile/presentation/profile_screen.dart`](../lib/features/profile/presentation/profile_screen.dart)
- [`lib/features/profile/presentation/edit_profile_screen.dart`](../lib/features/profile/presentation/edit_profile_screen.dart)
- [`lib/features/races/presentation/race_composer_screen.dart`](../lib/features/races/presentation/race_composer_screen.dart)
- [`lib/features/races/presentation/custom_pose/teach_movement_screen.dart`](../lib/features/races/presentation/custom_pose/teach_movement_screen.dart)
- [`lib/features/shell/presentation/main_shell.dart`](../lib/features/shell/presentation/main_shell.dart)

Recent UI changes are concentrated in the shell and primary tab compositions,
including commits `38e39f7` and `66f67b3`. Those active files take precedence
over earlier inventory documents and unused screen variants.

## Onboarding-specific recommendations

For a new onboarding screen that belongs in the current Nuvo app:

1. Use `NuvoColors.page` as the canvas and `NuvoColors.navy` for primary type.
   Use `NuvoColors.blue` for the one primary action and interactive selection.
2. Use Manrope through `AppTextStyles`; start with `screenTitle` for the page
   identity, `headlineMedium` or `headlineLarge` for the key instruction, and
   `bodyMedium`/`bodySmall` for support copy.
3. Keep horizontal content margins in the current 20–22px range, wrap the
   page in `SafeArea`, and respect `NuvoResponsive` density/text scaling.
4. Give the screen one obvious next action. Use a full-width
   `NuvoPrimaryButton` at 56px height unless the screen is using the small
   46px compact action register.
5. Use `NuvoBackButton` on pushed onboarding pages. Do not recreate the
   circular back control.
6. If onboarding is staged, reuse the visual contract of
   `RaceComposerScreen._ComposerTopBar`, `_ProgressLine`, and `_PageShell`:
   show the current step, a restrained progress line, one question, one short
   support line, and one bottom CTA. Keep the implementation semantic to
   onboarding rather than copying private class names.
7. Choose one primary surface treatment: a white outlined card, a blue-tinted
   panel, or a flat page composition. Do not stack all three.
8. Use `PressableScale` for tappable non-button rows and keep selection motion
   short. If adding entrance or selection animation, provide a static path when
   `MediaQuery.disableAnimationsOf(context)` is true.
9. Use `NuvoEmptyState`, `NuvoErrorState`, and `NuvoLoadingIndicator` for
   non-happy paths. Do not leave an empty blank stage while data is loading.
10. Reuse `NuvoAvatar`, `NuvoIcon`, `NuvoPill`, `NuvoMetaItem`, and the race
    components when the onboarding content is identity, status, metadata, or a
    race. Do not make lookalike local widgets.
11. Keep copy direct and action-oriented. The user should understand what the
    screen is, what progress they are making, and what to tap next.

## ONBOARDING DESIGN CONTRACT

The following is the concrete contract for future onboarding implementation:

- Canvas: `NuvoColors.page` (`#FBFCFF`).
- Main ink: `NuvoColors.navy` (`#07152D`).
- Primary action: `NuvoPrimaryButton`, action blue `#1264FF`, white label,
  navy 3px edge, 5px hard offset, 56px default height, 24px radius.
- Secondary action: `NuvoOutlineButton`, white face, navy 3px edge, 3px hard
  offset, 56px default height. Lower-emphasis actions use the current gray100
  `NuvoTertiaryButton`/`NuvoGhostButton`.
- Page title: `AppTextStyles.screenTitle`, Manrope 30/w800, navy, 1.10 line
  height, `-0.8` tracking.
- Instruction heading: `headlineLarge` or `headlineMedium`, navy, with no
  ad-hoc display scale unless the layout needs a documented local override.
- Supporting copy: `bodyMedium` or `bodySmall`, `NuvoColors.muted`.
- Horizontal margin: normally 20–22px; use `NuvoSpacing.pageHorizontal` where
  the screen is a tab composition.
- Vertical rhythm: use the 4/8/12/16/20/24/32 spacing scale.
- Surface: white, explicit outline, radius from `NuvoRadii`; use one hard
  offset shadow only when the surface is an action or hero.
- Border: 1–1.25px quiet/divider for passive surfaces; 2–3px navy for hero and
  physical controls.
- Shape: 24px button radius, 26px card radius, 32px hero radius, 999px pill.
- Iconography: `NuvoIcon` for core Nuvo symbols, Material icons for familiar
  operational actions, and no new icon dependency.
- Navigation: `NuvoBackButton` for pushed pages; do not add a second bottom nav
  or a second shell SafeArea strategy.
- States: use the shared loading, error, empty, and offline components.
- Motion: short ease-out tactile feedback; respect
  `MediaQuery.disableAnimationsOf(context)` for new animation.
- Product behavior: one primary action, clear next step, no dead controls, no
  placeholder copy, and no ownership leakage into Arena, Verify, Crew, or
  Profile.
