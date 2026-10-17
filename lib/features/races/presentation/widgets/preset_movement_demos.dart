import 'package:flutter/material.dart';

import '../../domain/motion_activity.dart';
import 'arm_raises_animation.dart';
import 'cadence_movement_demos.dart';
import 'multiphase_movement_demos.dart';
import 'movement_demo.dart';
import 'nuvo_character_painter.dart';

/// Key poses for each preset movement, authored to match what the
/// corresponding validator expects. Each demo cycles through the
/// movement's distinct phases (down/up, start/active, etc.) and loops.

// ── Pushups ───────────────────────────────────────────────────────────────────
// PushupsValidator: "down" = elbow angle < 112°, "up" = elbow angle > 150°.
// Side view (body in profile, 210 x 150 stage). Hands and toes stay planted on
// the floor line. Top: arms straight, body one straight diagonal plank.
// Bottom: elbows bent about 80° and pointing back toward the feet, chest a
// fist above the floor, body still straight. `left*` joints are the near
// limbs, `right*` the far limbs.

class _PushupsKeyPoses {
  // Top position — arms straight.
  static const top = NuvoCharacterPose(
    head: Offset(0.1548, 0.3955),
    neck: Offset(0.2571, 0.4667),
    leftShoulder: Offset(0.2571, 0.4667),
    rightShoulder: Offset(0.2857, 0.4667),
    leftElbow: Offset(0.2762, 0.6533),
    rightElbow: Offset(0.3048, 0.6533),
    leftWrist: Offset(0.2952, 0.8367),
    rightWrist: Offset(0.3238, 0.8367),
    leftHip: Offset(0.5291, 0.6151),
    rightHip: Offset(0.5577, 0.6151),
    leftKnee: Offset(0.7234, 0.7211),
    rightKnee: Offset(0.7520, 0.7211),
    leftAnkle: Offset(0.9048, 0.8200),
    rightAnkle: Offset(0.9333, 0.8200),
  );

  // Bottom position — elbows bent back, chest just above the floor.
  static const bottom = NuvoCharacterPose(
    head: Offset(0.1056, 0.6338),
    neck: Offset(0.2190, 0.6533),
    leftShoulder: Offset(0.2190, 0.6533),
    rightShoulder: Offset(0.2476, 0.6533),
    leftElbow: Offset(0.3143, 0.6467),
    rightElbow: Offset(0.3429, 0.6467),
    leftWrist: Offset(0.2952, 0.8367),
    rightWrist: Offset(0.3238, 0.8367),
    leftHip: Offset(0.5070, 0.7233),
    rightHip: Offset(0.5356, 0.7233),
    leftKnee: Offset(0.7128, 0.7733),
    rightKnee: Offset(0.7413, 0.7733),
    leftAnkle: Offset(0.9048, 0.8200),
    rightAnkle: Offset(0.9333, 0.8200),
  );

  static const poses = [top, bottom, top];
}

const pushupsDemo = MovementDemo(
  poses: _PushupsKeyPoses.poses,
  duration: Duration(milliseconds: 2400),
  sideView: true,
);

// ── Squats ────────────────────────────────────────────────────────────────────
// SquatsValidator: "down" = hipY > kneeY * 0.85 (hips drop), "up" = standing.
// Front view: body centered, legs bending.

