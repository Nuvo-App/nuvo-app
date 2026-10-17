# Nuvo Color System

Colour carries meaning. Use the semantic roles in `NuvoSemanticColors`
(`lib/core/theme/app_colors.dart`) instead of picking hues per screen.

| Role | Colour | Means |
|---|---|---|
| neutral | Nuvo blue | primary action, selected, admin, links, AI |
| success | green | live, active, verified, accepted, in-friends, leading |
| gold | gold | 1st place, levels/XP/streaks, the "you" highlight, crew owner |
| warning | orange | pending, waiting, needs attention, friend requests |
| danger | red | destructive, errors, rejected, blocked, cancelled |
| accent | tan | warm decoration only, never state |

## Surfaces

- Ordinary cards and rows: white `c.surface` with a 2pt ink border (`c.border`).
- Never use pale icy-blue panels as card, row or chip backgrounds.
  `c.panel` / `c.panelLight` are allowed only as inset wells inside a white
  card, and only if nothing else works.
- State is shown with a solid pill or a coloured border, not a tinted card.

## Examples

| Element | Role | Treatment |
|---|---|---|
| Race status: leading / live | success | solid green pill, dark text |
| Race status: chasing / in the race | neutral | solid blue pill, white text |
| Race status: waiting / starts in | warning | solid orange pill, dark text |
| Race status: finished | gold | solid gold pill, dark text |
| Race status: cancelled | danger | solid red pill, white text |
| Role chip: owner | gold | solid gold |
| Role chip: admin | neutral | solid blue |
| Role chip: member | none | white surface, ink border |
| Friend request row (incoming) | warning | white row, orange "Request" pill |
| Accepted friend row | success | white row, green "Friends" pill |
| Blocked / rejected row | danger | white row, red pill |
| Primary button | neutral | solid blue |
| Destructive button (leave, remove) | danger | solid red or red outline |

In code, use `NuvoPill(label: ..., role: NuvoPillRole.warning)` and
`RaceStatusPill(tone: RaceRowTone.waiting)`; both render a solid fill with
readable text. The older `NuvoPill(color: ...)` tinted form remains for
compatibility but should not be used for new emphasis.
