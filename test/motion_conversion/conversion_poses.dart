// Parametric pose generators for the Batch B conversion tests.
//
// Every pose is a `CleanPose` (name -> normalized Point). Canonical geometry
// mirrors the app's own movement previews where they exist — see each
// generator's comment for the calibration numbers against the native
// validator's internal signals (PoseFeatureExtractor).
//
// Conventions: normalized coordinates, y grows downward. Canonical front
// skeleton:
//   nose (0.50,0.14) shoulders (0.42/0.58, 0.18) elbows (0.39/0.61, 0.29)
//   wrists (0.40/0.60, 0.40)  hips (0.45/0.55, 0.40)
//   knees (0.44/0.56, 0.58)   ankles (0.44/0.56, 0.76)
//   => torsoHeight 0.22, hipWidth 0.10, shoulderWidth 0.16,
//      standing hipToKneeRatio = (0.58-0.40)/0.22 = 0.818.

import 'dart:math';

import '../support/realistic_pose.dart';

/// Canonical front-facing standing pose.
CleanPose frontStanding({double stance = 1.0}) => {
      'nose': p(0.50, 0.14),
      'leftShoulder': p(0.42, 0.18),
      'rightShoulder': p(0.58, 0.18),
      'leftElbow': p(0.39, 0.29),
      'rightElbow': p(0.61, 0.29),
      'leftWrist': p(0.40, 0.40),
      'rightWrist': p(0.60, 0.40),
      'leftHip': p(0.45, 0.40),
      'rightHip': p(0.55, 0.40),
      'leftKnee': p(0.50 - 0.06 * stance, 0.58),
      'rightKnee': p(0.50 + 0.06 * stance, 0.58),
      'leftAnkle': p(0.50 - 0.06 * stance, 0.76),
      'rightAnkle': p(0.50 + 0.06 * stance, 0.76),
    };

/// Regular squat at normalized [depth] in 0..1.
///
/// Depth model follows the app's squat demo key poses: hips drop 0.10,
/// shoulders follow down 0.05, knees rise 0.04 and travel 0.02 outward,
/// ankles stay planted.
///   depth 0    -> hipToKneeRatio 0.82  (start)
///   depth 1.0  -> hipToKneeRatio 0.148 (active, needs < 0.50)
///   depth 0.30 -> hipToKneeRatio 0.60  (dead zone 0.50..0.72)
CleanPose squatAt(double depth) => {
      'nose': p(0.50, 0.14 + 0.04 * depth),
      'leftShoulder': p(0.42, 0.18 + 0.05 * depth),
      'rightShoulder': p(0.58, 0.18 + 0.05 * depth),
      'leftElbow': p(0.39, 0.29 + 0.05 * depth),
      'rightElbow': p(0.61, 0.29 + 0.05 * depth),
      'leftWrist': p(0.40, 0.40 + 0.03 * depth),
      'rightWrist': p(0.60, 0.40 + 0.03 * depth),
      'leftHip': p(0.45, 0.40 + 0.10 * depth),
      'rightHip': p(0.55, 0.40 + 0.10 * depth),
      'leftKnee': p(0.44 - 0.02 * depth, 0.58 - 0.04 * depth),
      'rightKnee': p(0.56 + 0.02 * depth, 0.58 - 0.04 * depth),
      'leftAnkle': p(0.44, 0.76),
      'rightAnkle': p(0.56, 0.76),
    };

/// Wide sumo stance. ankleWidth/bodyWidth = 0.40/0.16 = 2.5 > 1.5.
CleanPose sumoStanding() => {
      ...frontStanding(),
      'leftKnee': p(0.36, 0.58),
      'rightKnee': p(0.64, 0.58),
      'leftAnkle': p(0.30, 0.76),
      'rightAnkle': p(0.70, 0.76),
    };

/// Sumo squat at [depth]. Same vertical model as [squatAt]; knees track
/// outward over the wide feet.
CleanPose sumoAt(double depth) => {
      ...squatAt(depth),
      'leftKnee': p(0.36 - 0.04 * depth, 0.58 - 0.04 * depth),
      'rightKnee': p(0.64 + 0.04 * depth, 0.58 - 0.04 * depth),
      'leftAnkle': p(0.30, 0.76),
      'rightAnkle': p(0.70, 0.76),
    };

/// Squat-jack closed phase — standing, arms down, feet together.
CleanPose squatJackClosed() => frontStanding();

