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

Content cannot disappear underneath the persistent dock — **visibly**. The
shell paints an opaque page-colored occlusion band over the dock zone
(`_DockOcclusion` in `main_shell.dart`, dock top minus Verify's raise
through the bottom inset), so scrolled-behind content is hidden rather
than showing through the dock's transparent margins.

Layout clearance is separate from occlusion and still required: scrollable
screens reserve `NuvoBottomNav.bottomPadding(context)` — dock height +
device safe-area inset + Verify's raised edge + clearance gap — so the last
row scrolls fully above the dock. This is the ONLY source of dock geometry;
never hardcode a dock height in a screen.

Because occlusion exists, a component may geometrically straddle the dock
edge — it simply disappears behind the band. Prefer whole-unit endings for
the *first viewport composition*, but do not manufacture large seam spacers
to force "below the fold": flowing content + occlusion beats a dead zone.

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
| Arena   | Budgeted composition — hero height measured against real content plus the standings reserve; computed seam keeps "Recent activity" at/below the dock edge |
| Compete | `_QuickStarts` flows as one continuous grid — a straddling row is occluded, not seam-pushed (the seam produced a dead zone before the odd last tile) |
| Verify  | Header → segments → Up next hero → Also ready rows flow continuously; rows scroll under the dock mask naturally |
| Crew    | Tabs own their scroll; fold handled per-tab                        |
| Profile | `Racing now` / `Recent results` row caps computed inside `SliverFold`; sections that can't place a single whole row render below the seam |

## 13. First View Answers Three Questions

Every main tab's initial viewport answers all three, in this order of
visual weight:

1. **Who/where am I?** — the header + identity layer.
2. **What matters right now?** — the dominant object (hero race, live
   state, next proof).
3. **What can I do next?** — the primary action surface.

| Tab     | Who/where        | What matters now        | What I can do      |
|---------|------------------|-------------------------|--------------------|
| Arena   | Arena + greeting | next-move board, standings | Submit proof / New / Join |
| Compete | Compete + status | featured race, my races | Start / Join / Quick starts |
| Verify  | Verify           | next proof, ready queue | Begin verification |
| Crew    | Crew + people    | live/social state       | Race someone, react |
| Profile | Profile + card   | featured race, latest result | See all / race rows |

Do not solve composition by reducing content — redistribute it.

## 15. Profile = Me + Performance + Settings

Profile answers five questions, in this strength order:

1. **Who am I?** — identity card (avatar, name, handle, Member pass,
   My Nuvo). Supportive stats strip: Racing / Wins / Win rate — never more.
2. **What am I doing right now?** — `Racing now`, a personal status module.
3. **What did I accomplish recently?** — `Recent results` + one earned mark.
4. **What else have I raced?** — `Other` history, below the seam.
5. **How do I control it?** — quiet settings groups: `Your Nuvo` → `App` →
   `Account` → `Legal`.

**One-current-race rule** — `Racing now` features exactly one active race in
the first viewport: the one closest to its finish line (viewer
`progressPercent` desc). The rest collapse behind an inline `See all` —
Profile is not a second Arena; it shows where *I* stand, not the whole
board.

**Featured-race meta** — title, placement (`#8`), canonical progress
(`39 / 50 reps`), progress track, participant avatars, and one derived
context: `N reps to finish · M racers` via `targetValue − progressValue`
formatted by `raceScoreLabel`. Races without a fixed target fall back to
`movement · M racers`; a race at the start line stays quiet (no empty bar).

**Recent-result rule** — placement is earned truth: `finalStandings`
first, positional rank as fallback. `1ST` is gold with a trophy; every
other placement is neutral. Never paint a non-win gold.

**No-fake-personal-metric rule** — the only extra personal module is
**Best finish**: the lowest `rankForUser` across completed races (gold
trophy on a win, neutral medal otherwise, canonical score on the right).
It hides entirely with zero results. Do not add streaks, XP, levels,
personal bests per activity, or head-to-head records unless a canonical
field/helper exists — comparable placements are all we have today.

**Settings hierarchy** — page-level rows under section labels, hairline
dividers aligned to the text column; no card sheets. `Your Nuvo`: My Nuvo,
Member pass, Notifications. `App`: Appearance (the real persisted
`nuvoThemeModeProvider` toggle — not decorative), Replay the guide
(demo-gated), Presentation mode (eligibility-gated), Rive Calibration
(`kDebugMode` only). `Account`: Edit profile, Sign out, Delete account.
`Legal`: Privacy, Terms. Only real routes/actions ship — no placeholder
destinations.

