# Nuvo UI Humanization Plan

## Objective

Make Nuvo look and feel like a native, competition-first iOS app designed by a human, not assembled from a generic component kit. The current UI is functionally correct but reads as AI-generated because of overuse of cards, identical rounding, saturated accent color, and non-native navigation.

This plan targets **Arena first**, then defines the rules for rolling the same discipline to the rest of the app.

---

## Core system requirements

These constraints apply to every change. Breaking any of them requires explicit approval.

1. **One hero per screen.** No two elements can fight for primary attention.
2. **One accent color.** Royal blue is reserved for interactive states and primary actions only.
3. **Two surface levels.** Background + elevated. No card inside a card.
4. **Three border radii.**
   - Sharp / 8 px: buttons, pills, controls.
   - Soft / 16 px: list rows, rail items.
   - Round / 100%: avatars.
5. **Content before chrome.** If information can live on the background or in a list row, it does not get a card.
6. **Native iOS first.** Use iOS tab bar, SF Symbols, system materials, spring animations, and haptics. No floating pill nav, no Material shadows, no oversized FAB.
7. **Asymmetric rhythm.** Left-align text rows, vary section spacing, let whitespace breathe.
8. **Real data, real people.** Photos, maps, or illustrations where possible; initials fallbacks must be subtle.
9. **Motion with purpose.** Animations confirm interaction; they do not decorate.
10. **No redesign of backend contracts.** Data shapes, API routes, and navigation routes stay unchanged.

---

## Why the current UI feels AI

| Symptom | Root cause |
|---|---|
| White cards everywhere | Chrome-first instead of content-first. |
| Same rounding on every surface | No radius system; everything uses 18–24 px. |
| Blue on ring, button, pill, rank, percent | Accent color used as decoration instead of signal. |
| Floating pill nav | Android/Material pattern, not iOS. |
| Color-ring avatars | Stock component look; no photo priority. |
| Big filled blue pill buttons | Bootstrap-era pattern. |
| `easeOutCubic` fades | No physical motion language. |
| Perfect centering / equal gaps | Lacks the rhythm of real layouts. |

---

## Phase 1 — Arena

### 1. Bottom navigation

**Current:** Floating pill nav with large center `+` button, shadow, custom icons.

**Target:** Native iOS tab bar.
- Four items: Arena, Compete, Crew, Profile.
- Use SF Symbols (`bolt.fill`, `flag.fill`, `person.2.fill`, `person.fill`) or custom line-art matching SF Symbol stroke weight.
- Translucent system-material background, no shadow.
- Center `+` removed; primary creation moves to the Compete tab or a top-right button.
- Respect safe area / home indicator.

### 2. Active race area

**Current:** White card containing movement pill, title, percent pill, ring, rank row, leaderboard, CTA.

**Target:** Content-first layout.
- Remove the white card container entirely.
- Place title + context directly on the background.
- Movement pill becomes a small, subdued label (not a bright blue badge).
- Percent moves out of the ring and becomes a large inline number or disappears in favor of the ring arc itself.
- Competition Ring becomes the clear hero, full-width or centered large, with no surrounding card.
- Leaderboard becomes a clean grouped list with left-aligned names, right-aligned values, and thin separators.
- CTA becomes an iOS-style rounded rectangle button, full-width but not a giant pill.

### 3. Competition Ring polish

- Thinner arc (reduce thickness).
- Progress color stays blue; background track stays subtle gray.
- Remove colored rank rings (gold/silver/bronze) from avatars; use a thin white ring + soft shadow.
- Current user gets a subtle accent ring, not a pulse.
- Center label removed or replaced with a small status label below the ring.
- Markers should feel like photos placed on a track, not badges.

### 4. Leaderboard row

- No row background highlight.
- Rank number left-aligned, muted for non-podium.
- Avatar + name grouped together.
- Value right-aligned in monospace/tabular figures if available.
- Hairline separator between rows, full width or indented from avatar.

### 5. Race Rail

**Current:** Horizontal cards with shadow, progress strip, avatar stack, chevron.

**Target:** Horizontal rail that feels like a row of race posters.
- No shadow; subtle border or no border.
- Larger image/map/texture area per item.
- Title + short status overlay or below.
- Progress as a thin line, not a fat bar.
- Keep horizontal scroll, but make each item feel distinct.

### 6. Activity feed

- Convert cards to simple horizontal rows or keep small cards but remove shadows.
- Use SF Symbols for activity type.
- Reduce to avatar, actor, action, race, time.

### 7. Header

Keep the minimal top bar direction:
- Greeting + one-line status.
- Notification icon only; profile moves to the Profile tab.
- Live pill stays small and neutral.

---

## Phase 2 — Global rules (apply after Arena ships)

1. **Tab bar** applied to Compete, Crew, Profile.
2. **Card audit:** Remove every card that contains only text and a button.
3. **Button audit:** Convert all filled pill CTAs to iOS rounded rect or text buttons.
4. **Color audit:** Move every non-interactive blue element to navy, gray, or semantic green/red.
5. **Typography audit:** Reduce to 4 sizes (display/title/body/caption) and 3 weights.
6. **Motion audit:** Replace `easeOutCubic` fades with spring and slide transitions.
7. **Icon audit:** Replace filled custom icons with line-art matching SF Symbol style.

---

## Non-goals

- No new screens or routes.
- No new backend endpoints or data shapes.
- No illustration library unless explicitly requested.
- No dark-mode pass in this phase.
- No redesign of auth, AI Motion Proof, camera bridge, motion validators, or iOS native files.

---

## Success criteria

1. Arena screen no longer looks like a stack of cards.
2. A user can describe the screen in one sentence: "One race with a ring and a log button."
3. Switching between races with 1, 3, or 10+ participants feels stable and smooth.
4. The app passes a 5-second "AI check": no generic kit styling, no floating FAB, no overuse of blue.
5. `flutter analyze --no-fatal-infos` remains clean.
6. iOS release build succeeds.

---

## Rollout order

1. Bottom nav → native tab bar.
2. Active race card → content-first layout.
3. Ring polish.
4. Leaderboard + rail refinement.
5. Color and typography pass.
6. Motion and haptics pass.

Each step is a standalone, reviewable change. We do not stack all of them into one diff.
