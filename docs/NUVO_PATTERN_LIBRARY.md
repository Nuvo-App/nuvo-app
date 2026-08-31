# Nuvo Visual Pattern Library

This document defines the concrete visual rules for every Nuvo object. It is the implementation guide for the design philosophy in `NUVO_PRODUCT_MODEL.md`.

Every rule is written as **anatomy + spacing + allowed/forbidden variants + production references**. If a screen cannot be described with these patterns, it should not ship.

---

## 01. Hero

### Purpose
Identity and orientation. One per screen.

### Anatomy (top to bottom)

```
┌────────────────────────────────────┐
│ Greeting  +  Profile/Action          │  16 px from safe area top
│                                      │
│ 1-line summary of what's happening   │
│                                      │
│ Primary action (1, max)              │
└────────────────────────────────────┘
```

### Rules
- Height: **200–260 px** on iPhone; never taller than 40 % of the screen.
- Background: navy gradient or solid blue.
- No borders, no shadows, no cards inside the hero.
- Exactly one interactive element besides the profile/notification affordance.
- Text hierarchy: greeting is largest, summary is secondary, action is smallest.

### Required
- Greeting using first name.
- One status indicator (rank, live count, or streak).
- Profile or notification tap target.

### Optional
- Animated stat.
- Live dot.

### Forbidden
- Lists.
- Multiple CTAs.
- Decorative illustrations.

### Example references
- Apple Fitness+ summary header
- Nike Run Club home hero
- Chess.com home header

---

## 02. Live Race

### Purpose
The active competition surface. Contains movement, goal, competition ring, rank, gap, and leaderboard preview.

### Anatomy

```
┌────────────────────────────────────┐
│ Movement pill     · Progress %     │  12 px between
│                                      │
│ Race title                           │
│ Context line                         │
│                                      │
│        ┌──────────────┐              │
│        │ Competition  │              │  Center of module
│        │     Ring     │              │
│        └──────────────┘              │
│                                      │
│ Avatar strip          Days left      │
│                                      │
│ Rank · chase copy                    │
│                                      │
│ [ Primary action ]                   │
└────────────────────────────────────┘
```

### Rules
- Surface: elevated card on background.
- Corner radius: 24 px.
- Padding: 22 px all sides.
- Internal vertical gaps: 16 px.
- Competition Ring size: **medium (160 px)** in this module.
- Ring sits visually centered, never full-width.

### Required
- Movement type pill.
- Your current progress percent.
- Race title.
- Competition Ring with real participants.
- Primary action (Log Move / Open Board).

### Optional
- Avatar strip of top 4 racers.
- Days-left meta.
- Rank + chase copy panel.

### Forbidden
- Progress bar separate from the ring.
- Leaderboard rows replacing the ring as the hero.
- Multiple primary buttons.

---

## 03. Competition Ring

### Purpose
Nuvo's signature object. Represents the competition, not just progress.

### Anatomy

```
        Marker (winner)
              ●
              │
    ●───────track───────●
   (2nd)               (3rd)
              │
              ○  ← current user (blue)

         Center value
```

### Rules
- Track: gray200.
- Progress arc: royal blue.
- Start position: 12 o'clock.
- Sweep direction: clockwise.
- Marker size: 28 px (medium), 40 px (large), 18 px (small).
- Ring thickness: 8 px (medium), 10 px (large), 5 px (small).
- Marker ring:
  - 1st = gold
  - 2nd = silver
  - 3rd = bronze
  - current user outside top 3 = royal blue
  - everyone else = border color
- Center label: bold navy, one or two lines max.

### Required
- At least one participant.
- Progress sweep animated from 0 on first paint.

### Allowed variants
- `small` — lists, notifications.
- `medium` — race detail, profile history.
- `large` — arena hero, share cards.

### Forbidden
- Empty static ring without a center state.
- Markers placed beside the ring instead of on it.
- More than 6 markers on a small ring.
- Different colors for arbitrary statuses.

---

## 04. Leaderboard Row

### Purpose
Comparison. Never a card.

### Anatomy

```
┌────────────────────────────────────┐
│ #  Avatar  Name  ·····  Progress   │
└────────────────────────────────────┘
```