**Edit-control contract** — the header's edit affordance is a compact
icon-only `NuvoPressable` in the standard right gutter, ~44px hit target.
No "Edit" text pill; Edit profile also lives as an Account row.

**Dock/scroll behavior** — unchanged: `SliverFold` splits whole units
across the fold, the seam spacer keeps the dock edge intentional, and
content reserves `NuvoBottomNav.bottomPadding(context)` — scroll-behind +
occlusion, never giant spacers.

## 14. Verify Is a Proof Command Center

Verify's product question is **"what can I prove right now, and what will
that proof change?"** — not "here are some races."

**Ready ordering** — closest to the finish line leads. The queue sorts by
canonical distance to goal (`viewerContext.goalRemaining`, else
`target − progress`), stable on the server's order for ties. The race that
needs the least proof is always "Up next" — never a hidden ranking.

**Up next hero** — shared `RaceHero` + one `contextNote` line under the
meta: canonical stakes copy from `ChaseContext` ("Beat Noah. 14 to take
#2" / "Defend your lead. Priya is 3 behind" / "Set the pace…"), falling
back to "N reps left". Blue text — forward action. If a fact isn't in
`viewerContext`/participants, it isn't on the card.

**Also ready rows** — flat level-0 rows, no cards. Meta carries real
state, not decoration:

- `0` progress → `Pushups · Start line · 8 racers`
- in progress, multi-racer → `Squats · 12 / 25 reps · #4 · 13 reps left`
- solo → same shape minus the rank

A thin `RaceProgress` track under the meta ties the queue to the race
language used by the hero and Compete rows.

**Completed** — consequence, not queue. Row meta is
`movement · Won|Finished|Goal reached · {ago}` (canonical `winnerUserId`,
`raceIsCompleted`, `completedAt`); the ordinal still shows final rank.

**Recent** — proof history, not just a log. Meta is
`who · movement · +N reps · {ago}` (the viewer's own moves read "You");
the right side stacks the verdict (`Verified` / `Not counted` /
`Under review`) over the canonical rank move (`#9 → #8`) when the server
recorded one.

**Color semantics on Verify** — blue = ready/action/progress;
green = verified/completed; gold = rank/win only; red = rejected/destructive
verdicts; the sliding segment pill already follows this (blue / success /
neutral-tan for Recent).

## 16. Main Tab Surface Contract

Every main-tab root must draw its structural colors from
`context.themeColors` (`NuvoThemeColors` on the active `ThemeData`),
never from light-only `NuvoColors` constants.

- Page root / scaffold background → `c.page`
- Cards and content surfaces → `c.surface`
- Tinted panels / wells / viewer highlights → `c.panel` / `c.panelLight`
- Primary text and structural ink → `c.ink`; secondary → `c.inkMuted`,
  `c.inkSubtle`, `c.inkDim`
- Borders → `c.border`; hairlines → `c.divider`; progress tracks → `c.track`
- Hard offset shadows → `AppShadows.hardOffset(c.inkShadow, offset: ...)`,
  never the light-only `hardSmall` / `hardMedium` / `hardLarge` constants

`NuvoColors` constants remain correct only for semantic accents (action
blue, success, danger, warning, gold/podium), brand chrome (logo marks,
the navy member pass), and foregrounds sitting on top of a semantic
surface (white on action blue).

Dark mode must be compositional, not shell-level: `AppTheme.dark()`
registers `NuvoThemeColors.dark`, and the persisted mode comes from
`nuvoThemeModeProvider`. A page that reads correctly in light but hardcodes
a light root is a bug — fix the shared primitive or the screen's tokens,
never patch the shell.

## 17. Content Flow Contract

Short content flows at normal section rhythm. Do not vertically
distribute sections to fill the viewport and do not reserve invisible
space for rows that are not rendered.

- `fold.seam(used)` exists to push the *fold-straddling* continuation
  past the viewport edge — it belongs between a fold-budgeted list and
  its remainder (§8). Do not use a seam to relocate later page sections:
  a seam after the last placed row pushes every following section a full
  remaining-viewport away, which is how Profile's dead gap happened.
- If the content after the fold isn't a capped list, render it directly —
  no seam, no `SliverFillRemaining` pinning, no `Spacer` to reach the dock.
- The dock owns bottom occlusion (`NuvoBottomNav` + dock reserve); pages
  own content flow. A page may end above the dock with honest breathing
  room — that is a feature, not a void to fill.
