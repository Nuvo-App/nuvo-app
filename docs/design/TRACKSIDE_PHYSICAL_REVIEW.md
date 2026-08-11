# Trackside Physical Review — Design Audit

Based on physical iPhone screenshots and code audit of all screens at checkpoint 6927d17.

## Depth System Findings

### Hard-offset shadow inventory

| Location | Shadow | Verdict |
|---|---|---|
| Compete featured card | hardLarge (7,7) | KEEP — screen hero |
| Verify segment tab (selected) | hardSmall (3,3) | REMOVE — too loud for a tab |
| Verify Up Next card | hardMedium (5,5) | REDUCE — screen hero but should use hardLarge or softSubtle |
| Crew header card | surfaceShadow | REDUCE — too loud for identity card |
| Bottom nav dock | hardSmall (3,3) | REMOVE — nav should be quiet |
| Bottom nav Verify button | hardSmall (3,3) | REMOVE — nav should be quiet |
| Profile identity card | custom inline shadow | REDUCE — too loud |
| NuvoBackplateCard | hardShadow4 | Audit usage |
| NuvoCompactCard | hardShadow3 | Audit usage |
| NuvoActionTile | hardShadow3 (via CompactCard) | Audit usage |

### Target depth model

- LEVEL 0 (page): no shadow
- LEVEL 1 (lists/supporting): border or tonal only
- LEVEL 2 (controls/selected): subtle tonal lift, no hard offset
- LEVEL 3 (screen hero): ONE hard-offset per screen, rare

## Screen-by-Screen Audit

### COMPETE

- **Strongest object**: Featured race card (navy, hardLarge) ✓
- **Second strongest**: Bottom nav dock (competes — too loud)
- **Primary action**: Start race (subtleLift) ✓
- **Issues**:
  - Top spacing too tight (fixed: xl → xxxl)
  - Waiting/Finished summaries are generic dashboard cards with icon containers
  - Quick Starts are 2-column settings grid tiles — weakest piece
  - Section headers use `sectionKicker` (uppercase, letter-spaced) — dashboard feel
  - 0% progress lanes are nearly invisible

### VERIFY

- **Strongest object**: Up Next card (navy, hardMedium) — good but should be hardLarge
- **Second strongest**: Segmented control selected tab (hardSmall) — too loud
- **Primary action**: Verify CTA inside Up Next ✓
- **Issues**:
  - Empty scroll/bounce (fixed: ClampingScrollPhysics)
  - Top spacing inconsistent with Compete (fixed: 22 → 32)
  - Segment control has hard-offset shadow on selected tab — old generation
  - "Up next" / "Also ready" are uppercase letter-spaced eyebrows — dashboard feel
  - Completed list is generic history
  - Recent is closest to useful but lacks social presence
  - Hardcoded radii: 4, 14

### CREW

- **Strongest object**: Crew header card (surfaceShadow) — too loud
- **Second strongest**: Pass/QR presentation
- **Issues**:
  - Crew header has massive shadow — old generation
  - Hardcoded radii: 28, 20
  - "Find people" / "Your crew" use titleMedium — inconsistent with Compete
  - People surface has 1.25px border — heavier than divider

### PROFILE

- **Strongest object**: Identity card (custom inline shadow) — too loud
- **Second strongest**: Stats row
- **Issues**:
  - Identity card has loud custom shadow — old generation
  - Stats row is generic dashboard strip
  - Race history rows don't match Trackside race-row language
  - "Race history" / "Account" / "Legal" use _SectionLabel — inconsistent
  - safeTop + 20 top padding (MainShell already handles safe area)

### BOTTOM NAV

- **Issues**:
  - 2px navy border — too heavy
  - hardSmall shadow — too loud
  - Verify button has hardSmall — too loud
  - 28px hardcoded radius
  - Competes with screen heroes on every screen

## Typography Hierarchy Issues

- Compete: "Compete" (30px navy), section headers use `sectionKicker` (uppercase)
- Verify: "Verify" (30px navy), "Up next"/"Also ready" use `labelSmall` w800 letterSpacing 0.8
- Crew: "Crew" (32px navy), sections use `titleMedium` w700
- Profile: "Profile" (32px navy), sections use `_SectionLabel`

**Inconsistent**: 30px vs 32px screen titles. Section headers use 4 different styles.

## Border/Radius Issues

- Hardcoded: 4, 14, 20, 28
- NuvoRadii tokens: xs, sm, md, card, lg, hero, pill, badge
- Too many rounded rectangles — feels generated

## Color Issues

- Blue overuse: Verify "See all" links, segment selected text, verified status
- Navy overuse: Profile stats, account rows
- Compete is disciplined; other screens are not

## Priority Actions

1. Flatten bottom nav (remove hard shadow, reduce border)
2. Flatten Verify segment control
3. Flatten Crew header card
4. Flatten Profile identity card
5. Redesign Compete Quick Starts
6. Redesign Compete Waiting/Finished summaries
7. Redesign Verify Up Next card composition
8. Unify section header typography
9. Unify top spacing across screens
10. Remove hardcoded radii
