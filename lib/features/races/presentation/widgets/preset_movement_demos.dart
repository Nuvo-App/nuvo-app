import 'package:flutter/material.dart';

import '../../domain/motion_activity.dart';
import 'arm_raises_animation.dart';
import 'movement_demo.dart';
import 'nuvo_character_painter.dart';

/// Key poses for each preset movement, authored to match what the
/// corresponding validator expects. Each demo cycles through the
/// movement's distinct phases (down/up, start/active, etc.) and loops.

// ── Pushups ───────────────────────────────────────────────────────────────────
// PushupsValidator: "down" = elbow angle < 112°, "up" = elbow angle > 150°.
// Front view: body horizontal, arms pushing up and down. Wrists stay on
// the ground; the body rises and falls.

class _PushupsKeyPoses {
  // Top position — arms extended, body up. Body is horizontal: head,
  // shoulders, hips, knees, ankles all at similar Y. Arms are vertical
  // from shoulders down to wrists on the ground.
  static const top = NuvoCharacterPose(
    head: Offset(0.50, 0.22),
    neck: Offset(0.50, 0.23),
    leftShoulder: Offset(0.43, 0.24),
    rightShoulder: Offset(0.57, 0.24),
    leftElbow: Offset(0.43, 0.32),
    rightElbow: Offset(0.57, 0.32),
    leftWrist: Offset(0.43, 0.40),
    rightWrist: Offset(0.57, 0.40),
    leftHip: Offset(0.46, 0.25),
    rightHip: Offset(0.54, 0.25),
    leftKnee: Offset(0.46, 0.26),
    rightKnee: Offset(0.54, 0.26),
    leftAnkle: Offset(0.46, 0.27),
    rightAnkle: Offset(0.54, 0.27),
  );

  // Bottom position — chest lowered, elbows bent out to sides. Body
  // drops by ~0.10; wrists stay fixed on the ground.
  static const bottom = NuvoCharacterPose(
    head: Offset(0.50, 0.32),
    neck: Offset(0.50, 0.33),
    leftShoulder: Offset(0.43, 0.34),
    rightShoulder: Offset(0.57, 0.34),
    leftElbow: Offset(0.38, 0.30),
    rightElbow: Offset(0.62, 0.30),
    leftWrist: Offset(0.43, 0.40),
    rightWrist: Offset(0.57, 0.40),
    leftHip: Offset(0.46, 0.35),
    rightHip: Offset(0.54, 0.35),
    leftKnee: Offset(0.46, 0.36),
    rightKnee: Offset(0.54, 0.36),
    leftAnkle: Offset(0.46, 0.37),
    rightAnkle: Offset(0.54, 0.37),
  );

  static const poses = [top, bottom, top];
}

const pushupsDemo = MovementDemo(
  poses: _PushupsKeyPoses.poses,
  duration: Duration(milliseconds: 2400),
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
// Side view: body horizontal, held steady with slight breathing.

class _PlankHoldKeyPoses {
  // Plank position — body straight, forearms down.
  static const plank = NuvoCharacterPose(
    head: Offset(0.18, 0.35),
    neck: Offset(0.24, 0.34),
    leftShoulder: Offset(0.30, 0.33),
    rightShoulder: Offset(0.30, 0.38),
    leftElbow: Offset(0.24, 0.40),
    rightElbow: Offset(0.24, 0.45),
    leftWrist: Offset(0.20, 0.46),
    rightWrist: Offset(0.20, 0.50),
    leftHip: Offset(0.50, 0.36),
    rightHip: Offset(0.50, 0.41),
    leftKnee: Offset(0.68, 0.37),
    rightKnee: Offset(0.68, 0.42),
    leftAnkle: Offset(0.82, 0.38),
    rightAnkle: Offset(0.82, 0.43),
  );

  // Slight dip — gentle breathing motion.
  static const plankDip = NuvoCharacterPose(
    head: Offset(0.18, 0.37),
    neck: Offset(0.24, 0.36),
    leftShoulder: Offset(0.30, 0.35),
    rightShoulder: Offset(0.30, 0.40),
    leftElbow: Offset(0.24, 0.40),
    rightElbow: Offset(0.24, 0.45),
    leftWrist: Offset(0.20, 0.46),
    rightWrist: Offset(0.20, 0.50),
    leftHip: Offset(0.50, 0.38),
    rightHip: Offset(0.50, 0.43),
    leftKnee: Offset(0.68, 0.39),
    rightKnee: Offset(0.68, 0.44),
    leftAnkle: Offset(0.82, 0.38),
    rightAnkle: Offset(0.82, 0.43),
  );

  static const poses = [plank, plankDip, plank];
}

const plankHoldDemo = MovementDemo(
  poses: _PlankHoldKeyPoses.poses,
  duration: Duration(milliseconds: 4000),
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
  };
}
