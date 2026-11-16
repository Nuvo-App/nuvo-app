# Onboarding v2 — motion brief (all five intro pages)

Written before the redo. Failure being fixed: the pages were bland, effects
visibly hit container edges ("limits"), and the climaxes did not feel like
climaxes. Bar for every page: one hero, one idea, full-bleed, big type, a real
anticipation -> slow-down -> payoff -> settle, haptics on the beats.

## What the OLD onboarding did (lib/features/onboarding/presentation/nuvo_onboarding_screen.dart, `_RacePathPainter`, `_racePath`, `_drawNuvoFlag`)

- ONE route: a cubic S-curve (start 5%/82% -> end 78%/14% of the box,
  control points at .25/.06 and .62/.98) drawn as a thick navy stroke (12px)
  with a thinner blue PROGRESS stroke (5px) on top, a blue start dot and a
  Nuvo flag (blue, navy outline) at the end.
- The racer is a single dot (navy 6.5, white 3, soft blue halo 11) that
  physically travels the path; progress = easeInOutCubic (slow start, fast
  middle, slow arrival). The route filled further with each example so "race
  anything" literally travelled toward the finish.
- The scene was scaled/centered to fit its box with a margin, so nothing
  was ever cropped. An ambient dot grid breathed behind with expanding rings
  (full-bleed, dots only, never a hard edge).
- Reused now: the route geometry, thick navy + thin blue progress stroke,
  racer dot style, Nuvo flag shape, "travel toward a finish" idea, and the
  slow-at-the-key-point speed profile (extended into a deliberate crawl).

## Reference patterns (web research)

- Headspace opens with a breathing animation: users take part before any
  copy (a single slow idea). Strava could show ten features and surfaces ONE
  (start recording). Great onboarding = one idea per screen.
  Sources: https://uxcam.com/blog/10-apps-with-great-user-onboarding/ ,
  https://www.storyly.io/post/app-onboarding-examples-best-flow
- Animation should DEMONSTRATE value (a goal being hit), not decorate; keep
  decorative loops out. Anticipation (prepare before the action) and
  follow-through (secondary motion after) are what make a payoff land.
  Sources: https://vp0.com/blogs/lottie-animations-for-onboarding-screens-free ,
  https://contra.com/p/seOAX3PZ-expressive-character-animation-for-finch-app
- Rive-style onboarding shares state across screens (one connected scene
  whose parts hand off between pages). Concept reference:
  https://contra.com/p/NrkWZZX7-stride-app-onboarding-with-rive
- Takeaways applied: full-bleed scene layer behind the text (never a boxed
  demo), large type, ONE hero per page, effects either fill the screen or fade
  before any edge, a held beat before the payoff, motion that builds one idea.

## Architecture (fixes the "boundaries breaking" defect)

- ONE full-screen scene layer per page, rendered edge to edge UNDER the text
  and CTA. No ClipRect, no inner demo box, no clipped Stack. The page's
  hero lives in a `stage` rect (between the header and the title block) with
  >= 20px margins; effects (rings, confetti) are drawn in screen space and
  fade to 0 before they need to be cropped.
- Camera push is a canvas scale about the page's focal point on a
  transparent layer: it can never expose an edge.
- Scenes slide with parallax as a whole layer (the device edge is the only
  crop).
- Play once, hold the final frame; reduce-motion = final frame + one light
  haptic.

## Per page

Timeline numbers are fractions of the page's play (4.2s; level-up 5.4s).

### 1 Race anything  (idea: a race to a finish line)
Hero: the old route, scaled to the stage. Timeline: 0-.12 route draws in;
.12-.50 YOU (big navy/white dot with blue halo) launch and run to 72%
(ease-in); .50-.80 THE CRAWL - the page slows, a slow camera push toward the
finish, two rivals close the gap, a thud at .52; .80-.88 sprint across the
line; .88 PAYOFF: flag pops, ring waves from the finish, confetti falling
across the whole screen, a large "1st" pill, white flash, strong haptic.
Edges: route inset 20px; confetti fades before the bottom.

### 2 Prove it on camera  (idea: the camera counts reps and verifies)
Hero: the app's real jumping-jack figure, LARGE (78% of width) and centered.
Full-bleed scan frame: four corner brackets slide in from beyond the screen
edges and lock at 14px from the edges. A three-segment rep ring around the
figure; big counter. Reps 1-2 tick (.26, .42). .50-.84 SLOW-MO: the field
dims a touch, the third segment crawls, brackets tighten, thud at .52.
.86 PAYOFF: flash, ring waves, burst, a huge "VERIFIED" stamp slams
(2.4x -> 1x), counter pops, strong haptic.

### 3 Climb the board  (idea: you overtake your way to #1)
Hero: a five-row leaderboard spanning the stage (rows >= 20px margins, big
rank/avatar/name/score). YOU start 5th and overtake four rows (ticks at
.34/.46/.58/.70), each pass a clean slide with almost no overshoot; the last
pass (2nd -> 1st) is the slow one. .78 PAYOFF: flash, ring waves, confetti
falls, the top row pulses, strong haptic.

### 4 Race with your crew  (idea: your people arrive)
Hero: six avatar faces swoop in from beyond the screen edges along curved
paths and settle with spring physics into a ring around YOU. Joins escalate
(.08 .20 .30 .38 .45 .51) with a tick and a ripple each; a counter pops per
join. .64 PAYOFF: connection lines draw in to YOU, pulse, ring waves, the
number slams to 6, strong haptic.

### 5 Level up  (idea: the XP ring fills and BREAKS into level 2)
Hero: a large XP ring with the level numeral inside. 0-.5 fast fill to 90%;
.5-.78 crawl to 98%; .78-.82 HOLD with a rising tremble (anticipation); .82
PAYOFF: the ring shatters into arcs that fly outward, three shock rings,
white flash, camera push 1.1, LEVEL 1 -> 2 slams in (big, then settles),
confetti, the badge pill and +100 XP slam in. Strongest haptic (thud + burst).

## Quality gate (before every push)

Frame strips at FULL screen 390x844 and 320x568, 8+ timestamps per page, read
for: clipped/cropped shapes, hard edges, overlapping text, empty areas.
Automated: `intro_scenes_test.dart` renders every frame of every page at both
sizes and asserts nothing paints outside the screen except fading effects
(see test), plus the existing sequence/one-play/haptics/overflow tests.
