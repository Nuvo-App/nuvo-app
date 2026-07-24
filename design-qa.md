# Nuvo approved-mode replication — design QA

## Scope and visual truth

The newly supplied comparison images supersede the earlier inferred Trackside
and Crew Momentum references. In each comparison, only the left 390 × 844 panel
is approved; the right panel is the rejected implementation.

Approved source crops:

- `qa/trackside_approved_source.png` — 390 × 844
- `qa/crew_momentum_approved_source.png` — 390 × 844
- `qa/source-starting-line.png` — the previously approved Starting Line source

Final Flutter captures:

- `qa/final-mode-selector-approved-390x844.png`
- `qa/final-starting-line-approved-390x844.png`
- `qa/final-trackside-approved-390x844.png`
- `qa/final-crew-momentum-approved-390x844.png`
- `qa/pass4-trackside-430x844.png` — corrected wider-iPhone render

Exact source measurements are recorded in:

- `qa/measurement-trackside.md`
- `qa/measurement-crew-momentum.md`

## Comparison evidence

Trackside:

- `qa/final-trackside-approved-side-by-side.png`
- `qa/final-trackside-approved-overlay-50.png`
- `qa/final-trackside-approved-difference.png`

Crew Momentum:

- `qa/final-crew-momentum-approved-side-by-side.png`
- `qa/final-crew-momentum-approved-overlay-50.png`
- `qa/final-crew-momentum-approved-difference.png`

The side-by-sides preserve each source and implementation at native 390 × 844,
so the full view keeps typography, dividers, avatars, progress paths, buttons,
standings, activity, and navigation readable. Separate focused crops were not
needed.

## Normalized state

- Viewport: 390 × 844 logical pixels at 1 device pixel per logical pixel.
- Wider-iPhone verification viewport: 430 × 844 logical pixels at 1 device
  pixel per logical pixel. The full-bleed surfaces remain 430 pixels wide while
  the approved composition is centered at its native 390-pixel width.
- Race: First to 100 Pushups.
- Current progress: 65 / 100.
- Trackside standings: You 65, Alex R. 48, Maya L. 31.
- Crew Momentum standings: You 65, Alex 58, Jordan 42.
- Primary action: Submit proof.
- The fixed state is compile-time visual-QA data only. Production data flow,
  race actions, routing, authentication, and backend contracts are unchanged.

## Fidelity review

### Trackside

- The full-width navy race environment ends at y=465, matching the approved
  hard transition to the standings surface.
- Logo, Arena label, hierarchy, split score, remaining copy, five-lane
  elliptical course, three crew positions, and 241 × 52 action match the
  measured source structure.
- The standings, activity row, and 74-pixel dark navigation use the approved
  vertical density and content.
- The course is a purpose-built painter because it is a scalable progress
  visualization, not a substituted image asset.

### Crew Momentum

- Warm open canvas, divided header, race title, 184-pixel progress orbit,
  four participant positions, score badges, ranks, chase copy, and 344 × 44
  action match the approved composition.
- The active path sweeps clockwise from the upper-right to the lower-left.
- Open standings, stacked activity copy, and 69-pixel light navigation match
  the approved source structure.

### Starting Line and selector

- Starting Line remains available and unchanged as the third visual mode.
- The post-login visual selector still exposes Starting Line, Trackside, and
  Crew Momentum before entering Arena.

## Comparison history

### Trackside pass 1

- P1 — The rejected generic ring was replaced by the approved full-width
  multi-lane course.
- P2 — The dark environment, hard section boundary, and source-sized action
  were established.

### Trackside pass 2

- P2 — Course depth, score hierarchy, lane count, and marker positions were
  measured against the approved crop and corrected.
- P2 — The standings state was corrected to 65 / 48 / 31.

### Trackside pass 3

- P2 — Active-path endpoints, avatar centers, row heights, progress bars,
  activity spacing, and navigation height were tightened.

### Trackside final pass

- Evidence: `qa/final-trackside-approved-side-by-side.png`.
- No actionable P0, P1, or P2 layout finding remains.

### Trackside real-device correction pass

- P1 — On a wider iPhone, the 390 × 465 hero was being enlarged to the full
  device width by `AspectRatio` plus `BoxFit.fill`. This made the hero roughly
  10% too tall, enlarged every heading and marker, compressed the standings
  below it, and produced the deformed screen reported from the physical phone.
- Fix — The navy hero and white standings remain full bleed, but their content
  now stays at the approved 390-pixel design width and 465 / 305 pixel heights.
  The bottom-navigation content is also capped at 390 pixels instead of
  spreading across the wider device.
- Post-fix evidence: `qa/pass4-trackside-430x844.png`.
- Normalized comparison evidence:
  `qa/pass4-trackside-side-by-side.png`. Its implementation half is the centered
  390-pixel crop from the 430-pixel browser render.
- Result — the wider viewport preserves the approved outline, formatting,
  density, and section proportions without horizontal or vertical deformation.

### Crew Momentum pass 1

- P1 — The rejected generic ring/card treatment was replaced with the approved
  open four-person orbit.
- P2 — Header, title, action, standings, and activity were placed against the
  source measurements.

### Crew Momentum pass 2

- P2 — Orbit diameter, arc direction, portrait centers, score badges, rank
  labels, and chase copy were corrected.

### Crew Momentum pass 3

- P2 — Button position, row density, progress bars, activity wrapping, and
  navigation height were tightened.

### Crew Momentum final pass

- Evidence: `qa/final-crew-momentum-approved-side-by-side.png`.
- No actionable P0, P1, or P2 layout finding remains.

## Remaining visible differences

- P3 / asset blocker — the approved source uses specific portrait photographs
  that are not present in the repository or supplied attachments. The QA
  fixture therefore shows the existing initials fallback. Production already
  renders each member's real `profilePhotoUrl` when available. The source
  portraits were not extracted from screenshots or fabricated.
- P3 — the exact source font files were not supplied. The implementation uses
  the app's existing Manrope family, producing small optical differences in
  character width and rasterization.
- P3 — Flutter web and the raster source use different text antialiasing, most
  visible in small uppercase labels and navigation captions.
- P3 — Crew Momentum's row dividers retain the stable Flutter inset rather than
  forcing the final few pixels with an overflow layout.

These are documented constraints, not hidden claims of pixel identity.

## Interaction and runtime verification

- Mode selector: all three choices were opened in Chrome at 390 × 844.
- Primary actions and production routing remain wired through the existing
  callbacks; the compile-time QA surface intentionally uses no-op callbacks.
- Final Chrome render completed without a new console error after the final hot
  restart. A transient overflow experiment produced errors during iteration and
  was reverted before the final captures.
- Wider-iPhone Trackside rendering was verified at 430 × 844 after the
  responsive correction.
- `flutter analyze --no-fatal-infos`: passed with no issues.
- `flutter test`: passed, all 92 tests.
- `git diff --check`: passed.

## Protected areas

No authentication, AI Motion Proof, motion validator, camera/ML bridge,
dependency, backend, race API, race repository, or race controller file was
edited for this task.

`ios/Runner.xcodeproj/project.pbxproj` was already modified in the working tree
before this task and was preserved without edits.

## Final result

final result: passed