class _SquatsKeyPoses {
  // Standing — legs straight.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Squatting — hips lowered, knees bent.
  static const squatting = NuvoCharacterPose(
    head: Offset(0.50, 0.14),
    neck: Offset(0.50, 0.20),
    leftShoulder: Offset(0.42, 0.23),
    rightShoulder: Offset(0.58, 0.23),
    leftElbow: Offset(0.38, 0.30),
    rightElbow: Offset(0.62, 0.30),
    leftWrist: Offset(0.36, 0.38),
    rightWrist: Offset(0.64, 0.38),
    leftHip: Offset(0.45, 0.48),
    rightHip: Offset(0.55, 0.48),
    leftKnee: Offset(0.42, 0.54),
    rightKnee: Offset(0.58, 0.54),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  static const poses = [standing, squatting, standing];
}

const squatsDemo = MovementDemo(
  poses: _SquatsKeyPoses.poses,
  duration: Duration(milliseconds: 2200),
);

// ── Sumo Squats ───────────────────────────────────────────────────────────────
// ConfigurableRepValidator with sumoSquatRepDefinition:
// "start" = hipToKneeRatio > 0.86 AND ankleWidthToBodyWidth > 1.5,
// "active" = hipToKneeRatio < 0.58 AND ankleWidthToBodyWidth > 1.5.
// Front view: wide stance, deep squat. Ankles stay wide throughout.

class _SumoSquatsKeyPoses {
  // Standing — wide stance, legs straight.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.38, 0.58),
    rightKnee: Offset(0.62, 0.58),
    leftAnkle: Offset(0.30, 0.76),
    rightAnkle: Offset(0.70, 0.76),
  );

  // Deep squat — hips lowered, knees bent, stance still wide.
  static const sumoSquat = NuvoCharacterPose(
    head: Offset(0.50, 0.16),
    neck: Offset(0.50, 0.22),
    leftShoulder: Offset(0.42, 0.25),
    rightShoulder: Offset(0.58, 0.25),
    leftElbow: Offset(0.38, 0.32),
    rightElbow: Offset(0.62, 0.32),
    leftWrist: Offset(0.40, 0.40),
    rightWrist: Offset(0.60, 0.40),
    leftHip: Offset(0.43, 0.50),
    rightHip: Offset(0.57, 0.50),
    leftKnee: Offset(0.36, 0.54),
    rightKnee: Offset(0.64, 0.54),
    leftAnkle: Offset(0.30, 0.76),
    rightAnkle: Offset(0.70, 0.76),
  );

  static const poses = [standing, sumoSquat, standing];
}

const sumoSquatsDemo = MovementDemo(
  poses: _SumoSquatsKeyPoses.poses,
  duration: Duration(milliseconds: 2400),
);

// ── Side Lunges ───────────────────────────────────────────────────────────────
// ConfigurableRepValidator with sideLungeRepDefinition:
// "start" = both knees straight (>154°),
// "active" = kneeSeparation > 0.85 AND one knee < 118°.
// Front view: lateral step produces large X-separation between knees.

class _SideLungesKeyPoses {
  // Standing — neutral stance.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Side lunge — right leg steps out wide to the side, right knee bends.
  // Large lateral X-separation between knees.
  static const sideLungeRight = NuvoCharacterPose(
    head: Offset(0.48, 0.10),
    neck: Offset(0.48, 0.17),
    leftShoulder: Offset(0.40, 0.20),
    rightShoulder: Offset(0.56, 0.20),
    leftElbow: Offset(0.37, 0.30),
    rightElbow: Offset(0.59, 0.30),
    leftWrist: Offset(0.36, 0.40),
    rightWrist: Offset(0.60, 0.40),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.46, 0.58),
    rightKnee: Offset(0.72, 0.54),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.82, 0.76),
  );

  // Side lunge — left leg steps out wide to the side, left knee bends.
  static const sideLungeLeft = NuvoCharacterPose(
    head: Offset(0.52, 0.10),
    neck: Offset(0.52, 0.17),
    leftShoulder: Offset(0.44, 0.20),
    rightShoulder: Offset(0.60, 0.20),
    leftElbow: Offset(0.41, 0.30),
    rightElbow: Offset(0.63, 0.30),
    leftWrist: Offset(0.40, 0.40),
    rightWrist: Offset(0.64, 0.40),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.28, 0.54),
    rightKnee: Offset(0.54, 0.58),
    leftAnkle: Offset(0.18, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  static const poses = [
    standing,
    sideLungeRight,
    standing,
    sideLungeLeft,
    standing,
  ];
}

const sideLungesDemo = MovementDemo(
  poses: _SideLungesKeyPoses.poses,
  duration: Duration(milliseconds: 3600),
);

