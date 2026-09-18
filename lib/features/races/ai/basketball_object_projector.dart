import '../data/ai_motion_models.dart';
import 'object_motion_models.dart';

/// One normalized detection returned by a local object model.
///
/// This is deliberately model-neutral: an ONNX, ML Kit, or future detector
/// can feed the same projector. Only the normalized center/scale leaves this
/// layer; model tensors and camera pixels do not.
class NuvoObjectDetection {
  const NuvoObjectDetection({
    required this.label,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
  });

  final String label;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;

  bool get isValid =>
      label.trim().isNotEmpty &&
      confidence.isFinite &&
      confidence >= 0 &&
      confidence <= 1 &&
      [left, top, right, bottom].every((value) => value.isFinite) &&
      left >= 0 &&
      top >= 0 &&
      right <= 1 &&
      bottom <= 1 &&
      right > left &&
      bottom > top;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get scale =>
      ((right - left).clamp(0.0, 1.0) + (bottom - top).clamp(0.0, 1.0)) / 2;
}

/// Converts detector boxes into the stable ball/hoop dot IDs used by the
/// basketball composition release.
class BasketballObjectProjector {
  const BasketballObjectProjector();

  NuvoObjectMotionFrame project({
    required NuvoPoseFrame pose,
    required DateTime createdAt,
    required Iterable<NuvoObjectDetection> detections,
  }) {
    final best = <String, NuvoObjectDetection>{};
    for (final detection in detections) {
      if (!detection.isValid) continue;
      final kind = _kindFor(detection.label);
      if (kind == null ||
          (best[kind]?.confidence ?? -1) >= detection.confidence) {
        continue;
      }
      best[kind] = detection;
    }
    return NuvoObjectMotionFrame(
      pose: pose,
      createdAt: createdAt,
      objects: {
        for (final entry in best.entries)
          entry.key: NuvoObjectDot(
            id: entry.key,
            kind: entry.key,
            x: entry.value.centerX,
            y: entry.value.centerY,
            likelihood: entry.value.confidence,
            scale: entry.value.scale,
          ),
      },
    );
  }

  String? _kindFor(String label) {
    final normalized = label.trim().toLowerCase();
    if ({'ball', 'basketball', 'sports ball'}.contains(normalized)) {
      return 'ball';
    }
    if ({
      'hoop',
      'rim',
      'basketball hoop',
      'basketball rim',
    }.contains(normalized)) {
      return 'hoop';
    }
    return null;
  }
}
