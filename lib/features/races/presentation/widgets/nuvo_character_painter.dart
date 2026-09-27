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

/// Visual treatment for the reusable movement guide.
///
/// Solid is used for the expressive Nuvo character. Line art is reserved for
/// instructional previews, where a neutral figure is easier to read than a
/// face and a filled silhouette.
enum NuvoCharacterStyle { solid, lineArt }

/// Paints a neutral movement preview from a [NuvoCharacterPose].
///
/// The character is built from filled rounded body segments — capsules for
/// limbs, a rounded torso shape, and a circular head — so it reads as one
/// continuous movement guide. It intentionally contains no face or brand mark
/// so it reads as an instruction, not a person watching the user.
class NuvoCharacterPainter extends CustomPainter {
  NuvoCharacterPainter({
    required this.pose,
    this.bodyColor = const Color(0xFF07152D),
    this.accentColor = const Color(0xFF1264FF),
    this.style = NuvoCharacterStyle.solid,
    this.outlineColor = Colors.white,
    this.outlineWidth = 0,
    this.backgroundRadius = 0,
  });

  final NuvoCharacterPose pose;

  /// Main body fill colour.
  final Color bodyColor;

  /// Accent colour for the chest "N" and optional highlights.
  final Color accentColor;

  /// Whether this is an expressive character or a neutral instruction figure.
  final NuvoCharacterStyle style;

  /// Outline colour for the character silhouette.
  final Color outlineColor;

  /// Outline stroke width. 0 means no outline.
  final double outlineWidth;

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

    if (style == NuvoCharacterStyle.lineArt) {
      _paintLineArt(
        canvas,
        head: head,
        neck: neck,
        leftShoulder: lSh,
        rightShoulder: rSh,
        leftElbow: lEl,
        rightElbow: rEl,
        leftWrist: lWr,
        rightWrist: rWr,
        leftHip: lHip,
        rightHip: rHip,
        leftKnee: lKn,
        rightKnee: rKn,
        leftAnkle: lAnk,
        rightAnkle: rAnk,
        size: size,
      );
      return;
    }

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

    final outlinePaint = outlineWidth > 0
        ? (Paint()
            ..color = outlineColor
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true)
        : null;

    // ── Draw order: back legs → torso → front legs → arms → head ────────
    // Each shape is drawn with an outline stroke first so the figure pops.

    // Legs (drawn first so torso overlaps hip joints)
    _drawCapsule(canvas, lHip, lKn, thighWidth, bodyPaint, outlinePaint);
    _drawCapsule(canvas, lKn, lAnk, shinWidth, bodyPaint, outlinePaint);
    _drawCapsule(canvas, rHip, rKn, thighWidth, bodyPaint, outlinePaint);
    _drawCapsule(canvas, rKn, rAnk, shinWidth, bodyPaint, outlinePaint);

    // Feet
    _drawFoot(canvas, lAnk, shinWidth * 0.7, bodyPaint, outlinePaint);
    _drawFoot(canvas, rAnk, shinWidth * 0.7, bodyPaint, outlinePaint);

    // Torso
    _drawTorso(canvas, lSh, rSh, lHip, rHip, neck, bodyPaint, outlinePaint);

    // Arms
    _drawCapsule(canvas, lSh, lEl, upperArmWidth, bodyPaint, outlinePaint);
    _drawCapsule(canvas, lEl, lWr, foreArmWidth, bodyPaint, outlinePaint);
    _drawCapsule(canvas, rSh, rEl, upperArmWidth, bodyPaint, outlinePaint);
    _drawCapsule(canvas, rEl, rWr, foreArmWidth, bodyPaint, outlinePaint);

    // Hands
    _drawCircle(canvas, lWr, foreArmWidth * 0.55, bodyPaint, outlinePaint);
    _drawCircle(canvas, rWr, foreArmWidth * 0.55, bodyPaint, outlinePaint);

