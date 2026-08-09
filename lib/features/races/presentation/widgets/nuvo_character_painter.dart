import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single pose configuration for the illustrated Nuvo character.
///
/// All coordinates are in a normalized 0–1 space where (0.5, 0) is the
/// top-centre of the canvas.  Y increases downward.
class NuvoCharacterPose {
  const NuvoCharacterPose({
    required this.head,
    required this.neck,
    required this.leftShoulder,
    required this.rightShoulder,
    required this.leftElbow,
    required this.rightElbow,
    required this.leftWrist,
    required this.rightWrist,
    required this.leftHip,
    required this.rightHip,
    required this.leftKnee,
    required this.rightKnee,
    required this.leftAnkle,
    required this.rightAnkle,
  });

  final Offset head;
  final Offset neck;
  final Offset leftShoulder;
  final Offset rightShoulder;
  final Offset leftElbow;
  final Offset rightElbow;
  final Offset leftWrist;
  final Offset rightWrist;
  final Offset leftHip;
  final Offset rightHip;
  final Offset leftKnee;
  final Offset rightKnee;
  final Offset leftAnkle;
  final Offset rightAnkle;

  /// Linear interpolation between two poses.
  static NuvoCharacterPose lerp(
    NuvoCharacterPose a,
    NuvoCharacterPose b,
    double t,
  ) {
    return NuvoCharacterPose(
      head: Offset.lerp(a.head, b.head, t)!,
      neck: Offset.lerp(a.neck, b.neck, t)!,
      leftShoulder: Offset.lerp(a.leftShoulder, b.leftShoulder, t)!,
      rightShoulder: Offset.lerp(a.rightShoulder, b.rightShoulder, t)!,
      leftElbow: Offset.lerp(a.leftElbow, b.leftElbow, t)!,
      rightElbow: Offset.lerp(a.rightElbow, b.rightElbow, t)!,
      leftWrist: Offset.lerp(a.leftWrist, b.leftWrist, t)!,
      rightWrist: Offset.lerp(a.rightWrist, b.rightWrist, t)!,
      leftHip: Offset.lerp(a.leftHip, b.leftHip, t)!,
      rightHip: Offset.lerp(a.rightHip, b.rightHip, t)!,
      leftKnee: Offset.lerp(a.leftKnee, b.leftKnee, t)!,
      rightKnee: Offset.lerp(a.rightKnee, b.rightKnee, t)!,
      leftAnkle: Offset.lerp(a.leftAnkle, b.leftAnkle, t)!,
      rightAnkle: Offset.lerp(a.rightAnkle, b.rightAnkle, t)!,
    );
  }
}

/// Paints an illustrated Nuvo athlete from a [NuvoCharacterPose].
///
/// The character is built from filled rounded body segments — capsules for
/// limbs, a rounded torso shape, and a circular head — so it reads as one
/// continuous person, not a skeleton.
class NuvoCharacterPainter extends CustomPainter {
  NuvoCharacterPainter({
    required this.pose,
    this.bodyColor = const Color(0xFF07152D),
    this.accentColor = const Color(0xFF1264FF),
    this.backgroundRadius = 0,
  });

  final NuvoCharacterPose pose;

  /// Main body fill colour.
  final Color bodyColor;

  /// Accent colour for the chest "N" and optional highlights.
  final Color accentColor;

  /// Corner radius for the rounded-rect background plate (0 = no plate).
  final double backgroundRadius;

