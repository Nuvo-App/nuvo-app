# Nuvo Pre-Verification Movement Animation

## Product requirements document

Status: Proposed

Owner: Nuvo product and mobile engineering

Surface: Submit Proof, before AI Motion Proof opens

Last updated: 2026-09-18

## 1. Summary

Nuvo needs a short, friendly movement demonstration before a participant opens
AI Motion Proof. The current implementation has two opposite problems:

- the old custom-painted athlete looked distorted and uncanny in difficult
  poses;
- the current abstract trace is safe and stable, but does not show a person
  doing the movement clearly enough.

This PRD defines a production animation system that shows a clean Nuvo
stick-figure athlete performing the movement without drawing every animation
frame in Dart. The character will be authored as a rigged 2D asset in an
animation tool, exported as a runtime asset, and played by a small Flutter
adapter.

The animation is instructional UI only. It must never participate in motion
recognition, proof acceptance, rep counting, or race progress.

## 2. Problem

The pre-verification step must answer three questions quickly:

1. What movement am I about to prove?
2. What should the movement look like?
3. What do I tap next?

A preview can fail in several ways:

- joints stretch or detach during interpolation;
- the figure changes size or leaves its frame;
- the ground contact disappears during squats, lunges, or jumps;
- the figure looks like a broken robot or a scary humanoid;
- the preview resembles the verifier and makes users think the preview is
  judging them;
- the animation changes the surrounding page height;
- a missing movement asset blocks proof submission;
- a new animation package creates a build or platform problem.

## 3. Goals

### Primary goals

- Show a clear, friendly person performing supported movements before proof.
- Use an authored rig and animation timeline instead of hand-drawing frames in
  Flutter code.
- Keep the preview deterministic, bounded, and visually stable on supported
  phone sizes.
- Preserve the current Nuvo visual language: white surface, navy structure,
  blue action emphasis, restrained accents, and tactile controls.
- Make adding a movement an asset-and-metadata task rather than a new painter
  implementation.
- Keep a safe fallback for movements without a published animation asset.
- Support reduced motion without hiding the movement guidance.

### Secondary goals

- Allow future server-distributed preview assets without coupling them to the
  verifier release.
- Reuse one character rig across many movement clips.
- Make preview quality reviewable with still frames and short replay tests.

## 4. Non-goals

- This is not a replacement for AI Motion Proof.
- This does not change pose detection, motion validators, confidence scores,
  proof status, or the motion control plane.
- This does not use a generative video model at runtime.
- This does not infer a new exercise from the participant's camera.
- This does not display the participant's live camera before they tap Begin.
- This does not require a 3D avatar, photorealistic human, facial animation, or
  body customization in the first release.
- This does not add a new route or move screen ownership between Submit Proof
  and AI Motion Proof.
- This does not make animation assets authoritative motion-verification data.

## 5. Product and UX principles

### 5.1 The preview is a coach, not a judge

The preview demonstrates the movement. It must not show warning colors,
failure states, rep counts, pose scores, or language that suggests the user is
already being evaluated.

Recommended copy:

- `How to move`
- `Start in frame`
- `Move at your own pace`
- `Finish the rep cleanly`

The existing `Begin` action remains the one primary action on the screen.

### 5.2 Clarity over realism

The character should be a deliberate instructional illustration. It should
read correctly at a glance and remain visually pleasant when reduced to a
small card. A simple, stable silhouette is better than an almost-real person
with visible rig artifacts.

### 5.3 Motion has one job

The loop demonstrates the movement and establishes readiness. It must not
bounce, wobble, shake, flash, or perform decorative page choreography.

Target loop duration: 1.6 to 2.8 seconds depending on the movement.

Target transition timing: 150 to 250 ms for state changes and no more than
500 ms for asset entry.

### 5.4 Stable geometry

The preview lives inside a fixed-height, fixed-aspect-ratio viewport. The
asset cannot change the height of the Submit Proof page when it loads, loops,
or changes movement.

## 6. Competitive and implementation research

### 6.1 What established products show

Public fitness products commonly use an animated avatar or rigged figure to
show the full range of motion. Fitlapse describes its library as animated
avatars that demonstrate movements from a clear angle. This supports the UX
pattern, but its public page does not document the internal runtime.

The useful lesson is not to copy a 3D look. It is to show one consistent
character, one clear camera angle, and one complete movement loop.

### 6.2 How production teams implement it

The common production pattern is:

```text
character artwork
    -> bones / pivots / constraints
    -> keyframed animation clips
    -> exported runtime asset
    -> Flutter playback adapter
    -> fixed preview viewport
```

The app code does not calculate every elbow, knee, torso, or foot pixel. It
loads the authored asset, selects a named clip or state-machine input, and
controls playback. This is the important difference from the previous Nuvo
approach.