### Rules
- Full-width row.
- Height: 52 px.
- Horizontal padding: screen margin (24 px).
- Rank pill: 28 px circle or bare number.
- Avatar: 32 px.
- Name: left aligned, truncate with ellipsis.
- Progress: right aligned, monospaced figures preferred.
- Top 3 ranks use gold/silver/bronze rank color; rows themselves stay neutral.

### Required
- Rank.
- Avatar or initials.
- Display name.
- Progress value.

### Optional
- Gap behind leader ("+6", "-12").
- You-highlight row background (subtle).

### Forbidden
- Colored row backgrounds for rank.
- Badges, chips, or icons on every row.
- Progress bars inside rows.

### Example references
- Chess.com leaderboard
- Strava segment rankings
- Formula 1 timing tower

---

## 05. Race Rail

### Purpose
Browsing. Horizontal object, not a card grid.

### Anatomy

```
┌────────────────────────────────────┐
│ Movement · Status    Chevron >     │
│ Title                              │
│ Goal                               │
│ Progress strip                     │
└────────────────────────────────────┘
```

### Rules
- Fixed width: 260 px.
- Height: 130–150 px.
- Horizontal gap between rails: 12 px.
- Corner radius: 20 px.
- Progress strip at bottom, 3 px.
- Chevron implies tappable.

### Required
- Movement type.
- Title.
- Goal / target.
- Progress.
- Status pill (Live, Finished, Solo, Waiting).

### Forbidden
- Full card shadow stack.
- Multiple CTAs per rail.
- Avatar lists inside the rail.

### Example references
- Spotify playlist rail
- App Store Today cards
- Apple Music recently played

---

## 06. Verification

### Purpose
Camera guidance. No decoration.

### Anatomy

```
┌────────────────────────────────────┐
│ Camera preview                     │
│                                      │
│ Instruction (1 line, large)        │
│ Sub-instruction (1 line)           │
│                                      │
│ Counter · status                     │
└────────────────────────────────────┘
```

### Rules
- Camera fills maximum safe area.
- UI overlays bottom or edges, never center unless critical.
- Instruction type: display size, white.
- Counters: body size, white with 70 % opacity.
- Progress indicators only for analysis, never live reps.

### Required
- Live camera preview.
- Current instruction.
- Cancel / done affordance.

### Forbidden
- Background illustrations.
- Floating cards over camera.
- Decorative gradients.
- Confidence scores visible to user.

---

## 07. Crew

### Purpose
People graph. Avatars dominate.

### Anatomy

```
┌────────────────────────────────────┐
│ ┌─┐ ┌─┐ ┌─┐ ┌─┐  + Invite         │
│ Name  Name  Name  Name             │
└────────────────────────────────────┘
```

### Rules
- Avatar size: 48 px default, 40 px in dense rows.
- Stack overlap: 8 px negative margin.
- Names below avatars, one line.
- Invite action as a circular avatar with "+" not a long button.

### Required
- Avatars.
- Names.
- Invite affordance.

### Forbidden
- Text-heavy member cards.
- Multiple action buttons per member.
- Status text longer than one word.

---

## 08. Timeline

### Purpose
History. Vertical, compact, GitHub-like.

### Anatomy

```
│ ┌─  Actor   Action
│ │   Time ago
│ │
│ └─
```

### Rules
- Left rail: 24 px wide, icon or avatar.
- Right content: actor name, action verb, object.
- Time: meta color, 12 px.
- Row height: 44–52 px.
- No cards. No dividers between adjacent items.

### Required
- Actor identity.
- Action + object.
- Timestamp.

### Forbidden
- Cards per entry.
- Full-width banners.
- Duplicate information.

---

## 09. Profile

### Purpose
Identity, not analytics.

### Anatomy

```
┌────────────────────────────────────┐
│ Avatar          Username           │
│                 Bio line            │
│                 Edit                │
│                                      │
│ Stats row (3 items, max)           │
│                                      │
│ Recent races → Race Rail           │
│                                      │
│ Settings / Log out                 │
└────────────────────────────────────┘
```

### Rules
- Avatar: 80 px.
- Stats: horizontal, equal width, no icons.
- Recent races use the Race Rail pattern horizontally.
- Settings as list rows, not cards.

### Required
- Avatar.
- Username.
- Primary stats.
- Recent races.

### Forbidden
- Charts and graphs.
- Multiple cards stacked.
- Long centered paragraphs.

---

## 10. Section Header

### Purpose
Boundary between objects.

### Anatomy

