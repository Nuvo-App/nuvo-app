# UI and design system guide

## Design source of truth

Read `docs/design/NUVO_DESIGN_SYSTEM.md`, `docs/NUVO_DESIGN_SYSTEM_INVENTORY.md`, and `docs/NUVO_PRODUCT_MODEL.md` before UI work. Prefer existing tokens and components over new one-off decoration.

`docs/FULL_APP_AUDIT_2026-08.md` is the current running list of known UI/UX debt
and what has been fixed — check it before "discovering" an issue.
[`09-widget-and-token-reference.md`](09-widget-and-token-reference.md) is the
day-to-day "how do I use this widget/token" cookbook;
[`10-pitfalls-and-fixes.md`](10-pitfalls-and-fixes.md) §E/§F covers the Flutter
rendering + colour-system traps (clipped corners, transparent buttons, shimmer +
`pumpAndSettle`, the three token systems).

**Semantic colour + depth rules (enforced):**
- Blue is neutral / brand / primary-action — never a success or failure signal.
  Green = success/verified/finished. Red = failure/rejected/destructive.
  Orange/gold = warning. Use `NuvoColors.*` role tokens or
  `context.semanticColors` (the `NuvoSemanticColors` theme extension), each role
  has `base` / `shadow` / `bright` / `surface` / `border` / `on`.
- Hard-offset shadows mean "you can tap this." Put them ONLY on interactive
  surfaces (buttons, tappable cards). Content — leaderboards, podiums, progress
  cards, list rows — stays flat (navy border, no shadow).
- Every button tier has a solid fill + a shadow (`nuvo_button.dart`). There are
  no transparent buttons; a bare `Text` in a `GestureDetector` is not a button.
- Sizes scale with device via `context.rs(px)` / `TextStyle.scaled(context)`
  (`lib/core/theme/nuvo_responsive.dart`); the app clamps `TextScaler` to
  `[0.85, 1.3]`.

Primary implementation locations:

- `lib/core/theme/app_colors.dart`: semantic and raw colors.
- `lib/core/theme/app_text_styles.dart`: typography.
- `lib/core/theme/app_geometry.dart`: spacing/radii.
- `lib/core/theme/app_shadows.dart`: approved elevation/shadow patterns.
- `lib/core/theme/nuvo_tokens.dart`: consolidated token access for newer work.
- `lib/core/theme/app_theme.dart`: Material 3 defaults and component themes.
- `lib/core/widgets/nuvo_button.dart`, `nuvo_card.dart`, `nuvo_page.dart`, `nuvo_empty_state.dart`, `nuvo_error_state.dart`: shared primitives.

The live theme is light, Manrope-based, icy-white/navy with action blue and semantic success/danger colors. Existing gradients, glass, pills, shadows, and legacy widgets are not automatically approved for new screens; verify the design docs and surrounding feature first.

## UI rules

Every screen should make three things obvious:

1. What is this?
2. Who is winning or what is my progress?
3. What should I tap next?

Every screen has one primary action. A card or button must not imply an action that is not wired. Avoid hardcoded colors, duplicated button styles, and new animation systems when an existing widget/token is sufficient.

## Responsive checks

Test narrow phone widths, large phones, text scaling, keyboard-open states, long titles, empty/error/loading states, and web preview widths. Do not assume a 430px centered web preview represents a real mobile viewport.

For visual changes, add or update a focused widget/layout test. If a golden changes, inspect the rendered golden and explain why the change is intentional.
