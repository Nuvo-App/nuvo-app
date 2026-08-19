# Nuvo Onboarding Redesign Model

Status: design model only. No product behavior changes are defined by this
file until the implementation is approved.

## Product Boundary

The splash screen owns the welcome moment. Onboarding owns a short visual
explanation and one decision:

> What do you want your first fitness race to help you do?

After that decision, the user enters account access and then the real Nuvo
app. The first-use tutorial teaches the user by helping them create a real
race in Compete.

```text
Splash
  -> Welcome to Nuvo
  -> Your movement becomes progress
  -> AI Motion Proof
  -> Fitness goal
  -> Practice preview
  -> Account access
  -> Profile, only when required
  -> Real Compete screen
  -> Guided first race
  -> Real race leaderboard
```

The explanatory pages are short and visual. The onboarding is complete when the
user's first race reaches its start line, not when the user has swiped through
a set of pages.

## New Onboarding Sequence

The onboarding should feel like a short product demonstration that turns into
the user's first practice session. It must not feel like a slideshow of empty
marketing pages.

There are four explanation screens, one goal screen, and one practice screen.
Each screen has one visual object that changes over time.

### Page 1: Welcome To Nuvo

This keeps the existing splash visual language:

- splash animation settles into the Nuvo wordmark,
- white canvas with moving electric-blue atmosphere,
- navy and blue curved race line appears beneath the mark,
- blue start dot and finish flag establish the visual metaphor.

Copy:

```text
Welcome to Nuvo
Your real goals become races your crew can see.
```

Bottom action: `See how it works`

The page should feel alive for a few seconds before the action becomes the
focus. It should not immediately show configuration controls.

### Page 2: Your Movement Becomes Progress

Show one fake but clearly labeled example race:

```text
FIRST TO 10 PUSHUPS

You                  6 / 10
Maya Chen            4 / 10
Priya Nair           2 / 10
```

Visual behavior:

- the rows begin with equal progress,
- the You row moves upward,
- the blue progress bar grows,
- the rank number changes from 3 to 1,
- the other rows shift down with a short, deliberate spring.

Copy:

```text
Every rep changes your position.
```

This teaches the leaderboard before the user has to create anything.

### Page 3: AI Motion Proof

Show a mock camera frame, not the live camera:

- simplified person silhouette in navy,
- electric-blue landmark points at shoulders, elbows, hips, and knees,
- a small movement arc showing the body moving down and up,
- a count changing from `04` to `05`,
- a proof status changing from `Checking` to `Verified`.

The mock should look like a product visualization, not a fake camera result.
Add a visible label:

```text
EXAMPLE PROOF
```

Copy:

```text
Nuvo checks the movement before it moves the board.
```

Supporting line:

```text
AI Motion Proof reads movement on your device and confirms the rep before your
crew sees the update.
```

Do not imply that this screen has verified the actual user. It is an
explanation only.

### Page 4: The Board Moves

Show the full proof sequence as three connected states, not three separate
cards:

```text
SUBMIT PROOF  ->  AI CHECKS IT  ->  BOARD MOVES
```

The same blue progress mark travels through the sequence. The leaderboard row
updates at the end.

Copy:

```text
Proof turns effort into visible progress.
```

This page explains why Nuvo is different from a private counter or habit
tracker.

### Page 5: Choose Your Training Direction

This is the current goal screen, but it should be redesigned as the final
explanation-to-action transition.

Headline:

```text
What do you want to train for?
```

The race visual stays in the center. The goal choices remain compact and
directly connected to the race title and target.

Available goals:

- Strength
- Endurance
- Consistency
- Crew
- Milestone

When a goal changes:

- movement title changes,
- target changes,
- path label changes,
- example progress text changes.

The user should feel like they are configuring one race, not selecting a
preference from a settings list.

### Page 6: Practice The Move

After selecting a goal, onboarding enters a practice screen before auth or the
main app tutorial.

This is not real proof and must be labeled clearly:

```text
PRACTICE MODE
```

Structure:

- bounded mock camera area,
- one animated movement silhouette,
- blue landmarks moving through a clean repetition,
- large counter such as `0 / 3`,
- instruction: `Follow the motion once`,
- progress line beneath the counter.

The user taps `Practice` and watches three example repetitions complete. They
can tap `Try again` to replay the practice animation.

The purpose is to explain the rhythm of AI Motion Proof without requesting
camera permission or pretending that the user's movement was verified.

After the practice animation reaches `3 / 3`, show:

```text
That is how proof moves the board.
```

Primary action: `Create my first race`