    // Head — drawn last so neck overlap is hidden.
    _drawCircle(canvas, head, headRadius, bodyPaint, outlinePaint);
  }

  void _paintLineArt(
    Canvas canvas, {
    required Offset head,
    required Offset neck,
    required Offset leftShoulder,
    required Offset rightShoulder,
    required Offset leftElbow,
    required Offset rightElbow,
    required Offset leftWrist,
    required Offset rightWrist,
    required Offset leftHip,
    required Offset rightHip,
    required Offset leftKnee,
    required Offset rightKnee,
    required Offset leftAnkle,
    required Offset rightAnkle,
    required Size size,
  }) {
    final stroke = (size.shortestSide * 0.028).clamp(2.0, 3.5);
    final paint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    void segment(Offset a, Offset b) => canvas.drawLine(a, b, paint);

    // A simple neutral figure keeps the movement readable without a face,
    // heavy body fills, or decorative marks that can feel uncanny in a setup
    // instruction.
    final shoulderMid = Offset.lerp(leftShoulder, rightShoulder, 0.5)!;
    final hipMid = Offset.lerp(leftHip, rightHip, 0.5)!;
    segment(neck, shoulderMid);
    segment(shoulderMid, hipMid);
    segment(leftShoulder, rightShoulder);
    segment(leftHip, rightHip);

    segment(leftShoulder, leftElbow);
    segment(leftElbow, leftWrist);
    segment(rightShoulder, rightElbow);
    segment(rightElbow, rightWrist);
    segment(leftHip, leftKnee);
    segment(leftKnee, leftAnkle);
    segment(rightHip, rightKnee);
    segment(rightKnee, rightAnkle);

    final headRadius = (size.shortestSide * 0.065).clamp(5.0, 8.0);
    canvas.drawCircle(head, headRadius, paint);
  }

  void _drawCapsule(
    Canvas canvas,
    Offset a,
    Offset b,
    double width,
    Paint paint,
    Paint? outlinePaint,
  ) {
    if (outlinePaint != null) {
      canvas.drawLine(a, b, outlinePaint..strokeWidth = width + outlineWidth);
    }
    canvas.drawLine(
      a,
      b,
      paint
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    paint.style = PaintingStyle.fill;
    if (outlinePaint != null) outlinePaint.style = PaintingStyle.stroke;
  }

  void _drawCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
    Paint? outlinePaint,
  ) {
    if (outlinePaint != null) {
      canvas.drawCircle(center, radius + outlineWidth * 0.5, outlinePaint);
    }
    canvas.drawCircle(center, radius, paint);
  }

  void _drawFoot(
    Canvas canvas,
    Offset ankle,
    double size,
    Paint paint,
    Paint? outlinePaint,
  ) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: ankle, width: size * 1.8, height: size * 0.9),
      Radius.circular(size * 0.45),
    );
    if (outlinePaint != null) {
      final outlineRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: ankle,
          width: size * 1.8 + outlineWidth,
          height: size * 0.9 + outlineWidth,
        ),
        Radius.circular(size * 0.45 + outlineWidth * 0.5),
      );
      canvas.drawRRect(outlineRect, outlinePaint..style = PaintingStyle.fill);
      outlinePaint.style = PaintingStyle.stroke;
    }
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
    Paint? outlinePaint,
  ) {
    final shoulderMid = Offset.lerp(lSh, rSh, 0.5)!;
    final hipMid = Offset.lerp(lHip, rHip, 0.5)!;
    final shoulderWidth = (lSh - rSh).distance;
    final torsoLen = (shoulderMid - hipMid).distance;

    final torsoRect = RRect.fromRectAndRadius(
      Rect.fromPoints(
        Offset(math.min(lSh.dx, lHip.dx) - shoulderWidth * 0.05, lSh.dy),
        Offset(math.max(rSh.dx, rHip.dx) + shoulderWidth * 0.05, lHip.dy),
      ),
      Radius.circular(shoulderWidth * 0.35),
    );

    if (outlinePaint != null) {
      final outlineRect = RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(
            math.min(lSh.dx, lHip.dx) -
                shoulderWidth * 0.05 -
                outlineWidth * 0.5,
            lSh.dy - outlineWidth * 0.5,
          ),
          Offset(
            math.max(rSh.dx, rHip.dx) +
                shoulderWidth * 0.05 +
                outlineWidth * 0.5,
            lHip.dy + outlineWidth * 0.5,
          ),
        ),
        Radius.circular(shoulderWidth * 0.35 + outlineWidth * 0.5),
      );
      canvas.drawRRect(outlineRect, outlinePaint..style = PaintingStyle.fill);
      outlinePaint.style = PaintingStyle.stroke;
    }
    canvas.drawRRect(torsoRect, paint);

    // Rounded shoulder cap
    final path = Path();
    path.moveTo(lSh.dx, lSh.dy + torsoLen * 0.036);
    path.arcToPoint(
      rSh,
      radius: Radius.circular(torsoLen * 0.12),
      largeArc: false,
    );
    path.lineTo(rHip.dx + torsoLen * 0.024, rHip.dy - torsoLen * 0.012);
    path.arcToPoint(
      rHip,
      radius: Radius.circular(torsoLen * 0.072),
      largeArc: false,
    );
    path.lineTo(lHip.dx, lHip.dy);
    path.arcToPoint(
      Offset(lHip.dx - torsoLen * 0.024, lHip.dy - torsoLen * 0.012),
      radius: Radius.circular(torsoLen * 0.072),
      largeArc: false,
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant NuvoCharacterPainter old) =>
      old.pose != pose ||
      old.bodyColor != bodyColor ||
      old.accentColor != accentColor ||
      old.style != style ||
      old.outlineColor != outlineColor ||
      old.outlineWidth != outlineWidth;
}