// ── Deep Squats ───────────────────────────────────────────────────────────────
// ConfigurableRepValidator with deepSquatRepDefinition:
// "start" = hipToKneeRatio > 0.86 (standing tall),
// "active" = hipToKneeRatio < 0.30 (hips below knees — below parallel).
// Front view: same stance as regular squats, but the descent goes deeper.
// The demo shows standing → normal squat depth (pass-through, not held) →
// deep squat depth (held) → standing, matching the verifier's active phase.

class _DeepSquatsKeyPoses {
  // Standing — legs straight, same as regular squat standing.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Normal squat depth — thighs ~parallel. This is the pass-through phase
  // that a regular squat would hold but a deep squat continues past.
  // hipToKneeRatio here ~0.50 (between 0.30 and 0.58 — counts for regular
  // squats but NOT for deep squats).
  static const normalSquatDepth = NuvoCharacterPose(
    head: Offset(0.50, 0.12),
    neck: Offset(0.50, 0.18),
    leftShoulder: Offset(0.42, 0.21),
    rightShoulder: Offset(0.58, 0.21),
    leftElbow: Offset(0.38, 0.28),
    rightElbow: Offset(0.62, 0.28),
    leftWrist: Offset(0.37, 0.36),
    rightWrist: Offset(0.63, 0.36),
    leftHip: Offset(0.45, 0.46),
    rightHip: Offset(0.55, 0.46),
    leftKnee: Offset(0.43, 0.54),
    rightKnee: Offset(0.57, 0.54),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Deep squat depth — hips below knees. This is the active phase.
  // hipToKneeRatio here ~0.20 (< 0.30 — counts for deep squats).
  static const deepSquatDepth = NuvoCharacterPose(
    head: Offset(0.50, 0.16),
    neck: Offset(0.50, 0.22),
    leftShoulder: Offset(0.42, 0.25),
    rightShoulder: Offset(0.58, 0.25),
    leftElbow: Offset(0.38, 0.32),
    rightElbow: Offset(0.62, 0.32),
    leftWrist: Offset(0.38, 0.40),
    rightWrist: Offset(0.62, 0.40),
    leftHip: Offset(0.45, 0.52),
    rightHip: Offset(0.55, 0.52),
    leftKnee: Offset(0.42, 0.50),
    rightKnee: Offset(0.58, 0.50),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  static const poses = [
    standing,
    normalSquatDepth,
    deepSquatDepth,
    normalSquatDepth,
    standing,
  ];
}

const deepSquatsDemo = MovementDemo(
  poses: _DeepSquatsKeyPoses.poses,
  duration: Duration(milliseconds: 2800),
);

// ── Squat Jacks ──────────────────────────────────────────────────────────────
// ConfigurableRepValidator with squatJackRepDefinition:
// "start" = arms down + feet together + standing (hipToKneeRatio > 0.86),
// "active" = arms up + feet wide + squat depth (hipToKneeRatio < 0.58).
// Front view: a jumping jack that adds a squat at the open phase.

class _SquatJacksKeyPoses {
  // Closed — arms down, feet together, standing tall.
  static const closed = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.40, 0.26),
    rightElbow: Offset(0.60, 0.26),
    leftWrist: Offset(0.41, 0.34),
    rightWrist: Offset(0.59, 0.34),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.47, 0.76),
    rightAnkle: Offset(0.53, 0.76),
  );

  // Open + squat — arms up, feet wide, squat depth.
  // Combines jumping jack open pose with squat descent.
  static const openSquat = NuvoCharacterPose(
    head: Offset(0.50, 0.10),
    neck: Offset(0.50, 0.16),
    leftShoulder: Offset(0.42, 0.20),
    rightShoulder: Offset(0.58, 0.20),
    leftElbow: Offset(0.34, 0.14),
    rightElbow: Offset(0.66, 0.14),
    leftWrist: Offset(0.30, 0.08),
    rightWrist: Offset(0.70, 0.08),
    leftHip: Offset(0.45, 0.44),
    rightHip: Offset(0.55, 0.44),
    leftKnee: Offset(0.38, 0.54),
    rightKnee: Offset(0.62, 0.54),
    leftAnkle: Offset(0.30, 0.76),
    rightAnkle: Offset(0.70, 0.76),
  );

  static const poses = [closed, openSquat, closed];
}