### 6.3 Rive

Rive is the best first candidate for Nuvo's 2D stickman preview. Its editor
supports authored vector artwork, bones, animation timelines, and state
machines. Its Flutter runtime can load a `.riv` asset and control state-machine
inputs such as triggers, booleans, and numbers.

Rive fits the requirement because:

- the figure is created once and reused;
- movement clips are authored outside Dart;
- the app can use a state machine named `movement_preview`;
- code can select an artboard and fire `play` or `reset` inputs;
- the exported vector asset remains crisp at different phone sizes;
- animation state can be tested without coupling it to camera recognition.

Rive's current Flutter package supports iOS and Android, but it is a new
dependency for this repository. The dependency must not be added until the
owner approves the package and its build impact, because repository policy
protects `pubspec.yaml` and `pubspec.lock`.

### 6.4 Lottie

Lottie is a JSON-based format for animated vector graphics. It is a good fit
for a self-contained, mostly timeline-driven illustration exported from a
design tool. It is less attractive for Nuvo if the preview needs runtime
state-machine inputs, reusable bone controls, or future data-driven retargeting.

Lottie remains a valid fallback for a small set of fixed movement clips if a
designer already supplies production-ready exports. It should not become the
source of truth for verifier configuration.

### 6.5 Spine

Spine is a mature 2D skeletal-animation workflow with official runtimes,
including Flutter support. It is technically strong for reusable rigs,
animation blending, and procedural control. Its licensing and editor workflow
are heavier than Nuvo needs for a small instructional preview, so it is a
secondary option rather than the first implementation.

### 6.6 3D rigged avatars

3D fitness products often use a rigged model with keyframed or motion-captured
clips. A public AxisFit case study describes a shared bone-rig engine where
each exercise is represented by a keyframe set and the runtime handles ground
alignment and other common behavior. This is a strong long-term pattern for
full-body fidelity, but it adds model, rendering, asset, and performance
complexity that is not justified for Nuvo's first pre-verification preview.

### 6.7 Video, GIF, and sprite sheets

These are the fastest options for a demo but the weakest long-term system:

- video is large and difficult to recolor or control by movement phase;
- GIF quality and transparency are inconsistent across platforms;
- sprite sheets can be reliable but require exporting many frames and do not
  provide a reusable rig;
- none of these options gives Nuvo a clean path to future state-machine
  inputs.

They may be used as a temporary fallback for a single movement, but not as the
core architecture.

## 7. Decision

### Recommended implementation

Use a single Rive 2D stickman rig with authored movement clips and a small
Flutter playback adapter.

The first release should use:

- one friendly, gender-neutral stickman;
- navy outline and body structure;
- blue active motion accent;
- a pale blue or white preview surface;
- a subtle ground line;
- no face, facial expression, sweat, flames, impacts, explosions, or realistic
  body shading;
- no red during normal playback;
- optional green only for a quiet finish marker, never as a large background.

### Why not keep the current CustomPainter system?

The current `MovementDemo` and `NuvoCharacterPainter` approach stores poses and
renders the character directly in Dart. It is deterministic, but it makes
visual quality depend on hand-tuned geometry in source code. That is why the
old version could produce stretched limbs, awkward torso shapes, and broken
extreme poses.

The existing painter should remain available as a temporary fallback during
migration, but new movement animation work should not add more painter-based
character assets.

## 8. Proposed technical architecture

### 8.1 Runtime layers

```text
MovementPreviewAsset
    - activityId
    - assetPath
    - artboardName
    - stateMachineName
    - fallbackPose
    - publishedVersion

MovementPreviewRegistry
    - resolve(activityId)
    - resolveFallback(activityId)

NuvoMovementPreview
    - fixed viewport
    - loads asset
    - drives state machine
    - handles reduced motion
    - reports asset failures to diagnostics

SubmitProofScreen
    - passes movement metadata
    - remains owner of copy and Begin action
```

### 8.2 Rive file contract

Each `.riv` file should expose this stable contract:

- artboard: `nuvo_stickman`
- state machine: `movement_preview`
- trigger: `play`
- trigger: `reset`
- number input: `speed`
- boolean input: `reduced_motion`
- callback: `loop_complete`

The first implementation may package all launch movements in one `.riv` file
with named animations, or use one small file per movement. Prefer one file
while the rig is shared and the total asset remains small. Split files only
when download, caching, or release ownership requires it.

### 8.3 Movement metadata

The app-side registry should contain presentation metadata only:

```dart
class MovementPreviewAsset {
  const MovementPreviewAsset({
    required this.activityId,
    required this.assetPath,
    required this.artboard,
    required this.stateMachine,
    required this.clip,
    required this.duration,
    required this.fallbackIcon,
  });

  final String activityId;
  final String assetPath;
  final String artboard;
  final String stateMachine;
  final String clip;
  final Duration duration;
  final IconData fallbackIcon;
}
```

