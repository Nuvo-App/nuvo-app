import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ai_motion_models.dart';

/// Keeps the last good pose on screen for a moment after a bad frame so the
/// skeleton does not strobe when detection briefly drops a landmark.
class SkeletonFrameHold {
  SkeletonFrameHold({required this.holdDuration});

  final Duration holdDuration;
  NuvoPoseFrame? _frame;
  DateTime? _lastVisibleAt;

  NuvoPoseFrame? get frame => _frame;
  DateTime? get lastVisibleAt => _lastVisibleAt;

  void show(NuvoPoseFrame frame, DateTime now) {
    _frame = frame;
    _lastVisibleAt = now;
  }

  bool expire(DateTime now) {
    final last = _lastVisibleAt;
    if (last == null) {
      final changed = _frame != null;
      clear();
      return changed;
    }
    if (now.difference(last) > holdDuration) {
      clear();
      return true;
    }
    return false;
  }

  void clear() {
    _frame = null;
    _lastVisibleAt = null;
  }
}

/// Maps normalized landmark coordinates onto a `BoxFit.cover` preview.
class PoseSkeletonCoordinateMapper {
  const PoseSkeletonCoordinateMapper._();

  static Offset map({
    required NuvoPosePoint point,
    required Size canvasSize,
    required Size sourceSize,
    required bool mirrorX,
  }) {
    if (canvasSize.isEmpty || sourceSize.isEmpty) return Offset.zero;
    final sourceAspect = sourceSize.width / sourceSize.height;
    final canvasAspect = canvasSize.width / canvasSize.height;
    final scale = canvasAspect > sourceAspect
        ? canvasSize.width / sourceSize.width
        : canvasSize.height / sourceSize.height;
    final fittedWidth = sourceSize.width * scale;
    final fittedHeight = sourceSize.height * scale;
    final cropX = (fittedWidth - canvasSize.width) / 2;
    final cropY = (fittedHeight - canvasSize.height) / 2;
    final normalizedX = mirrorX ? 1 - point.x : point.x;
    return Offset(
      normalizedX * sourceSize.width * scale - cropX,
      point.y * sourceSize.height * scale - cropY,
    );
  }
}

/// Decides whether landmarks need mirroring to line up with the preview.
class PoseSkeletonPreviewTransform {
  const PoseSkeletonPreviewTransform._();

  static bool shouldMirrorX({
    required CameraLensDirection? lensDirection,
    required TargetPlatform platform,
  }) {
    if (lensDirection != CameraLensDirection.front) return false;

    // iOS camera_avfoundation mirrors the front capture connection before the
    // frame reaches both CameraPreview and ML Kit. Mirroring here again swaps
    // the visible left/right sides of the skeleton.
    if (platform == TargetPlatform.iOS) return false;

    // Android CameraX mirrors front previews in Dart for the displayed texture,
    // while the image stream landmarks remain in camera-image coordinates.
    return platform == TargetPlatform.android;
  }
}

class Bone {
  const Bone(this.a, this.b);

  final String a;
  final String b;
}

const skeletonBones = <Bone>[
  Bone('leftShoulder', 'rightShoulder'),
  Bone('leftShoulder', 'leftElbow'),
  Bone('leftElbow', 'leftWrist'),
  Bone('rightShoulder', 'rightElbow'),
  Bone('rightElbow', 'rightWrist'),
  Bone('leftShoulder', 'leftHip'),
  Bone('rightShoulder', 'rightHip'),
  Bone('leftHip', 'rightHip'),
  Bone('leftHip', 'leftKnee'),
  Bone('leftKnee', 'leftAnkle'),
  Bone('rightHip', 'rightKnee'),
  Bone('rightKnee', 'rightAnkle'),
  Bone('leftWrist', 'leftThumb'),
  Bone('leftWrist', 'leftIndex'),
  Bone('leftWrist', 'leftPinky'),
  Bone('rightWrist', 'rightThumb'),
  Bone('rightWrist', 'rightIndex'),
  Bone('rightWrist', 'rightPinky'),
];

class PoseSkeletonPainter extends CustomPainter {
  PoseSkeletonPainter({
    this.frame,
    required this.sourceSize,
    required this.mirrorX,
    this.color = NuvoColors.white,
    this.glow = 0,
  });

  final NuvoPoseFrame? frame;
  final Size sourceSize;
  final bool mirrorX;

  /// Tint for joints and bones. Lets a screen signal state through the
  /// skeleton itself without drawing extra chrome.
  final Color color;

  /// 0..1 emphasis. Thickens and brightens the skeleton, used to pulse it the
  /// instant a rep is awarded.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final points = frame?.points;
    if (points == null || points.isEmpty) return;

    final emphasis = glow.clamp(0.0, 1.0);

    final jointPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final bonePaint = Paint()
      ..color = color.withValues(alpha: 0.55 + 0.45 * emphasis)
      ..strokeWidth = 2.5 + 2.5 * emphasis
      ..strokeCap = StrokeCap.round;

    Offset toOffset(NuvoPosePoint point) => PoseSkeletonCoordinateMapper.map(
      point: point,
      canvasSize: size,
      sourceSize: sourceSize,
      mirrorX: mirrorX,
    );

    for (final pair in skeletonBones) {
      final a = points[pair.a];
      final b = points[pair.b];
      if (a == null || b == null) continue;
      canvas.drawLine(toOffset(a), toOffset(b), bonePaint);
    }

    for (final entry in points.entries) {
      final point = entry.value;
      if (point.likelihood < 0.5) continue;
      canvas.drawCircle(toOffset(point), 4.5 + 1.5 * emphasis, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter old) =>
      old.frame != frame ||
      old.sourceSize != sourceSize ||
      old.mirrorX != mirrorX ||
      old.color != color ||
      old.glow != glow;
}

/// Draws the live pose skeleton over a camera preview.
class PoseSkeletonOverlay extends StatelessWidget {
  const PoseSkeletonOverlay({
    super.key,
    required this.frame,
    required this.sourceSize,
    required this.mirrorX,
    this.color = NuvoColors.white,
    this.glow = 0,
  });

  final NuvoPoseFrame? frame;
  final Size sourceSize;
  final bool mirrorX;
  final Color color;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: PoseSkeletonPainter(
          frame: frame,
          sourceSize: sourceSize,
          mirrorX: mirrorX,
          color: color,
          glow: glow,
        ),
      ),
    );
  }
}