const squatJacksDemo = MovementDemo(
  poses: _SquatJacksKeyPoses.poses,
  duration: Duration(milliseconds: 2400),
);

// ── Jump Squats ──────────────────────────────────────────────────────────────
// MultiPhaseSequenceValidator with buildJumpSquatDefinition:
// STANDING → SQUAT → AIRBORNE → LANDING → standing.
// Front view: squat down, then jump up with arms raised, then land and stand.
// The airborne pose visibly leaves the ground (ankles rise above baseline).

class _JumpSquatsKeyPoses {
  // Standing — neutral, arms at sides.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Squat — hips low, knees bent, arms forward for balance.
  static const squat = NuvoCharacterPose(
    head: Offset(0.50, 0.14),
    neck: Offset(0.50, 0.20),
    leftShoulder: Offset(0.42, 0.23),
    rightShoulder: Offset(0.58, 0.23),
    leftElbow: Offset(0.36, 0.30),
    rightElbow: Offset(0.64, 0.30),
    leftWrist: Offset(0.34, 0.36),
    rightWrist: Offset(0.66, 0.36),
    leftHip: Offset(0.45, 0.48),
    rightHip: Offset(0.55, 0.48),
    leftKnee: Offset(0.42, 0.54),
    rightKnee: Offset(0.58, 0.54),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Airborne — whole body lifted up, arms overhead, ankles above baseline.
  // The y-coordinates are shifted up by ~0.12 to visibly leave the ground.
  static const airborne = NuvoCharacterPose(
    head: Offset(0.50, 0.02),
    neck: Offset(0.50, 0.08),
    leftShoulder: Offset(0.42, 0.12),
    rightShoulder: Offset(0.58, 0.12),
    leftElbow: Offset(0.36, 0.04),
    rightElbow: Offset(0.64, 0.04),
    leftWrist: Offset(0.34, 0.00),
    rightWrist: Offset(0.66, 0.00),
    leftHip: Offset(0.45, 0.28),
    rightHip: Offset(0.55, 0.28),
    leftKnee: Offset(0.44, 0.44),
    rightKnee: Offset(0.56, 0.44),
    leftAnkle: Offset(0.44, 0.60),
    rightAnkle: Offset(0.56, 0.60),
  );

  // Landing — back on the ground, slight squat to absorb impact.
  static const landing = NuvoCharacterPose(
    head: Offset(0.50, 0.12),
    neck: Offset(0.50, 0.18),
    leftShoulder: Offset(0.42, 0.21),
    rightShoulder: Offset(0.58, 0.21),
    leftElbow: Offset(0.38, 0.28),
    rightElbow: Offset(0.62, 0.28),
    leftWrist: Offset(0.36, 0.34),
    rightWrist: Offset(0.64, 0.34),
    leftHip: Offset(0.45, 0.46),
    rightHip: Offset(0.55, 0.46),
    leftKnee: Offset(0.43, 0.55),
    rightKnee: Offset(0.57, 0.55),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  static const poses = [standing, squat, airborne, landing, standing];
}

const jumpSquatsDemo = MovementDemo(
  poses: _JumpSquatsKeyPoses.poses,
  duration: Duration(milliseconds: 2800),
);

// ── Lunge Jumps ──────────────────────────────────────────────────────────────
// MultiPhaseSequenceValidator with buildLungeJumpDefinitions:
// RIGHT_LUNGE → AIRBORNE → LEFT_LUNGE (and vice versa).
// Front view: lunge right, jump switch, lunge left, jump switch.
// The airborne transition visibly lifts the body off the ground.

class _LungeJumpsKeyPoses {
  // Lunge right — right leg forward, left leg back.
  // Mirrors the existing lunges demo lungeRight pose.
  static const lungeRight = NuvoCharacterPose(
    head: Offset(0.52, 0.10),
    neck: Offset(0.52, 0.17),
    leftShoulder: Offset(0.44, 0.20),
    rightShoulder: Offset(0.60, 0.20),
    leftElbow: Offset(0.41, 0.30),
    rightElbow: Offset(0.63, 0.30),
    leftWrist: Offset(0.40, 0.40),
    rightWrist: Offset(0.64, 0.40),
    leftHip: Offset(0.47, 0.42),
    rightHip: Offset(0.57, 0.42),
    leftKnee: Offset(0.42, 0.58),
    rightKnee: Offset(0.64, 0.52),
    leftAnkle: Offset(0.40, 0.76),
    rightAnkle: Offset(0.70, 0.72),
  );

  // Airborne — body lifted, legs switching, arms up for momentum.
  // The y-coordinates are shifted up to visibly leave the ground.
  static const airborne = NuvoCharacterPose(
    head: Offset(0.50, 0.04),
    neck: Offset(0.50, 0.10),
    leftShoulder: Offset(0.42, 0.14),
    rightShoulder: Offset(0.58, 0.14),
    leftElbow: Offset(0.36, 0.06),
    rightElbow: Offset(0.64, 0.06),
    leftWrist: Offset(0.34, 0.02),
    rightWrist: Offset(0.66, 0.02),
    leftHip: Offset(0.45, 0.30),
    rightHip: Offset(0.55, 0.30),
    leftKnee: Offset(0.40, 0.44),
    rightKnee: Offset(0.60, 0.44),
    leftAnkle: Offset(0.42, 0.58),
    rightAnkle: Offset(0.58, 0.58),
  );

  // Lunge left — left leg forward, right leg back.
  // Mirrors the existing lunges demo lungeLeft pose.
  static const lungeLeft = NuvoCharacterPose(
    head: Offset(0.48, 0.10),
    neck: Offset(0.48, 0.17),
    leftShoulder: Offset(0.40, 0.20),
    rightShoulder: Offset(0.56, 0.20),
    leftElbow: Offset(0.37, 0.30),
    rightElbow: Offset(0.59, 0.30),
    leftWrist: Offset(0.36, 0.40),
    rightWrist: Offset(0.60, 0.40),
    leftHip: Offset(0.43, 0.42),
    rightHip: Offset(0.53, 0.42),
    leftKnee: Offset(0.36, 0.52),
    rightKnee: Offset(0.58, 0.58),
    leftAnkle: Offset(0.30, 0.72),
    rightAnkle: Offset(0.60, 0.76),
  );

  static const poses = [lungeRight, airborne, lungeLeft, airborne, lungeRight];
}

const lungeJumpsDemo = MovementDemo(
  poses: _LungeJumpsKeyPoses.poses,
  duration: Duration(milliseconds: 3200),
);

// ── Jumping Jacks ─────────────────────────────────────────────────────────────
// JumpingJacksValidator: "start" = arms down + feet together,
// "active" = arms overhead + feet apart.

class _JumpingJacksKeyPoses {
  // Start — arms at sides, feet together.
  static const start = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.47, 0.40),
    rightHip: Offset(0.53, 0.40),
    leftKnee: Offset(0.47, 0.58),
    rightKnee: Offset(0.53, 0.58),
    leftAnkle: Offset(0.47, 0.76),
    rightAnkle: Offset(0.53, 0.76),
  );