The registry must not contain thresholds, confidence values, validator
settings, or any field used to accept proof.

### 8.4 Flutter adapter behavior

The adapter must:

1. Reserve its full viewport before the asset begins loading.
2. Show a stable skeleton or fallback pose while loading.
3. Load the asset once and reuse it for the page lifetime.
4. Start the named clip only after the widget is laid out.
5. Stop playback when the widget is offscreen or disposed.
6. Switch to one static representative pose when reduced motion is enabled.
7. Use `BoxFit.contain` inside a clipped viewport.
8. Never use the preview animation to gate the Begin action.
9. Fail closed to the icon-and-trace fallback if the asset is missing or
   corrupt.
10. Emit a diagnostic signal without showing technical details to the user.

### 8.5 Fixed layout contract

Recommended first viewport:

- preview width: available content width;
- preview aspect ratio: 1.45 to 1.65;
- minimum height: 150 logical pixels;
- maximum height: 210 logical pixels;
- internal padding: 16 to 24 logical pixels;
- border: 2 logical pixels navy;
- radius: existing Nuvo card radius;
- overflow: clipped;
- page height: unchanged between loading, loaded, looping, and fallback states.

## 9. Animation design specification

### 9.1 Character rig

The rig should contain:

- root / ground anchor;
- pelvis;
- spine and chest;
- neck and head;
- upper and lower arms;
- hands;
- upper and lower legs;
- feet.

Use fixed bone lengths and pivots. Use constraints for:

- feet staying on the ground for grounded movements;
- hands staying planted for plank and mountain-climber variants;
- spine staying within a readable range;
- head following the chest without independent jitter.

### 9.2 Keyframe rules

Each movement should have authored phases rather than a single arbitrary loop:

```text
ready -> preparation -> action -> recovery -> ready
```

For holds:

```text
ready -> enter_hold -> hold -> exit_hold -> ready
```

For jumps:

```text
ready -> load -> takeoff -> airborne -> landing -> ready
```

Use ease-in-out for normal body motion, deliberate anticipation before large
actions, and a short settle after landing. Do not use bounce or elastic easing.

### 9.3 Initial movement set

The first authored set should be:

1. Pushups
2. Squats
3. Jumping jacks
4. Arm raises
5. Lunges
6. Plank hold

The remaining launch movements may use the fallback until each animation passes
the visual acceptance gate.

### 9.4 Visual quality rules

- The head must never detach from the neck.
- Hands and feet must remain visibly connected to limbs.
- The figure must never touch the panel edge.
- The feet must remain on or intentionally leave the ground line.
- No joint may change apparent length during a normal loop.
- The movement must be readable when paused at any sampled frame.
- The preview must not imply that one body shape or range of motion is the
  only valid body.
- The animation must not use red for normal movement.

## 10. Asset production workflow

### Phase A: rig once

1. Create the simple stickman in Rive or an equivalent rig editor.
2. Name every bone and input using the contract above.
3. Establish the canonical standing pose and ground line.
4. Add constraints and verify the rig at the smallest preview viewport.

### Phase B: author movement clips

1. Record or reference the intended movement phases.
2. Pose the rig at 3 to 8 intentional keyframes.
3. Review the loop at normal speed and half speed.
4. Check every keyframe for disconnected or inverted limbs.
5. Export the clip into the `.riv` asset.

### Phase C: app integration

1. Add the asset under the approved asset directory.
2. Add one registry entry.
3. Render it in the fixed preview widget.
4. Confirm fallback behavior by temporarily using an invalid asset path in a
   test-only fixture.
5. Run widget, layout, and asset-contract tests.

### Phase D: review

1. Review still frames at 0%, 25%, 50%, 75%, and 100% progress.
2. Review a normal-speed loop without audio.
3. Review reduced-motion output.
4. Review on 375x667, 390x844, and 430x932 logical layouts.
5. Only then add the next movement.

## 11. Data and release strategy

### Initial release

The first `.riv` asset should ship as a local app asset. This avoids adding a
network dependency to the proof-entry path and makes the presentation reliable.

### Future remote distribution

Preview assets may later be distributed through the existing motion control
plane, but they need their own presentation asset manifest. They must not be
confused with verifier releases.

The future manifest can contain:

- `assetId`
- `activityId`
- `format`
- `assetUrl`
- `checksum`
- `byteLength`
- `minimumAppVersion`
- `publishedAt`
- `fallbackPolicy`

The app must verify checksum, cache the asset, retain the last known-good
asset, and fall back locally when a download fails. Remote presentation assets
must never block starting AI Motion Proof.

## 12. Accessibility and safety