```
Title                          Action
```

### Rules
- Height: 40 px.
- Title: section size, navy, left.
- Action: body size, blue, right.
- Divider optional, 1 px, border color.

### Required
- Title.

### Optional
- Right action.

### Forbidden
- Badges or counts in the title.
- Background pills.

---

## 11. Status Pill

### Purpose
One-word state communication.

### Anatomy

```
┌──────────┐
│  Live    │
└──────────┘
```

### Rules
- Height: 22 px.
- Horizontal padding: 8 px.
- Border radius: 99 px.
- Text: label size, semibold.
- Background: semantic color at 10 % opacity.
- Text color: semantic color at full opacity.

### Allowed states
- Live: blue
- Finished: green
- Solo: gray
- Waiting: orange

### Forbidden
- Two-word pills.
- Filled backgrounds.
- Icons inside pills.

---

## 12. Buttons

### Primary Button

```
┌────────────────────────────────────┐
│  Icon  Label                       │
└────────────────────────────────────┘
```

- Height: 52 px.
- Background: royal blue.
- Text: white, semibold, 16 px.
- Icon: leading, 20 px.
- Use for: Compete, Verify, Join.

### Secondary Button

- Same height.
- Transparent background.
- Royal blue text.
- Border: 1 px royal blue.
- Use for: Share, Copy, Invite.

### Danger Button

- Red text, transparent background.
- Use for: Leave race, Delete.

### Forbidden
- More than one primary button in any module.
- Ghost buttons as primary actions.
- Buttons with shadows.

---

## 13. Surfaces

### Background
- Color: `NuvoTokens.background`.
- Usage: 70 % of screen.

### Elevated
- Color: `NuvoTokens.card`.
- Usage: hero modules, primary objects.
- Shadow: `NuvoTokens.shadow1`.

### Overlay
- Color: navy at 85 % opacity.
- Usage: dialogs, bottom sheets, camera overlays.

### Navigation
- Color: `NuvoTokens.card`.
- Shadow: `NuvoTokens.shadow3`.
- Floating, pill-shaped where appropriate.

---

## 14. Typography Hierarchy

| Level | Size | Weight | Usage |
|-------|------|--------|-------|
| Display | 32 px | Bold | Center ring value, rank hero |
| Page | 28 px | Bold | Screen titles, greeting |
| Section | 18 px | Semibold | Section headers, race titles |
| Body | 14–16 px | Regular | Context, leaderboard names |
| Label | 12 px | Semibold | Pills, timestamps, meta |

Rules:
- No sizes between the scale steps.
- Line height: 1.2 for display, 1.4 for body.
- Color: navy for primary, gray700 for secondary, gray500 for meta.

---

## 15. Spacing System

Apply `NuvoTokens.space4..space64` directly. Do not invent values.

| Use | Token |
|-----|-------|
| Tight internal | space8 |
| Standard internal | space12, space16 |
| Section break | space24, space32 |
| Major section | space48, space64 |
| Screen margin | 24 px (`NuvoTokens.margin`) |

---

## 16. Motion

| Type | Duration | Curve | Use |
|------|----------|-------|-----|
| Micro | 220 ms | ease | Button presses, pill switches |
| Object | 320 ms | spring | Ring expansion, row entrance, count-up |
| Page | 400 ms | ease | Nav transitions |

Rules:
- Ring progress animates from previous to new value.
- Numbers count, do not jump.
- Leaderboard rows cascade in with 40 ms stagger.
- Avatars scale on selection with spring.
- Nothing fades in place of movement.

---

## 17. Before / After

### Bad
- `Card` containing title, subtitle, graph, three buttons, and a list.
- Centered paragraph explaining the race.
- Progress ring with no people.
- Leaderboard row with a full-width colored background.

### Good
- `Hero` → `Live Race` → `Race Rail` for history.
- One primary action per module.
- Competition Ring with participants on the ring.
- Leaderboard rows as neutral, high-density rows.

---

## 18. The Nuvo Test Applied

Before approving any screen, verify:

1. Hero object is obvious and alone.
2. Competition object is identifiable at a glance.
3. People (avatars or names) are visible without scrolling.
4. Primary action is the only emphasized button.
5. Every object maps to a pattern in this library.
6. At least one element can be removed without breaking meaning.
7. The screen feels closer to Chess.com/F1 than to a Flutter template.