  // Active — arms overhead, feet apart.
  static const active = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.38, 0.10),
    rightElbow: Offset(0.62, 0.10),
    leftWrist: Offset(0.36, 0.02),
    rightWrist: Offset(0.64, 0.02),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.40, 0.58),
    rightKnee: Offset(0.60, 0.58),
    leftAnkle: Offset(0.36, 0.76),
    rightAnkle: Offset(0.64, 0.76),
  );

  static const poses = [start, active, start];
}

const jumpingJacksDemo = MovementDemo(
  poses: _JumpingJacksKeyPoses.poses,
  duration: Duration(milliseconds: 1600),
);

// ── Lunges ────────────────────────────────────────────────────────────────────
// LungesValidator: "start" = standing, "active" = one leg forward,
// front knee bent, back leg extended.

class _LungesKeyPoses {
  // Standing — neutral.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Lunge — right leg forward, left leg back.
  static const lungeRight = NuvoCharacterPose(
    head: Offset(0.52, 0.10),
    neck: Offset(0.52, 0.17),
    leftShoulder: Offset(0.44, 0.20),
    rightShoulder: Offset(0.60, 0.20),
    leftElbow: Offset(0.41, 0.30),
    rightElbow: Offset(0.63, 0.30),
    leftWrist: Offset(0.40, 0.40),
    rightWrist: Offset(0.64, 0.40),
    leftHip: Offset(0.47, 0.42),
    rightHip: Offset(0.57, 0.42),
    leftKnee: Offset(0.42, 0.58),
    rightKnee: Offset(0.64, 0.52),
    leftAnkle: Offset(0.40, 0.76),
    rightAnkle: Offset(0.70, 0.72),
  );

