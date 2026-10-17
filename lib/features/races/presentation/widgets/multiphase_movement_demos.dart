import 'package:flutter/material.dart';

import 'movement_demo.dart';
import 'nuvo_character_painter.dart';

/// Key-pose loops for movements that pass through several distinct phases:
/// burpees, mountain climbers and the basketball shot.
///
/// Poses use the same normalized 0–1 space as the demos in
/// preset_movement_demos.dart. Plank-like poses are authored as a diagonal
/// side-on figure (head left, feet right) like the pushup poses, so they
/// should be flagged `sideView` where that option exists.

// ── Shared standing pose ──────────────────────────────────────────────────────

const _standing = NuvoCharacterPose(
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

// ── Burpees ───────────────────────────────────────────────────────────────────
// Stand, crouch with hands on the floor, kick back to plank, chest down,
// jump the feet in, jump up with hands overhead, stand.

class _BurpeesKeyPoses {
  // Crouch — hips low, both hands planted on the floor in front of the feet.
  static const crouch = NuvoCharacterPose(
    head: Offset(0.50, 0.34),
    neck: Offset(0.50, 0.40),
    leftShoulder: Offset(0.42, 0.42),
    rightShoulder: Offset(0.58, 0.42),
    leftElbow: Offset(0.36, 0.56),
    rightElbow: Offset(0.64, 0.56),
    leftWrist: Offset(0.36, 0.74),
    rightWrist: Offset(0.64, 0.74),
    leftHip: Offset(0.45, 0.60),
    rightHip: Offset(0.55, 0.60),
    leftKnee: Offset(0.38, 0.66),
    rightKnee: Offset(0.62, 0.66),
    leftAnkle: Offset(0.44, 0.78),
    rightAnkle: Offset(0.56, 0.78),
  );

  // Plank — feet kicked back, arms straight, body in one diagonal line.
  static const plank = NuvoCharacterPose(
    head: Offset(0.16, 0.34),
    neck: Offset(0.23, 0.41),
    leftShoulder: Offset(0.28, 0.44),
    rightShoulder: Offset(0.30, 0.48),
    leftElbow: Offset(0.30, 0.57),
    rightElbow: Offset(0.33, 0.60),
    leftWrist: Offset(0.31, 0.68),
    rightWrist: Offset(0.35, 0.71),
    leftHip: Offset(0.64, 0.50),
    rightHip: Offset(0.67, 0.54),
    leftKnee: Offset(0.79, 0.54),
    rightKnee: Offset(0.82, 0.58),
    leftAnkle: Offset(0.92, 0.57),
    rightAnkle: Offset(0.95, 0.61),
  );

  // Chest down — pushup bottom.
  static const chestDown = NuvoCharacterPose(
    head: Offset(0.22, 0.45),
    neck: Offset(0.29, 0.51),
    leftShoulder: Offset(0.35, 0.53),
    rightShoulder: Offset(0.37, 0.57),
    leftElbow: Offset(0.40, 0.62),
    rightElbow: Offset(0.43, 0.66),
    leftWrist: Offset(0.31, 0.68),
    rightWrist: Offset(0.35, 0.71),
    leftHip: Offset(0.66, 0.60),
    rightHip: Offset(0.69, 0.64),
    leftKnee: Offset(0.80, 0.59),
    rightKnee: Offset(0.83, 0.63),
    leftAnkle: Offset(0.92, 0.57),
    rightAnkle: Offset(0.95, 0.61),
  );

  // Airborne — straight jump, hands overhead, feet off the ground.
  static const jump = NuvoCharacterPose(
    head: Offset(0.50, 0.04),
    neck: Offset(0.50, 0.10),
    leftShoulder: Offset(0.42, 0.13),
    rightShoulder: Offset(0.58, 0.13),
    leftElbow: Offset(0.40, 0.05),
    rightElbow: Offset(0.60, 0.05),
    leftWrist: Offset(0.42, 0.00),
    rightWrist: Offset(0.58, 0.00),
    leftHip: Offset(0.45, 0.30),
    rightHip: Offset(0.55, 0.30),
    leftKnee: Offset(0.44, 0.46),
    rightKnee: Offset(0.56, 0.46),
    leftAnkle: Offset(0.44, 0.62),
    rightAnkle: Offset(0.56, 0.62),
  );

  static const poses = [
    _standing,
    crouch,
    plank,
    chestDown,
    crouch,
    jump,
    _standing,
  ];
}

const burpeesDemo = MovementDemo(
  poses: _BurpeesKeyPoses.poses,
  duration: Duration(milliseconds: 3400),
);

// ── Mountain climbers ─────────────────────────────────────────────────────────
// Side-on plank; knees drive alternately toward the chest.

class _MountainClimbersKeyPoses {
  // Left knee driven in, right leg extended back.
  static const leftIn = NuvoCharacterPose(
    head: Offset(0.16, 0.34),
    neck: Offset(0.23, 0.41),
    leftShoulder: Offset(0.28, 0.44),
    rightShoulder: Offset(0.30, 0.48),
    leftElbow: Offset(0.30, 0.57),
    rightElbow: Offset(0.33, 0.60),
    leftWrist: Offset(0.31, 0.68),
    rightWrist: Offset(0.35, 0.71),
    leftHip: Offset(0.64, 0.48),
    rightHip: Offset(0.67, 0.52),
    leftKnee: Offset(0.50, 0.58),
    rightKnee: Offset(0.82, 0.57),
    leftAnkle: Offset(0.58, 0.68),
    rightAnkle: Offset(0.95, 0.61),
  );

  // Right knee driven in, left leg extended back.
  static const rightIn = NuvoCharacterPose(
    head: Offset(0.16, 0.34),
    neck: Offset(0.23, 0.41),
    leftShoulder: Offset(0.28, 0.44),
    rightShoulder: Offset(0.30, 0.48),
    leftElbow: Offset(0.30, 0.57),
    rightElbow: Offset(0.33, 0.60),
    leftWrist: Offset(0.31, 0.68),
    rightWrist: Offset(0.35, 0.71),
    leftHip: Offset(0.64, 0.48),
    rightHip: Offset(0.67, 0.52),
    leftKnee: Offset(0.79, 0.53),
    rightKnee: Offset(0.53, 0.62),
    leftAnkle: Offset(0.92, 0.57),
    rightAnkle: Offset(0.61, 0.71),
  );

  static const poses = [leftIn, rightIn, leftIn, rightIn, leftIn];
}

const mountainClimbersDemo = MovementDemo(
  poses: _MountainClimbersKeyPoses.poses,
  duration: Duration(milliseconds: 1600),
  sideView: true,
);

// ── Basketball shot ───────────────────────────────────────────────────────────
// Ball at the chest, dip, drive up through the legs and arms, release,
// follow through, return.

class _BasketballShotKeyPoses {
  // Ball held at the chest — hands together in front of the sternum.
  static const chest = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.42, 0.18),
    rightShoulder: Offset(0.58, 0.18),
    leftElbow: Offset(0.36, 0.30),
    rightElbow: Offset(0.64, 0.30),
    leftWrist: Offset(0.47, 0.28),
    rightWrist: Offset(0.53, 0.28),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Dip — knees bend, ball stays tucked at the chest.
  static const dip = NuvoCharacterPose(
    head: Offset(0.50, 0.14),
    neck: Offset(0.50, 0.21),
    leftShoulder: Offset(0.42, 0.24),
    rightShoulder: Offset(0.58, 0.24),
    leftElbow: Offset(0.36, 0.35),
    rightElbow: Offset(0.64, 0.35),
    leftWrist: Offset(0.47, 0.34),
    rightWrist: Offset(0.53, 0.34),
    leftHip: Offset(0.45, 0.47),
    rightHip: Offset(0.55, 0.47),
    leftKnee: Offset(0.40, 0.60),
    rightKnee: Offset(0.60, 0.60),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  // Release — legs and arms fully extended upward, up on the toes.
  static const release = NuvoCharacterPose(
    head: Offset(0.50, 0.07),
    neck: Offset(0.50, 0.14),
    leftShoulder: Offset(0.43, 0.17),
    rightShoulder: Offset(0.57, 0.17),
    leftElbow: Offset(0.45, 0.08),
    rightElbow: Offset(0.55, 0.08),
    leftWrist: Offset(0.47, 0.00),
    rightWrist: Offset(0.53, 0.00),
    leftHip: Offset(0.45, 0.39),
    rightHip: Offset(0.55, 0.39),
    leftKnee: Offset(0.44, 0.57),
    rightKnee: Offset(0.56, 0.57),
    leftAnkle: Offset(0.44, 0.73),
    rightAnkle: Offset(0.56, 0.73),
  );

  // Follow-through — wrists snap over, hands open and drop slightly.
  static const followThrough = NuvoCharacterPose(
    head: Offset(0.50, 0.08),
    neck: Offset(0.50, 0.15),
    leftShoulder: Offset(0.43, 0.18),
    rightShoulder: Offset(0.57, 0.18),
    leftElbow: Offset(0.42, 0.10),
    rightElbow: Offset(0.58, 0.10),
    leftWrist: Offset(0.40, 0.03),
    rightWrist: Offset(0.60, 0.03),
    leftHip: Offset(0.45, 0.40),
    rightHip: Offset(0.55, 0.40),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.76),
    rightAnkle: Offset(0.56, 0.76),
  );

  static const poses = [_standing, chest, dip, release, followThrough, _standing];
}

const basketballShotDemo = MovementDemo(
  poses: _BasketballShotKeyPoses.poses,
  duration: Duration(milliseconds: 2400),
);