- Respect Flutter's reduced-animation setting.
- Provide a semantic label describing the movement and the three phases.
- Do not rely on color alone to communicate movement phases.
- Keep text instructions below the animation.
- Keep Begin at the existing minimum touch target.
- Do not use strobing, rapid camera motion, screen shake, or flashing.
- Do not imply medical advice or guaranteed form correctness.
- The preview must never claim that the user's proof is accepted.

## 13. Testing and acceptance gates

### Functional gate

- Supported activity resolves to the correct preview asset.
- Begin is visible and tappable before, during, and after asset loading.
- Tapping Begin navigates to the existing AI Motion Proof route.
- No preview state changes the verifier configuration.
- Missing assets use the trace/icon fallback.
- Reduced motion renders a static representative pose.

### Visual gate

- No overflow or clipping at 375x667, 390x844, or 430x932.
- The preview card has identical height in loading, loaded, and fallback states.
- The figure remains inside the viewport for the entire loop.
- No detached joints, limb stretching, inverted feet, or ground drift.
- The animation reads without a caption after one loop.
- The card feels like Nuvo: clean, playful, blue-led, and restrained.

### Performance gate

- No dropped-frame pattern during the loop on a physical iPhone.
- Asset memory and size are measured before adding more clips.
- The asset is not reloaded on every rebuild.
- The animation stops when the screen is disposed.

### Regression gate

- `flutter analyze --no-fatal-infos` introduces no new warning or error.
- Submit Proof widget and layout tests pass.
- Camera verification tests pass unchanged.
- Motion validator tests pass unchanged.
- No simulator launch is required for the initial documentation and asset
  integration work; physical-device QA is required before release.

## 14. Rollout plan

### Milestone 1: rig proof of concept

- Approve Rive or select an alternative runtime.
- Create the stickman rig and one pushup clip.
- Render it in an isolated preview fixture.
- Pass geometry, reduced-motion, and small-layout gates.

### Milestone 2: Submit Proof integration

- Add the adapter behind the existing preview surface.
- Keep the trace fallback available.
- Preserve existing route and Begin behavior.
- Verify no page-height shift.

### Milestone 3: launch movement set

- Add squats, jumping jacks, arm raises, lunges, and plank hold.
- Review each movement independently.
- Do not promote movements with visible rig defects.

### Milestone 4: remote presentation assets

- Define a presentation-only asset manifest.
- Add checksum and cache handling.
- Add staged rollout and rollback for assets.
- Keep verifier releases and animation assets separate.

## 15. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Rive dependency increases build complexity | Medium | Approve package first; build a one-asset spike before migration |
| Asset looks polished in editor but fails on device | High | Test the exported asset in Flutter at target sizes before adding clips |
| Animation is mistaken for proof feedback | Medium | Label as guidance; keep all verification state in AI Motion Proof |
| Asset download fails | Medium | Ship local fallback; checksum and cache remote assets |
| Rive licensing or editor workflow is not acceptable | Medium | Keep Lottie and Spine as documented alternatives |
| Too many unique clips increase review cost | Medium | One shared rig, six initial movements, explicit visual gates |
| Rig still looks uncanny | High | Use simple graphic language, no face, no realistic shading, and reject bad clips |
| Reduced motion is ignored | Medium | Static representative pose and widget test |

## 16. Open decisions

These decisions require owner approval before implementation:

1. Approve adding the Rive Flutter dependency, or choose an already approved
   runtime.
2. Decide whether the first asset is one `.riv` file or one file per movement.
3. Approve the final stickman proportions and color treatment.
4. Decide who authors and reviews movement keyframes.
5. Decide whether remote presentation assets are required for the first public
   release or can remain local assets.

## 17. Research references

- [Rive state machines and Flutter inputs](https://github.com/rive-app/help-center/blob/master/runtimes/state-machines.md)
- [Rive Flutter runtime](https://pub.dev/packages/rive)
- [Rive runtime documentation](https://rive.app/docs/auth)
- [Lottie vector animation specification](https://lottie.github.io/lottie-spec/dev/)
- [Spine runtimes](https://us.esotericsoftware.com/spine-runtimes)
- [Spine Flutter runtime documentation](https://en.esotericsoftware.com/spine-flutter)
- [Fitlapse animated exercise library](https://fitlapse.com/en/about/)
- [AxisFit bone-rig animation case study](https://www.dfieldsolutions.com/projects/axisfit)

## 18. Final recommendation

Build the first proof-of-concept with a Rive-authored 2D rig, not a new
CustomPainter and not generated video. Rive gives Nuvo the key property we are
missing: the figure and its movement are authored visually, while Flutter
only loads and controls a stable exported asset.

The first proof-of-concept should be one pushup loop. It should not expand to
all movements until it survives the geometry, accessibility, small-screen,
performance, and fallback gates above.