  // Lunge — left leg forward, right leg back.
  static const lungeLeft = NuvoCharacterPose(
    head: Offset(0.48, 0.10),
    neck: Offset(0.48, 0.17),
    leftShoulder: Offset(0.40, 0.20),
    rightShoulder: Offset(0.56, 0.20),
    leftElbow: Offset(0.37, 0.30),
    rightElbow: Offset(0.59, 0.30),
    leftWrist: Offset(0.36, 0.40),
    rightWrist: Offset(0.60, 0.40),
    leftHip: Offset(0.43, 0.42),
    rightHip: Offset(0.53, 0.42),
    leftKnee: Offset(0.36, 0.52),
    rightKnee: Offset(0.58, 0.58),
    leftAnkle: Offset(0.30, 0.72),
    rightAnkle: Offset(0.60, 0.76),
  );

  static const poses = [standing, lungeRight, standing, lungeLeft, standing];
}

const lungesDemo = MovementDemo(
  poses: _LungesKeyPoses.poses,
  duration: Duration(milliseconds: 3600),
);

// ── High Knees ────────────────────────────────────────────────────────────────
// HighKneesValidator: "start" = standing, "active" = one knee above hip line.
// Alternates left and right knees.

class _HighKneesKeyPoses {
  // Standing — neutral.
  static const standing = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.39, 0.28),
    rightElbow: Offset(0.61, 0.28),
    leftWrist: Offset(0.38, 0.38),
    rightWrist: Offset(0.62, 0.38),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Right knee up — clearly above hip line (y=0.32 vs hip y=0.40).
  static const rightKneeUp = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.36, 0.24),
    rightElbow: Offset(0.64, 0.24),
    leftWrist: Offset(0.34, 0.30),
    rightWrist: Offset(0.66, 0.30),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.58, 0.32),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.44),
  );

  // Left knee up — clearly above hip line (y=0.32 vs hip y=0.40).
  static const leftKneeUp = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.36, 0.24),
    rightElbow: Offset(0.64, 0.24),
    leftWrist: Offset(0.34, 0.30),
    rightWrist: Offset(0.66, 0.30),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.42, 0.32),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.44),
    rightAnkle: Offset(0.56, 0.76),
  );

  static const poses = [standing, rightKneeUp, standing, leftKneeUp, standing];
}

const highKneesDemo = MovementDemo(
  poses: _HighKneesKeyPoses.poses,
  duration: Duration(milliseconds: 2000),
);

// ── Plank Hold ────────────────────────────────────────────────────────────────
// PlankHoldValidator: hold position — body straight, forearms on ground.
// Side view (210 x 150 stage): forearm plank, elbow under the shoulder, body
// one straight line to the toes, held steady with a subtle breathing rise.

