# Nuvo three visual modes — design QA

## Evidence

- Source visual truth:
  - `qa/source-starting-line.png` — 853 × 1844 px
  - `qa/source-trackside.png` — 853 × 1844 px
  - `qa/source-crew-momentum.png` — 853 × 1844 px
- Final Flutter-rendered implementation:
  - `qa/final-starting-line-390x844.png` — 390 × 844 px
  - `qa/final-trackside-390x844.png` — 390 × 844 px
  - `qa/final-crew-momentum-390x844.png` — 390 × 844 px
  - `qa/final-mode-selector-390x844.png` — 390 × 844 px
- Source-versus-final comparisons:
  - `qa/comparison-starting-line-390x844.png`
  - `qa/comparison-trackside-390x844.png`
  - `qa/comparison-crew-momentum-390x844.png`
- Transparent overlays:
  - `qa/overlay-starting-line-390x844.png`
  - `qa/overlay-trackside-390x844.png`
  - `qa/overlay-crew-momentum-390x844.png`
- Enhanced difference images:
  - `qa/difference-starting-line-390x844.png`
  - `qa/difference-trackside-390x844.png`
  - `qa/difference-crew-momentum-390x844.png`

## Normalization

- Target viewport: 390 × 844 logical pixels.
- Implementation density: 1 device pixel per logical pixel.
- Each 853 × 1844 source was downsampled to 390 × 844 with a high-quality
  Lanczos filter before comparison.
- Source and implementation aspect ratios differ by less than 0.2%.
- State: active race, 65 / 100 progress, four race participants in the graphic,
  top-three standings, recent activity, and Submit proof as the primary action.
- The fixed QA data is compile-time-only. Production continues to use real race,
  participant, progress, avatar, and activity data.

## Required fidelity surfaces

- Fonts and typography: Manrope is used throughout. The final hierarchy matches
  the references' large score numerals, strong race title, compact uppercase
  labels, tabular values, and restrained navigation labels.
- Spacing and layout rhythm: the three full-view comparisons confirm matching
  content order, primary margins, dark/light section proportions, graphic
  placement, leaderboard density, button placement, and persistent navigation.
- Colors and visual tokens: Starting Line uses bright neutral white, Trackside
  uses the deep navy race environment and electric-blue course, and Crew
  Momentum uses warm off-white with blue, ochre, and sage crew accents.
- Image and asset fidelity: the existing transparent Nuvo mark is used directly.
  Production uses real participant photos when supplied by application data and
  the existing initials fallback otherwise. The fixed QA fixture intentionally
  exercises that honest fallback instead of inventing profile images.
- Copy and content: the selector says “Choose your Arena” and “Pick how you want
  to view the race.” Arena copy uses race, crew, progress, leaderboard, finish
  line, and Submit proof language.
- Accessibility and interaction: selector choices expose button semantics,
  progress graphics expose text equivalents, actions remain at least 48 logical
  pixels high, mode choice opens immediately, and reduced-motion behavior is
  preserved by the existing shared motion system.

## Full-view findings

- Starting Line matches the source's open editorial hierarchy, split blue/ink
  score, remaining-distance copy, horizontal marker track, checkered finish,
  full-width squared action, flat standings, activity, and light navigation.
- Trackside matches the source's continuous navy upper environment, compact
  identity header, centered score, large multi-lane course, crew markers with
  ranks, narrower squared action, hard navy-to-white boundary, standings,
  activity, and dark navigation.
- Crew Momentum matches the source's warm open composition, compact divided
  header, central score, four-person orbit, counterclockwise blue progress path,
  squared action, dense standings, activity, and light navigation.

Focused region captures were not required because the source and final screens
are available in normalized native-size pairs and every important label,
graphic, button edge, avatar marker, divider, and navigation item is legible.
The overlay and difference images provide the focused geometry evidence.

## Comparison history

### Pass 1

- P1 — Trackside still resembled the rejected implementation: light outer
  header, rounded dark card, and generic percentage ring.
- P1 — Crew Momentum still resembled the rejected implementation: enclosing
  card, generic percentage ring, and no open portrait orbit.
- P2 — Starting Line lacked split score color, source lockup, recent activity,
  and a checkered finish.

Fixes:

- Replaced Trackside with a full-width navy environment and custom multi-lane
  course using real participant positions and avatar data.
- Replaced Crew Momentum with an open four-position crew orbit.
- Added the source lockup, split score, finish-line track, flat standings, and
  source hierarchy to Starting Line.

### Pass 2

- P2 — Trackside's goal text rendered with the wrong optical weight and its
  course sat too low.
- P2 — Crew Momentum showed only three members and its blue arc ran in the
  opposite direction.
- P2 — The temporary QA selector miniature overflowed its frame by five pixels.

Fixes:

- Corrected the Trackside score weight and moved the course behind the score.
- Added a fourth participant, enlarged the crew composition, and reversed the
  progress sweep.
- Tightened the Trackside selector miniature.

### Pass 3

- P2 — Trackside crew markers were inside the lanes rather than seated on the
  course edge.
- P2 — Crew standings were too tall to keep recent activity above navigation.
- P2 — Source buttons were squared while the implementation remained pill-like.

Fixes:

- Repositioned Trackside markers and adjusted the course depth.
- Added a dense Crew Momentum standings treatment.
- Added a mode-source action with restrained six-pixel radii and matched the
  narrower Trackside action width.

### Final pass

- Evidence: all three `qa/comparison-*-390x844.png` files.
- No actionable P0, P1, or P2 visual findings remain.

## Remaining acceptable differences

- QA participants without supplied photos render the production initials
  fallback. Real profile photos appear when the backend provides them.
- Source portraits and names are examples; production keeps real names, ranks,
  progress, and activity.
- Bottom-navigation icons use the app's existing Cupertino icon set rather than
  copying the source artwork.
- Starting Line's top lockup is slightly more compact before the physical
  device safe area is applied.

## Runtime and interaction verification

- `flutter analyze --no-fatal-infos`: exit 0, no findings.
- `flutter test`: exit 0, all 90 tests passed.
- Deterministic Flutter render: all four 390 × 844 capture tests passed.
- Physical iPhone: debug build signed, installed, and launched successfully on
  `Shresh’s iPhone` (`00008110-001079C12183401E`).
- Authentication behavior was exercised on launch: the existing expired
  session correctly returned to the unchanged sign-in flow.
- iOS Simulator could not run because the locked Google ML Kit pods do not
  support the Apple Silicon iOS 26 simulator architecture. No dependency or
  protected native-file change was made to bypass that baseline constraint.
- The local web QA build is served on port 7360. Automated Chrome inspection was
  unavailable because the ChatGPT Chrome Extension connection could not be
  established, so no final Chrome-console claim is made.

## Final result

final result: passed