This action moves to account access while carrying the selected fitness goal.

## Visual Diagnosis Of The Current Screen

The current screen is not failing because it has too many controls. It fails
because the controls do not form one visual object.

- The splash mark is reduced to a small, low-contrast header image.
- The large headline consumes the upper half of the viewport without helping
  the user make a decision.
- The race path is decorative and visually disconnected from the goal choices.
- The goal selector is a bordered container holding five unrelated controls.
- The two-row wrapping makes the selector read like a settings panel.
- The lower CTA is visually strong but its wording is awkward and does not
  complete a meaningful action.
- The screen says `1 / 1`, which adds progress chrome without showing progress.
- The empty space between headline, race path, selector, and CTA is not being
  used to create a sense of motion or completion.
- The page does not show what changes when a goal is selected.
- The race path does not visibly complete, so the user is not participating in
  the onboarding.

## Visual System

### Canvas

- Background: the same near-white canvas as the splash screen.
- No full-page cards or stacked panels.
- One central composition spanning the middle of the screen.
- Safe-area-aware fixed layout; no scrolling on supported phone sizes.

### Typography

- Use the existing Nuvo display face for one short headline only.
- Use the existing Nuvo wordmark asset, never a typed `NUVO` substitute.
- Use uppercase blue labels sparingly for state and section identity.
- Keep supporting copy to one or two short lines.

### Color

- Navy: structure, race path outline, primary text.
- Electric blue: active goal, path progress, finish state, primary action.
- Muted slate: secondary copy and inactive controls.
- Pale blue: only for a selected state or animated atmosphere.

### Geometry

- The recurring object is a race path with a start dot and finish flag.
- The path should be large enough to read as an interface element, not a
  decorative divider.
- Use the same curved geometry family as Arena.
- Do not create a new rounded rectangle for every piece of information.

## Screen Model: Fitness Goal

The screen is one contained race setup surface, not a list page.

```text
┌────────────────────────────────────┐
│  [splash mark + wordmark]           │
│                                    │
│  WHAT ARE YOU TRAINING FOR?         │
│                                    │
│              BUILD STRENGTH         │
│             10 PUSHUPS              │
│                                    │
│        ●━━━━━━━━━━━━━━⚑             │
│         0 / 10   START LINE         │
│                                    │
│  Strength    Endurance    Rhythm    │
│  Crew        Milestone              │
│                                    │
│  [ Start the race ]                 │
└────────────────────────────────────┘
```

### Header

- Reuse the splash mark animation at a smaller settled scale.
- Keep the wordmark visible and high contrast.
- Remove the `1 / 1` indicator. There is no multi-page progress to report.

### Headline

Use one compact question:

`What are you training for?`

Do not add a second paragraph that explains the entire product.

### Race object

The race object is the visual center of the screen:

- Goal label above the race title.
- Race title in large type.
- Curved navy path.
- Electric-blue progress path initially at zero length.
- Blue start dot.
- Navy finish flag with blue fill.
- Small status row: `0 / 10` and the selected movement.

When the goal changes, the title, target, icon, and status update in place.
Nothing disappears and nothing causes the page to resize.

### Goal control

Use a compact horizontal/flowing selector with no outer card.

- Five text-and-icon controls sit directly on the canvas.
- Selected control gets a blue underline and blue icon.
- Inactive controls use navy/slate.
- On narrow devices the controls wrap into two balanced rows with equal
  alignment, not a container that looks like a card.
- The selected item is always visible and never clipped.

Labels:

- Strength
- Endurance
- Consistency
- Crew
- Milestone

### CTA

The CTA completes the onboarding race:

- Before selection: `Choose a goal` disabled.
- After selection: `Start the race`.
- During animation: `Crossing the start line`.
- After animation: route to account access.

The CTA must not say `Start with build strength`; that describes a preference,
not an action.

## Interaction Timeline

### Explanation page transitions

- Use a horizontal PageView with swipe support and an explicit bottom action.
- Each page owns one animation controller and resets its visual example when
  the page becomes active.
- The page indicator represents the explanation sequence only.
- Back returns to the previous explanation page; it never jumps to the app.
- The user may skip the explanation, but Practice Mode remains available
  before account creation.

### Fake example rules

- Every simulated race and proof visual is labeled `EXAMPLE` or `PRACTICE MODE`.
- Simulated counts are local animation state only.
- No simulated proof is sent to the backend.
- No simulated result is shown as a real user achievement.
- Camera permission is requested only when the user later submits real proof
  inside a race.

### Entry

