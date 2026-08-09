import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_geometry.dart';
import '../../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../../ai/custom_pose/normalized_pose.dart';
import 'pose_skeleton_overlay.dart';

/// Loops a simple skeleton animation showing the movement Nuvo learned.
///
/// Uses [CustomPoseVerifierSpec.startPose] as the stable base skeleton and
/// overlays only the canonical `landmark.<name>.x/y` feature values from
/// [CustomPoseVerifierSpec.canonicalSequence]. Angle and distance features are
/// ignored — they remain part of verification but do not affect this preview.
class LearnedMovementPreview extends StatefulWidget {
  const LearnedMovementPreview({super.key, required this.spec});

  final CustomPoseVerifierSpec spec;

  @override
  State<LearnedMovementPreview> createState() => _LearnedMovementPreviewState();
}

class _LearnedMovementPreviewState extends State<LearnedMovementPreview> {
  static const Duration _frameDuration = Duration(milliseconds: 100);
  static const double _paddingFraction = 0.15;
  static const double _previewHeight = 320;

  Timer? _timer;
  int _frameIndex = 0;
  late final List<PreviewFrame> _frames;
  late final PreviewBounds _bounds;

  @override
  void initState() {
    super.initState();
    _frames = buildLearnedMovementFrames(widget.spec);
    _bounds = computeLearnedMovementBounds(widget.spec.startPose, _frames);
    if (_frames.length > 1) {
      _timer = Timer.periodic(_frameDuration, _onTick);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _onTick(Timer timer) {
    if (!mounted) return;
    setState(() {
      _frameIndex = (_frameIndex + 1) % _frames.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frames.isEmpty
        ? const PreviewFrame.empty()
        : _frames[_frameIndex];
    return Container(
      height: _previewHeight,
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
      ),
      child: CustomPaint(
        painter: _LearnedMovementPainter(
          frame: frame,
          bounds: _bounds,
          paddingFraction: _paddingFraction,
        ),
      ),
    );
  }
}

@visibleForTesting
class PreviewFrame {
  const PreviewFrame({required this.landmarks});

  const PreviewFrame.empty() : landmarks = const {};

  /// Landmark name -> (x, y) in normalized body coordinates.
  final Map<String, PreviewPoint> landmarks;
}

@visibleForTesting
class PreviewPoint {
  const PreviewPoint(this.x, this.y);

  final double x;
  final double y;
}

@visibleForTesting
class PreviewBounds {
  const PreviewBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
}

@visibleForTesting
List<PreviewFrame> buildLearnedMovementFrames(CustomPoseVerifierSpec spec) {
  final startPose = spec.startPose;
  final baseLandmarks = <String, PreviewPoint>{};
  for (final entry in startPose.landmarks.entries) {
    final landmark = entry.value;
    if (!landmark.valid) continue;
    baseLandmarks[entry.key] = PreviewPoint(landmark.x, landmark.y);
  }

  final frames = <PreviewFrame>[];
  for (final templateFrame in spec.canonicalSequence) {
    final frameLandmarks = Map<String, PreviewPoint>.from(baseLandmarks);
    for (final entry in templateFrame.features.entries) {
      final id = entry.key;
      final feature = entry.value;
      final parsed = parseLandmarkFeatureId(id);
      if (parsed == null) continue;
      final existing = frameLandmarks[parsed.landmarkName];
      final baseX = existing?.x ?? baseLandmarks[parsed.landmarkName]?.x;
      final baseY = existing?.y ?? baseLandmarks[parsed.landmarkName]?.y;
      final x = parsed.isX ? feature.value : baseX;
      final y = parsed.isX ? baseY : feature.value;
      if (x == null || y == null) continue;
      frameLandmarks[parsed.landmarkName] = PreviewPoint(x, y);
    }
    frames.add(PreviewFrame(landmarks: frameLandmarks));
  }
  return frames;
}

@visibleForTesting
LandmarkFeatureId? parseLandmarkFeatureId(String id) {
  if (!id.startsWith('landmark.')) return null;
  final parts = id.split('.');
  if (parts.length != 3) return null;
  final axis = parts[2];
  if (axis != 'x' && axis != 'y') return null;
  return LandmarkFeatureId(landmarkName: parts[1], isX: axis == 'x');
}

@visibleForTesting
class LandmarkFeatureId {
  const LandmarkFeatureId({required this.landmarkName, required this.isX});

  final String landmarkName;
  final bool isX;
}

@visibleForTesting
PreviewBounds computeLearnedMovementBounds(
  NormalizedPose startPose,
  List<PreviewFrame> frames,
) {
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  void consider(PreviewPoint point) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }

  for (final landmark in startPose.landmarks.values) {
    if (!landmark.valid) continue;
    consider(PreviewPoint(landmark.x, landmark.y));
  }
  for (final frame in frames) {
    for (final point in frame.landmarks.values) {
      consider(point);
    }
  }
  if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
    return const PreviewBounds(minX: 0, maxX: 1, minY: 0, maxY: 1);
  }
  return PreviewBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

class _LearnedMovementPainter extends CustomPainter {
  const _LearnedMovementPainter({
    required this.frame,
    required this.bounds,
    required this.paddingFraction,
  });

  final PreviewFrame frame;
  final PreviewBounds bounds;
  final double paddingFraction;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final boundsWidth = bounds.width == 0 ? 1.0 : bounds.width;
    final boundsHeight = bounds.height == 0 ? 1.0 : bounds.height;
    final padding = paddingFraction * math.min(boundsWidth, boundsHeight);
    final paddedWidth = boundsWidth + padding * 2;
    final paddedHeight = boundsHeight + padding * 2;
    final scale = math.min(
      size.width / paddedWidth,
      size.height / paddedHeight,
    );
    final offsetX =
        (size.width - paddedWidth * scale) / 2 -
        (bounds.minX - padding) * scale;
    final offsetY =
        (size.height - paddedHeight * scale) / 2 -
        (bounds.minY - padding) * scale;

    Offset toOffset(PreviewPoint point) {
      return Offset(point.x * scale + offsetX, point.y * scale + offsetY);
    }

    final jointPaint = Paint()
      ..color = NuvoColors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final bonePaint = Paint()
      ..color = NuvoColors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final landmarks = frame.landmarks;
    for (final bone in skeletonBones) {
      final a = landmarks[bone.a];
      final b = landmarks[bone.b];
      if (a == null || b == null) continue;
      canvas.drawLine(toOffset(a), toOffset(b), bonePaint);
    }
    for (final point in landmarks.values) {
      canvas.drawCircle(toOffset(point), 4.5, jointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LearnedMovementPainter old) =>
      old.frame != frame || old.bounds != bounds;
}