/// Squat-jack open phase at squat [depth]: arms overhead, feet wide, hips
/// dropped. Uses the same wrist-above-shoulder geometry the demo poses use.
CleanPose squatJackOpen(double depth) => {
      ...squatAt(depth),
      'leftElbow': p(0.34, 0.16),
      'rightElbow': p(0.66, 0.16),
      'leftWrist': p(0.40, 0.05),
      'rightWrist': p(0.60, 0.05),
      'leftKnee': p(0.38 - 0.04 * depth, 0.58 - 0.04 * depth),
      'rightKnee': p(0.62 + 0.04 * depth, 0.58 - 0.04 * depth),
      'leftAnkle': p(0.32, 0.76),
      'rightAnkle': p(0.68, 0.76),
    };

/// Deep side lunge toward [dir] ('left' or 'right').
///
/// Geometry follows the repo's own side-lunge fixture (see
/// test/configurable_rep_validator_test.dart): the bent leg's knee pushes
/// out, the foot plants roughly under the knee so the interior knee angle
/// reads ~112-114° (< 118 threshold), and knee-to-knee x separation lands
/// ~1.8-2.8x hip width (> 0.85 threshold). The planted leg stays straight.
CleanPose sideLunge(String dir) {
  final left = dir == 'left';
  return {
    'nose': p(0.50, 0.14),
    'leftShoulder': p(0.42, 0.18),
    'rightShoulder': p(0.58, 0.18),
    'leftElbow': p(0.40, 0.30),
    'rightElbow': p(0.60, 0.30),
    'leftWrist': p(0.44, 0.42),
    'rightWrist': p(0.56, 0.42),
    'leftHip': p(0.44, 0.44),
    'rightHip': p(0.56, 0.44),
    // Bent leg: knee drives laterally, shin drops to the planted foot.
    'leftKnee': left ? p(0.28, 0.56) : p(0.45, 0.58),
    'rightKnee': left ? p(0.55, 0.58) : p(0.72, 0.56),
    'leftAnkle': left ? p(0.32, 0.78) : p(0.45, 0.78),
    'rightAnkle': left ? p(0.55, 0.78) : p(0.68, 0.78),
  };
}

/// Side-view plank line for push-ups. [bend] in 0..1 is elbow flexion:
/// 0 = locked-out top plank, 1 = chest-to-floor bottom.
/// Shoulders travel down and toward the feet; wrists/ankles stay planted.
///   bend 0   -> elbow angle ~165°, |shoulder-wrist|/|shoulder-hip| ~0.66
///   bend 1   -> elbow angle ~90°,  |shoulder-wrist|/|shoulder-hip| ~0.47
/// (values verified by the calibration probe)
CleanPose pushupAt(double bend) => {
      'nose': p(0.16, 0.34 + 0.06 * bend),
      'leftShoulder': p(0.28 + 0.05 * bend, 0.44 + 0.10 * bend),
      'rightShoulder': p(0.30 + 0.05 * bend, 0.48 + 0.10 * bend),
      'leftElbow': p(0.30 + 0.10 * bend, 0.57 + 0.05 * bend),
      'rightElbow': p(0.33 + 0.10 * bend, 0.60 + 0.05 * bend),
      'leftWrist': p(0.31, 0.68),
      'rightWrist': p(0.35, 0.71),
      'leftHip': p(0.64 + 0.01 * bend, 0.50 + 0.04 * bend),
      'rightHip': p(0.67 + 0.01 * bend, 0.54 + 0.04 * bend),
      'leftKnee': p(0.79, 0.54 + 0.02 * bend),
      'rightKnee': p(0.82, 0.58 + 0.02 * bend),
      'leftAnkle': p(0.92, 0.57),
      'rightAnkle': p(0.95, 0.61),
    };

/// Straight-line plank (side view) for plank-hold sequences. [sag] drops the
/// hips off the shoulder->ankle line; [kneeBend] bends the knees.
CleanPose plankAt({double sag = 0.0, double kneeBend = 0.0}) => {
      'nose': p(0.18, 0.30),
      'leftShoulder': p(0.28, 0.42),
      'rightShoulder': p(0.30, 0.46),
      'leftElbow': p(0.29, 0.53),
      'rightElbow': p(0.32, 0.57),
      'leftWrist': p(0.30, 0.64),
      'rightWrist': p(0.34, 0.68),
      'leftHip': p(0.58, 0.50 + sag),
      'rightHip': p(0.61, 0.54 + sag),
      'leftKnee': p(0.76, 0.56 + sag * 0.5 + kneeBend * 0.03),
      'rightKnee': p(0.79, 0.60 + sag * 0.5 + kneeBend * 0.03),
      'leftAnkle': p(0.92, 0.60 + kneeBend * 0.02),
      'rightAnkle': p(0.95, 0.64 + kneeBend * 0.02),
    };