class _PlankHoldKeyPoses {
  // Plank position — forearm flat on the floor, body straight.
  static const plank = NuvoCharacterPose(
    head: Offset(0.1653, 0.6077),
    neck: Offset(0.2762, 0.6467),
    leftShoulder: Offset(0.2762, 0.6467),
    rightShoulder: Offset(0.3000, 0.6467),
    leftElbow: Offset(0.2762, 0.8333),
    rightElbow: Offset(0.3000, 0.8333),
    leftWrist: Offset(0.1333, 0.8367),
    rightWrist: Offset(0.1571, 0.8367),
    leftHip: Offset(0.5362, 0.7195),
    rightHip: Offset(0.5600, 0.7195),
    leftKnee: Offset(0.7219, 0.7715),
    rightKnee: Offset(0.7457, 0.7715),
    leftAnkle: Offset(0.8952, 0.8200),
    rightAnkle: Offset(0.9190, 0.8200),
  );

  // Breath in — chest and hips lift a touch.
  static const plankBreath = NuvoCharacterPose(
    head: Offset(0.1660, 0.5843),
    neck: Offset(0.2762, 0.6267),
    leftShoulder: Offset(0.2762, 0.6267),
    rightShoulder: Offset(0.3000, 0.6267),
    leftElbow: Offset(0.2762, 0.8333),
    rightElbow: Offset(0.3000, 0.8333),
    leftWrist: Offset(0.1333, 0.8367),
    rightWrist: Offset(0.1571, 0.8367),
    leftHip: Offset(0.5362, 0.6945),
    rightHip: Offset(0.5600, 0.6945),
    leftKnee: Offset(0.7219, 0.7659),
    rightKnee: Offset(0.7457, 0.7659),
    leftAnkle: Offset(0.8952, 0.8200),
    rightAnkle: Offset(0.9190, 0.8200),
  );

  static const poses = [plank, plankBreath, plank];
}

const plankHoldDemo = MovementDemo(
  poses: _PlankHoldKeyPoses.poses,
  duration: Duration(milliseconds: 4000),
  sideView: true,
);

/// Maps a [MotionActivityType] to its pre-verify [MovementDemo].
/// Returns null if no demo is available for the movement.
/// This is the presentation-layer registry of movement demos —
/// the domain catalog stays free of UI dependencies.
MovementDemo? movementDemoForType(MotionActivityType type) {
  return switch (type) {
    MotionActivityType.pushUps => pushupsDemo,
    MotionActivityType.squats => squatsDemo,
    MotionActivityType.jumpingJacks => jumpingJacksDemo,
    MotionActivityType.lunges => lungesDemo,
    MotionActivityType.highKnees => highKneesDemo,
    MotionActivityType.armRaises => armRaisesDemo,
    MotionActivityType.plankHold => plankHoldDemo,
    MotionActivityType.sumoSquats => sumoSquatsDemo,
    MotionActivityType.sideLunges => sideLungesDemo,
    MotionActivityType.deepSquats => deepSquatsDemo,
    MotionActivityType.squatJacks => squatJacksDemo,
    MotionActivityType.jumpSquats => jumpSquatsDemo,
    MotionActivityType.lungeJumps => lungeJumpsDemo,
    MotionActivityType.runningInPlace => runningInPlaceDemo,
    MotionActivityType.treadmillRunning => treadmillRunningDemo,
    MotionActivityType.walkingInPlace => walkingInPlaceDemo,
    MotionActivityType.marchingInPlace => marchingInPlaceDemo,
    MotionActivityType.buttKicks => buttKicksDemo,
    MotionActivityType.mountainClimbers => mountainClimbersDemo,
    MotionActivityType.burpees => burpeesDemo,
    MotionActivityType.stepUps => stepUpsDemo,
    MotionActivityType.calfRaises => calfRaisesDemo,
    MotionActivityType.lateralSteps => lateralStepsDemo,
    MotionActivityType.basketballShot => basketballShotDemo,
    MotionActivityType.remote => null,
  };
}
