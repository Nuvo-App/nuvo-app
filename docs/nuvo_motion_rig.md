# Nuvo Motion Rig

## Purpose

Nuvo's movement preview is a visual guide only. It is separate from AI Motion
Proof, camera capture, pose detection, validation, and repetition acceptance.
The semantic motion layer lets movement authors describe a human pose without
knowing Rive property names, mirrored signs, converters, or artboard padding.

## Architecture

```text
Movement definition → NuvoHumanPose → semantic interpolation
→ NuvoRigResolver → NuvoRiveRigCalibration → NuvoPoseModel → Rive stickman
```

Movement definitions stop at `NuvoHumanPose`. Raw Rive values belong in the
resolver and calibration boundary; raw View Model handles belong only in
`RivePoseController`.

## Asset and exported model

- Asset: `assets/animations/preverify/nuvo_stickman.riv`
- Artboard: `nuvo stickman elite`
- View Model: `NuvoPoseModel`
- State machine: `Nuvo pose`
- Runtime: Rive `0.14.11`

The discovered numeric controls are torso angle, shoulder/elbow/hip/knee
angles for both sides, eight limb scales, and `torsoScaleY`. Raw asset
defaults are diagnostic values. They are not the visible standing pose because
the scale converters use the exported 0–100 input space.

## Calibration

| Control | Raw default | Visible standing value |
| --- | ---: | ---: |
| `torsoAngle` | 0 | -90 |
| `leftShoulderAngle` | -90 | -180 |
| `rightShoulderAngle` | 0 | 180 |
| `leftElbowAngle` | 0 | 0 |
| `rightElbowAngle` | 20 | 0 |
| `leftHipAngle` | 0 | -180 |
| `rightHipAngle` | 0 | 180 |
| knee controls | 0 | 0 |
| limb scales | 0 | 100 |
| `torsoScaleY` | 0 | 100 |

Shoulder and hip sides use independent calibrated mappings. For the current
global jumping-jack geometry, the left elbow local bend is +68.5° and maps to
+68.5 raw degrees; the right elbow local bend is -68.5° and maps to +34.25
raw degrees. Movement code must not mirror raw values itself.

Elbow controls are local child-joint rotations: the shoulder positions the
upper arm, while the elbow changes the lower arm relative to that upper arm.
The controller writes cached property handles and requests one Rive advance.

## Ground-Truth Pose Calibration

The calibration screen remains available in debug builds from the Profile tab
via `Rive Calibration`. It binds the actual `NuvoPoseModel` instance and reads
its current raw values; it does not initialize controls from the semantic
resolver.

Use one slider or nudge button at a time. Each control writes only its own
number property and requests a Rive advance. The rig remains static: there is
no animation controller, semantic resolver, kinematic solver, or interpolation
on this screen.

Use `RESET RIG` to recreate the View Model instance from authored defaults.
Use `COPY CURRENT RAW POSE` to copy every exported numeric property as a
JSON-like structure. Set the closed standing pose manually and press `SAVE AS
CLOSED`. Set the open pose manually with elbows outside the hands and hands
above the elbows, then press `SAVE AS OPEN`. `SHOW CLOSED` and `SHOW OPEN`
apply those saved raw values exactly. Saved values are temporary in-memory
calibration data until they are copied into the canonical calibration source.

After both poses are approved, Jumping Jacks will use those raw endpoints and
interpolate each control directly. The semantic middleware remains available
for later movement work, but it must not contain guessed raw Rive numbers.

## Semantic coordinate system

Movement definitions use global 2D segment directions, with +x to the right
and +y downward. An arm is described by two vectors: shoulder→elbow and
elbow→wrist. A leg uses hip→knee and knee→ankle. The resolver computes each
segment's global angle and the elbow/knee local delta, then converts those
values to calibrated Rive controls. Movement authors think about where each
visible segment points, not about local bone rotations.

For the open jumping jack, the left upper arm is `(-0.70, -0.70)` and its
forearm is `(0.40, -0.92)`. The right side mirrors those vectors. Elbows are
therefore farther out than hands, while hands are higher than elbows.

`foreshortening` is a dimensionless length multiplier, with 1 as neutral. The
resolver performs all left/right conversion despite different authored signs.

## Jumping Jacks

The active Jumping Jack sequence reads a `NuvoRiveRigCalibration` baseline
from the live View Model when the Rive instance loads. It applies two simple
sets of offsets to that baseline, interpolates only the six shoulder/elbow/hip
controls, and leaves torso, knees, and scales fixed at their baseline values.

### Human-derived preview timing

The Jumping Jack preview keeps its Rive appearance endpoints locked in the
calibration above, but its timing comes from real Nuvo pose sessions rather
than hand-authored easing. The source sessions are the Cloudflare motion
artifacts indexed as `activity_id = jumping_jacks`. The existing verifier's
closed-to-closed `rep_counted` transitions segment the data. Each segment is
normalized to one cycle, body-size normalized using shoulder width, and reduced
to four semantic channels: arm raise, elbow bend, ankle spread, and root rise.
Sixteen clean cycles from three sessions were median-aggregated and lightly
smoothed into the compact profile in
`jumping_jack_human_motion_profile.dart`. Runtime samples interpolate that
profile and only then lerp the approved closed/open Rive endpoints. No raw
person coordinates, camera frames, or network access are used by the preview.

## Framing

The artboard is 462×380 and includes transparent padding. The preview uses a
fixed centered `ClipRect` containing a 1.75× larger centered artboard layout.
`Fit.contain` preserves aspect ratio inside that layout. The crop removes
transparent waste while the fixed center prevents drift or size changes. No
`Transform.scale` or movement-specific translation is used.

## Adding a movement

1. Define closed/open `NuvoHumanPose` values using semantic helpers.
2. Interpolate `NuvoHumanPose`, never raw Rive fields.
3. Resolve through `NuvoRigResolver`.
4. Apply the resulting `RivePoseFrame` through the controller.
5. Keep timing on one persistent animation clock.

Do not write `leftShoulderAngle`, `rightElbowAngle`, or scale property names
from a movement definition. Do not manually mirror signs, guess neutral values,
or add movement-specific Flutter transforms.

## Future pushup example

A future pushup can use horizontal torso intent, semantic elbow bend, and arm
or leg `foreshortening` below 1. The resolver can later map depth values into
the calibrated scale controls without changing the movement definition.

## Troubleshooting

- Wrong arm direction: inspect `NuvoRigResolver`, not the movement.
- Forearm moves with the whole arm: verify the Rive elbow binding and local
  hierarchy, then update calibration.
- Character too small or clipped: update the shared viewport/envelope, never
  add a movement-specific transform.
- Limb too short: inspect the scale converter and calibrated neutral 100.
- New asset behavior: rerun the property probe and update calibration first.