/// Standing pose for gait motions (running/walking/step-ups), front view.
/// [lift] raises one knee toward the hip — a vertical swing that flips the
/// sign of the native AlternatingGaitSignal's devY term each side (a lateral
/// x-drift would read the same sign for both legs — the swing direction must
/// alternate). `side` selects which leg drives.
CleanPose gaitPose(String side, {double lift = 1.0}) {
  final left = side == 'left';
  final kneeLiftY = 0.09 * lift; // ~0.4 torso — above the 0.30 march fraction
  return {
    ...frontStanding(),
    'leftKnee': left ? p(0.44, 0.58 - kneeLiftY) : p(0.44, 0.58),
    'rightKnee': left ? p(0.56, 0.58) : p(0.56, 0.58 - kneeLiftY),
    'leftAnkle': left ? p(0.43, 0.70 - 0.02 * lift) : p(0.44, 0.76),
    'rightAnkle': left ? p(0.56, 0.76) : p(0.57, 0.70 - 0.02 * lift),
  };
}

/// Neutral gait pose (both feet planted, knees level) — between-step frames.
CleanPose gaitNeutral() => frontStanding();

/// Alternating gait sequence: neutral -> left -> neutral -> right ... for
/// [cycles] full left+right cycles (each confirmed side switch = 1 native
/// count, so [cycles] cycles => 2*[cycles] counts).
List<CleanPose> gaitSequence({
  int cycles = 6,
  int framesPerSide = 4,
  int neutralFrames = 2,
  double lift = 1.0,
}) {
  final out = <CleanPose>[for (var i = 0; i < 6; i++) gaitNeutral()];
  var side = 'left';
  for (var c = 0; c < cycles * 2; c++) {
    for (var i = 0; i < framesPerSide; i++) {
      out.add(gaitPose(side, lift: lift));
    }
    for (var i = 0; i < neutralFrames; i++) {
      out.add(gaitNeutral());
    }
    side = side == 'left' ? 'right' : 'left';
  }
  return out;
}

/// One-sided gait (same leg every time) — must never count.
List<CleanPose> gaitOneSided({int steps = 8, int framesPerSide = 4}) => [
      for (var i = 0; i < 6; i++) gaitNeutral(),
      for (var s = 0; s < steps; s++) ...[
        for (var i = 0; i < framesPerSide; i++) gaitPose('left'),
        for (var i = 0; i < 3; i++) gaitNeutral(),
      ],
    ];

/// Mountain-climber pose (diagonal/front plank projection), following the
/// repo's own replay fixtures: torso roughly horizontal-in-frame, one knee
/// driving toward the chest along the torso axis.
CleanPose mountainClimberPose(String driveSide, {double drive = 1.0}) {
  final left = driveSide == 'left';
  // Plank: shoulders upper-left, hips right, hands under shoulders.
  const h = (0.62, 0.50); // hip centre-ish
  const torsoDx = 0.32, torsoDy = 0.14;
  final kneeDrive = Point(
    h.$1 - torsoDx * 0.55 * drive,
    h.$2 - torsoDy * 0.55 * drive + 0.10 * drive,
  );
  return {
    'nose': p(0.20, 0.28),
    'leftShoulder': p(0.28, 0.34),
    'rightShoulder': p(0.32, 0.38),
    'leftElbow': p(0.27, 0.40),
    'rightElbow': p(0.33, 0.44),
    'leftWrist': p(0.28, 0.44),
    'rightWrist': p(0.34, 0.46),
    'leftHip': p(0.60, 0.48),
    'rightHip': p(0.64, 0.52),
    'leftKnee': left ? kneeDrive : p(0.80, 0.58),
    'rightKnee': left ? p(0.84, 0.62) : kneeDrive,
    'leftAnkle': p(0.92, 0.62),
    'rightAnkle': p(0.95, 0.66),
  };
}
