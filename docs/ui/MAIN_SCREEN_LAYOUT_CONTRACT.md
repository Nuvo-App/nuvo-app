# Nuvo Main Screen Layout Contract

The shared composition rules for Nuvo's five main tabs: Arena, Compete,
Verify, Crew, Profile. These rules are load-bearing — every first-viewport
change on a main tab is measured against them, and
`test/first_viewport_contract_test.dart` enforces the geometry invariants.

## 1. First Viewport Principle

The initial viewport is intentionally composed. When a tab opens, what sits
above the persistent bottom dock must read as one designed surface — not a
scrolling webpage that happens to be clipped by the nav. The user should
feel "this screen was designed for this phone," never "there's more stuff
below and the nav covered it."

## 2. Bottom Dock Exclusion Zone

Content cannot disappear underneath the persistent dock. The exclusion zone
is `NuvoBottomNav.bottomPadding(context)` — dock height + device safe-area
inset + Verify's raised edge + clearance gap. This is the ONLY source of
dock geometry; never hardcode a dock height in a screen.

## 3. Breathing Zone

The last first-viewport component ends slightly above the dock — a small,
deliberate gap, tokenized as `NuvoSpacing.dockBreathing` (14px). Small by
design: content should end confidently, not float in a void.

## 4. Logical Fold

When content continues past the first viewport, the fold lands on a
component boundary — a row, tile, or section either renders whole or starts
below the fold. Never a half-visible row under the nav. An intentional
continuation cue (e.g. "See all", a fully-visible section label is not one)
is welcome.

```
GOOD                              BAD
final visible item                final visible item
                                  ┌ HALF OF ANOTHER ROW ┐
   small breathing zone           ███████ DOCK █████████
█████████ DOCK █████████

BAD TOO
final visible item


   enormous dead area

█████████ DOCK █████████
```

## 5. Never Shrink Everything to Fit

Scrolling is preferable to destroying component hierarchy. Cards keep
presence, typography stays readable, touch targets stay generous. When a
layout feels cramped, first reconsider section spacing, what belongs above
the fold, scroll boundaries, and list height — before touching component
size. Four polished tiles beat five crushed ones.

## 6. Density

Avoid both giant unexplained whitespace and crushed content. Every stretch
of space should feel intentional. If the middle of a screen has dead air
while the bottom is crowded, fix the distribution — don't add padding and
don't shrink things.

## 7. Hero Screens

Arena and Compete prioritize the primary race interaction (next move,
featured race). They should feel like siblings: same outer gutters, same
major-section rhythm, same card confidence, same relationship to the dock —
without identical layouts.

## 8. Lists

Rows near the fold are intentionally visible or below it — never
accidentally bisected. List-bearing bodies split at the fold with
`SliverFold` (`lib/core/widgets/nuvo_fold.dart`): the fold measures
`remainingPaintExtent` once, hands the caller a `NuvoFoldBudget`, and the
caller renders the whole units that fit, then
`SizedBox(height: fold.seam(used))`, then the rest. The seam guarantees
continuation content begins at or past the viewport's bottom edge.

## 9. Responsive Height

Short phones (≈568pt) scroll sooner; tall phones (≈932pt) breathe more.
Neither should look accidental. Layouts respond by moving content below the
fold — never by overflow and never by shrinking components. Test at 320 /
390 / 430 width and at short, standard, and tall heights.

## 10. Persistent Navigation

Every main-tab layout accounts for actual dock geometry via
`SliverFold.reserveOf(context)` =
`NuvoBottomNav.bottomPadding(context) + NuvoSpacing.dockBreathing`. Fold
splits must use this reserve; sections that can't fit whole go below it.

## 11. Testing Requirements

`test/first_viewport_contract_test.dart` pumps the real screens inside
`MainShell` at short/standard/tall viewports and asserts:

- no render overflow (`tester.takeException()` is null);
- no first-viewport component rect straddles the dock's top edge —
  every component is fully above it or fully below the viewport;
- the last visible component keeps positive breathing clearance;
- fold-displaced content still exists in the tree (scrollable, not removed).

Keep these as geometry invariants — never pixel-exact goldens that fail
when text moves 2px.

## 12. Where Each Screen Splits

| Screen  | Fold point                                                        |
|---------|-------------------------------------------------------------------|
| Arena   | `SliverFillRemaining` pins the Leaderboard label at a section gap, reserves the dock zone, centers the standing in what remains |
| Compete | `_QuickStarts` tile rows split inside `SliverFold` — whole rows only |
| Verify  | Already composed; no split needed                                  |
| Crew    | Tabs own their scroll; fold handled per-tab                        |
| Profile | `Racing now` / `Recent results` row caps computed inside `SliverFold`; sections that can't place a single whole row render below the seam |
