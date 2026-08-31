# Visual System Polish Audit

## Global Problems

- **Too much scrolling**: Arena, Compete, Profile, AI Motion Proof all require scrolling to see primary CTAs or key content. Sections have excessive vertical padding (26–28px gaps) and oversized cards.
- **Basic/default card surfaces**: Race rows on Arena, Compete, and Profile are plain white containers with a 1px border — no Nuvo backplate, no press feedback, no visual hierarchy.
- **Underused Nuvo backplate style**: Only the hero Featured Race card, Submit Proof AI card, and Leaderboard leader row use the signature offset navy shadow. Quick action tiles, race list rows, settings rows, and section headers are unstyled.
- **Inconsistent card heights**: Stats grid tiles are tall (childAspectRatio 1.55). Race history rows and settings rows use identical styling. No density differentiation between primary and secondary cards.
- **Weak section hierarchy**: `_Section` in Race Detail and header text in other screens use plain `titleLarge` with default spacing. No visual hook to anchor the reader.
- **CTA placement**: On AI Motion Proof setup state, the CTA is in the bottomNavigationBar — but the camera placeholder and duplicate status panel cards push it off-screen on scroll.
- **Bottom nav/content overlap**: Page-level ListView bottom padding must account for the floating bottom nav height. Some screens don't add enough bottom SafeArea.

---

## Screen-by-Screen Problems

### Arena
- **Problems**: Hero card looks good. Quick action cards (`_ActionCard`) are icy-blue containers with no backplate shadow — feel flat. Active race rows (`_CompactRaceCard`) are plain white border boxes — no progress indicator, no AI/complete pill, no press feedback, looks identical to a default ListTile.
- **Fixes**: Add offset navy backplate shadow to `_ActionCard`. Rebuild `_CompactRaceCard` as NuvoDenseRaceRow: compact height, inline progress bar, Complete pill if 100%, AI Motion pill if AI race, arrow, PressableScale feedback.

### Pass
- **Problems**: Pass card is premium (dark navy, QR, corners). Search field is default Flutter `TextField`. Crew empty state is large centered block. No Nuvo treatment on search row.
- **Fixes**: Style search with subtle Nuvo card surface. Make crew empty state compact and card-contained. Reduce vertical padding between pass card and search.

### Compete
- **Problems**: `_RaceListTile` white cards with navy circle icons — plain, no progress, no pill. Quick starts below racing are secondary styled. Multiple screens of scrolling.
- **Fixes**: Add compact inline progress indicator to race tiles. Strengthen backplate on 10 Jumping Jacks. Reduce section gaps from 26–28px to 18–20px.

### Profile
- **Problems**: Stats grid `childAspectRatio: 1.55` — cells are tall, grid takes ~220px. Race history rows are plain white 15px-padded cards. Settings rows identical to history rows. Heavy vertical spacing throughout.
- **Fixes**: Increase `childAspectRatio` to 2.0 and reduce grid padding to 12px. Add NuvoActionTile treatment to settings (icon badge, subtle backplate, arrow). Race history rows: compact, add status pill.

### Race Detail
- **Problems**: Progress card is plain white border box. `_Section` adds 20px bottom on each section — 6 sections = 120px of gap. `_InfoRow` has 14px padding and is overly tall for simple text. Manage Race section uses 4 buttons in 2×2 grid — takes a lot of space. Proof method / rules / recent proofs sections require scrolling to reach leaderboard.
- **Fixes**: Add backplate shadow to progress card. Reduce `_Section` gap to 14px. Compact `_InfoRow` to 12px padding. Inline proof method into leaderboard section as a small pill. Reduce manage race to compact NuvoActionTile rows.

### Submit Proof
- **Problems**: AI proof card looks good (dark navy, backplate). Below the two options, there is ~400px of empty white page. The reassurance copy "Nuvo checks this race with your iPhone camera" is missing.
- **Fixes**: Add short reassurance copy beneath the AI card. The manual option should appear immediately below with less gap.

### AI Motion Proof
- **Problems**: Setup state shows: checklist card + 3:4 camera placeholder (≈520dp tall on 390dp screen) + status panel with near-identical text + CTA buttons. Everything stacks to 900dp+, forcing heavy scroll. Camera in ready state is same giant height. CTA can be below fold.
- **Fixes**: Remove status panel in setup state (duplicate of checklist). Constrain camera panel height to 260dp fixed (display-only crop, analysis unaffected). Show status panel only in active camera states (cameraReady/recording/errors). Back button should be top-left inline (not randomly placed by back button widget in the middle on some states).

---

## New Shared Components Needed

- **`NuvoBackplateCard`** — Wrapper with navy offset boxShadow + rounded corners. Used for hero cards and featured surfaces.
- **`NuvoCompactCard`** — Lighter card with `NuvoColors.white` fill, subtle border, small backplate. Used for rows and secondary cards.
- **`NuvoActionTile`** — Icon badge + title + optional subtitle + optional arrow. Used for settings, quick actions, proof rows.
- **`NuvoDenseRaceRow`** — Compact race row with icon badge, title, subtitle/progress pill, arrow, PressableScale.
- **`NuvoStatTile`** — Small stat card: number + label, compact height. Used in Profile 2×2 grid.
- **`NuvoPill`** — Reusable inline pill badge. Used for progress %, Complete, Active, AI Motion labels.
- **`NuvoIconBadge`** — Rounded square icon container with configurable color. Used as left icon in rows.

---

## Implementation Order

1. Create shared components (`lib/core/widgets/nuvo_shared_components.dart`)
2. Arena screen — backplate on action cards, NuvoDenseRaceRow for race list
3. Compete screen — dense race rows, reduce spacing
4. Race Detail screen — compact sections, backplate progress card
5. Submit Proof screen — add reassurance copy, reduce gap
6. AI Motion Proof screen — compact camera, remove duplicate status in setup
7. Pass screen — styled search, compact empty state
8. Profile screen — compact stats grid, NuvoActionTile settings
9. Update docs
10. `dart format .` + `flutter analyze`
