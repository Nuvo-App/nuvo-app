import 'package:flutter/material.dart';

import 'movement_demo.dart';
import 'nuvo_character_painter.dart';

/// Key poses for the Arm Raises movement, matching what
/// [ArmRaisesValidator] expects:
/// - "down" = wrists below shoulder line, above hips
/// - "up" = wrists above shoulder line by 0.04+
///
/// The animation cycles: down → up → down, looping smoothly.
class ArmRaisesKeyPoses {
  // Neutral standing pose — arms at sides.
  static const down = NuvoCharacterPose(
    head: Offset(0.50, 0.10),
    neck: Offset(0.50, 0.17),
    leftShoulder: Offset(0.42, 0.20),
    rightShoulder: Offset(0.58, 0.20),
    leftElbow: Offset(0.39, 0.30),
    rightElbow: Offset(0.61, 0.30),
    leftWrist: Offset(0.38, 0.39),
    rightWrist: Offset(0.62, 0.39),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.74),
    rightAnkle: Offset(0.56, 0.74),
  );

  // Arms beginning to raise — elbows at shoulder height.
  static const raising = NuvoCharacterPose(
    head: Offset(0.50, 0.10),
    neck: Offset(0.50, 0.17),
    leftShoulder: Offset(0.42, 0.20),
    rightShoulder: Offset(0.58, 0.20),
    leftElbow: Offset(0.36, 0.20),
    rightElbow: Offset(0.64, 0.20),
    leftWrist: Offset(0.34, 0.22),
    rightWrist: Offset(0.66, 0.22),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.74),
    rightAnkle: Offset(0.56, 0.74),
  );

  // Arms at shoulder height — wrists level with shoulders.
  static const shoulderLevel = NuvoCharacterPose(
    head: Offset(0.50, 0.10),
    neck: Offset(0.50, 0.17),
    leftShoulder: Offset(0.42, 0.20),
    rightShoulder: Offset(0.58, 0.20),
    leftElbow: Offset(0.34, 0.18),
    rightElbow: Offset(0.66, 0.18),
    leftWrist: Offset(0.28, 0.20),
    rightWrist: Offset(0.72, 0.20),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.74),
    rightAnkle: Offset(0.56, 0.74),
  );

  // Arms above shoulders — wrists clearly above shoulder line.
  static const aboveShoulders = NuvoCharacterPose(
    head: Offset(0.50, 0.10),
    neck: Offset(0.50, 0.17),
    leftShoulder: Offset(0.42, 0.20),
    rightShoulder: Offset(0.58, 0.20),
    leftElbow: Offset(0.36, 0.12),
    rightElbow: Offset(0.64, 0.12),
    leftWrist: Offset(0.34, 0.06),
    rightWrist: Offset(0.66, 0.06),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.74),
    rightAnkle: Offset(0.56, 0.74),
  );

  // Arms fully overhead — wrists at the top of the range.
  static const overhead = NuvoCharacterPose(
    head: Offset(0.50, 0.10),
    neck: Offset(0.50, 0.17),
    leftShoulder: Offset(0.42, 0.20),
    rightShoulder: Offset(0.58, 0.20),
    leftElbow: Offset(0.40, 0.08),
    rightElbow: Offset(0.60, 0.08),
    leftWrist: Offset(0.42, 0.01),
    rightWrist: Offset(0.58, 0.01),
    leftHip: Offset(0.45, 0.42),
    rightHip: Offset(0.55, 0.42),
    leftKnee: Offset(0.44, 0.58),
    rightKnee: Offset(0.56, 0.58),
    leftAnkle: Offset(0.44, 0.74),
    rightAnkle: Offset(0.56, 0.74),
  );

  /// All key poses in order for one cycle (up then back down).
  static const poses = [
    down,
    raising,
    shoulderLevel,
    aboveShoulders,
    overhead,
    aboveShoulders,
    shoulderLevel,
    raising,
  ];
}

/// [MovementDemo] for Arm Raises — the canonical demo data for this movement.
const armRaisesDemo = MovementDemo(
  poses: ArmRaisesKeyPoses.poses,
  duration: Duration(milliseconds: 2800),
);

/// A widget that displays an animated illustrated Nuvo character performing
/// Arm Raises. The animation loops continuously.
///
/// This is a thin wrapper around [NuvoMovementAnimation] with the
/// [armRaisesDemo] data, kept for backward compatibility with existing
/// call sites and tests.
class ArmRaisesAnimation extends StatelessWidget {
  const ArmRaisesAnimation({
    super.key,
    this.bodyColor = const Color(0xFF07152D),
    this.accentColor = const Color(0xFF1264FF),
  });

  final Color bodyColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return NuvoMovementAnimation(
      demo: armRaisesDemo,
      bodyColor: bodyColor,
      accentColor: accentColor,
    );
  }
}