  @override
  void paint(Canvas canvas, Size size) {
    // Map normalized 0–1 coordinates to canvas pixels.
    Offset p(Offset normalized) =>
        Offset(normalized.dx * size.width, normalized.dy * size.height);

    final head = p(pose.head);
    final neck = p(pose.neck);
    final lSh = p(pose.leftShoulder);
    final rSh = p(pose.rightShoulder);
    final lEl = p(pose.leftElbow);
    final rEl = p(pose.rightElbow);
    final lWr = p(pose.leftWrist);
    final rWr = p(pose.rightWrist);
    final lHip = p(pose.leftHip);
    final rHip = p(pose.rightHip);
    final lKn = p(pose.leftKnee);
    final rKn = p(pose.rightKnee);
    final lAnk = p(pose.leftAnkle);
    final rAnk = p(pose.rightAnkle);

    // Derived sizes
    final torsoLen = (neck - Offset.lerp(lHip, rHip, 0.5)!).distance;
    final limbWidth = torsoLen * 0.14;
    final upperArmWidth = limbWidth * 0.92;
    final foreArmWidth = limbWidth * 0.78;
    final thighWidth = limbWidth * 1.1;
    final shinWidth = limbWidth * 0.92;
    final headRadius = torsoLen * 0.16;

    // ── Paint setup ──────────────────────────────────────────────────────
    final bodyPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // ── Draw order: back legs → torso → front legs → arms → head ────────
    // This layering ensures overlaps at joints look clean.

    // Legs (drawn first so torso overlaps hip joints)
    _drawCapsule(canvas, lHip, lKn, thighWidth, bodyPaint);
    _drawCapsule(canvas, lKn, lAnk, shinWidth, bodyPaint);
    _drawCapsule(canvas, rHip, rKn, thighWidth, bodyPaint);
    _drawCapsule(canvas, rKn, rAnk, shinWidth, bodyPaint);

    // Feet
    _drawFoot(canvas, lAnk, shinWidth * 0.7, bodyPaint);
    _drawFoot(canvas, rAnk, shinWidth * 0.7, bodyPaint);

    // Torso — a filled rounded shape from shoulders to hips
    _drawTorso(canvas, lSh, rSh, lHip, rHip, neck, bodyPaint);

    // Arms (drawn after torso so shoulder joints overlap)
    _drawCapsule(canvas, lSh, lEl, upperArmWidth, bodyPaint);
    _drawCapsule(canvas, lEl, lWr, foreArmWidth, bodyPaint);
    _drawCapsule(canvas, rSh, rEl, upperArmWidth, bodyPaint);
    _drawCapsule(canvas, rEl, rWr, foreArmWidth, bodyPaint);

    // Hands
    _drawCircle(canvas, lWr, foreArmWidth * 0.55, bodyPaint);
    _drawCircle(canvas, rWr, foreArmWidth * 0.55, bodyPaint);

    // Head — drawn last so neck overlap is hidden
    _drawCircle(canvas, head, headRadius, bodyPaint);

    // Chest "N" accent
    _drawChestAccent(
      canvas,
      Offset.lerp(neck, Offset.lerp(lHip, rHip, 0.5)!, 0.45)!,
      torsoLen * 0.08,
      accentColor,
    );
  }

  void _drawCapsule(
    Canvas canvas,
    Offset a,
    Offset b,
    double width,
    Paint paint,
  ) {
    canvas.drawLine(
      a,
      b,
      paint
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    // Ensure the paint is reset to fill for subsequent shapes
    paint.style = PaintingStyle.fill;
  }

  void _drawCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawCircle(center, radius, paint);
  }

  void _drawFoot(Canvas canvas, Offset ankle, double size, Paint paint) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: ankle, width: size * 1.8, height: size * 0.9),
      Radius.circular(size * 0.45),
    );
    canvas.drawRRect(rect, paint);
  }

  void _drawTorso(
    Canvas canvas,
    Offset lSh,
    Offset rSh,
    Offset lHip,
    Offset rHip,
    Offset neck,
    Paint paint,
  ) {
    final shoulderMid = Offset.lerp(lSh, rSh, 0.5)!;
    final hipMid = Offset.lerp(lHip, rHip, 0.5)!;
    final shoulderWidth = (lSh - rSh).distance;
    final torsoLen = (shoulderMid - hipMid).distance;

    // Build a rounded torso path: shoulders → outer hip → inner hip → neck
    final path = Path();
    // Start at left shoulder, go clockwise
    path.moveTo(lSh.dx, lSh.dy + torsoLen * 0.036);
    path.arcToPoint(
      rSh,
      radius: Radius.circular(torsoLen * 0.12),
      largeArc: false,
    );
    // Right side down to hip
    path.lineTo(rHip.dx + torsoLen * 0.024, rHip.dy - torsoLen * 0.012);
    path.arcToPoint(
      rHip,
      radius: Radius.circular(torsoLen * 0.072),
      largeArc: false,
    );
    // Bottom across to left hip
    path.lineTo(lHip.dx, lHip.dy);
    path.arcToPoint(
      Offset(lHip.dx - torsoLen * 0.024, lHip.dy - torsoLen * 0.012),
      radius: Radius.circular(torsoLen * 0.072),
      largeArc: false,
    );
    // Left side back up to shoulder
    path.close();

    canvas.drawPath(path, paint);

    // Also draw a filled rounded rect as a base for a cleaner torso
    final torsoRect = RRect.fromRectAndRadius(
      Rect.fromPoints(
        Offset(math.min(lSh.dx, lHip.dx) - shoulderWidth * 0.05, lSh.dy),
        Offset(math.max(rSh.dx, rHip.dx) + shoulderWidth * 0.05, lHip.dy),
      ),
      Radius.circular(shoulderWidth * 0.35),
    );
    canvas.drawRRect(torsoRect, paint);
  }

  void _drawChestAccent(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.28
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw a simple "N"
    final h = size * 1.2;
    final w = size * 0.8;
    final cx = center.dx;
    final cy = center.dy;

    canvas.drawLine(
      Offset(cx - w / 2, cy - h / 2),
      Offset(cx - w / 2, cy + h / 2),
      paint,
    );
    canvas.drawLine(
      Offset(cx - w / 2, cy - h / 2),
      Offset(cx + w / 2, cy + h / 2),
      paint,
    );
    canvas.drawLine(
      Offset(cx + w / 2, cy - h / 2),
      Offset(cx + w / 2, cy + h / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant NuvoCharacterPainter old) =>
      old.pose != pose ||
      old.bodyColor != bodyColor ||
      old.accentColor != accentColor;
}