1. Splash settles into the top mark position.
2. Headline reveals with a short upward fade.
3. Race path draws from start dot to finish flag.
4. Goal controls appear after the path is visible.

### Goal selection

1. User taps a goal.
2. Selected control changes color and underline.
3. Race title crossfades to the recommended movement.
4. Target number rolls to its suggested value.
5. The blue path draws a short preview segment.
6. CTA becomes active.

### Completion

1. User taps `Start the race`.
2. Blue progress travels along the exact navy path geometry.
3. Start dot moves with the progress edge.
4. Finish flag gives one small confirmation motion.
5. The screen holds the completed state for 180ms.
6. Navigate to account access while carrying the selected goal.

No animation should change layout height or create a second scroll position.

## Goal Mapping

| Goal | Suggested movement | Target | Preview language |
|---|---|---:|---|
| Strength | Pushups | 10 | Build strength through reps |
| Endurance | Jumping Jacks | 50 | Keep moving toward the line |
| Consistency | Squats | 10 | Put a repeatable move on the board |
| Crew | Pushups | 10 | Give your crew a race to chase |
| Milestone | Pushups | 10 | Set a clear first finish line |

These are local onboarding defaults. They do not change backend response shapes
or create a race before authentication.

## Screen-Specific Responsive Rules

### iPhone SE / short height

- Headline uses two lines at 32-36pt.
- Race object height is 170-190pt.
- Goal controls use two rows.
- CTA remains pinned above the bottom safe area.

### iPhone 14

- Headline uses two lines at 38-42pt.
- Race object height is 220-250pt.
- Goal controls stay visually close to the race object.

### Pro Max / tall height

- Do not stretch the headline or controls.
- Add atmosphere around the race object, not extra content.
- Keep CTA at the same relative bottom position.

## Account Handoff Model

The auth screen receives the selected goal and shows it as context:

```text
Training for: Build strength
Put your first race on the board.
```

The selected goal survives:

- Apple sign-in,
- Google sign-in,
- email sign-in,
- OTP verification,
- cancelled provider flows.

Auth implementation and token behavior remain unchanged.

## Tutorial Model After Auth

Onboarding ends before the tutorial. The tutorial uses the actual app:

```text
Compete
  -> Start
  -> Choose movement
  -> Set finish line
  -> Name race
  -> Pull in crew or start solo
  -> Review
  -> Start race
  -> Race leaderboard
```

The guide advances only after the real action succeeds. It does not advance
because a timer elapsed.

Each step contains:

- route expectation,
- target key,
- allowed action,
- success callback,
- next step,
- recovery if the user leaves the route.

The coach mark stays near the highlighted control and never covers it. It must
recalculate after keyboard, scroll, route, and device-size changes.

## Flutter Implementation Model

### Presentation components

- `OnboardingRaceCanvas`
- `OnboardingGoalSelector`
- `OnboardingRacePathPainter`
- `OnboardingCompletionController`
- `TutorialCoordinator`
- `TutorialCoachMark`

### State

The onboarding state stores:

- selected fitness goal,
- recommended movement,
- recommended target,
- completion phase,
- whether the user has handed off to auth.

The tutorial state stores:

- current guide step,
- expected route,
- target key,
- success condition,
- skip/completion state.

### Animation constraints

- Use one animation controller for race completion.
- Use separate short controllers only for selection and text transitions.
- Use `PathMetric.extractPath` so blue progress follows the exact navy path.
- Use bounded `CustomPaint` regions.
- Do not animate parent padding, height, or intrinsic layout.

## QA Model

Before the next visual implementation is accepted:

- Screenshot the screen at SE, iPhone 14, and Pro Max sizes.
- Confirm no scrolling is needed.
- Confirm every goal is tappable and visible.
- Confirm the race path is visible at zero progress.
- Confirm blue progress follows the navy geometry exactly.
- Confirm the completion animation does not clip the flag or CTA.
- Confirm the selected goal survives auth navigation.
- Confirm a returning user does not see first-use onboarding.
- Confirm demo replay begins at the splash and repeats the same completion flow.
- Run focused onboarding tests, `flutter analyze --no-fatal-infos`, and a
  release install on the connected phone.

## Implementation Order

1. Build this model as a contained Flutter screen with no scroll view.
2. Verify layout and animation on the three device sizes.
3. Wire the selected goal into the existing auth handoff.
4. Replace the tutorial presentation with the coordinator model.
5. Test the complete path from splash to first leaderboard.

No auth, race API, backend, camera, or motion-validation files are part of
this redesign.
