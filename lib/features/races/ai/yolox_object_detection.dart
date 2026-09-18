import 'dart:math' as math;

import 'basketball_object_projector.dart';

/// Decodes the post-processed YOLOX detection tensor used by a local
/// basketball detector into Nuvo's model-neutral detection contract.
///
/// The decoder accepts numbers only. It never receives a [CameraImage], model
/// bytes, or a video frame. The tensor is expected to contain one decoded row
/// per candidate:
///
/// `[centerX, centerY, width, height, objectness, ...classScores]`
///
/// Coordinates are in the square model-input space. The supported release
/// uses top-left letterbox padding, so source coordinates are recovered by
/// removing the resize scale before normalizing them.
class YoloXBasketballObjectDecoder {
  const YoloXBasketballObjectDecoder({
    this.classLabels = defaultClassLabels,
    this.inputSize = 800,
    this.confidenceThreshold = 0.25,
    this.iouThreshold = 0.45,
  });

  /// Raw class order for the redistributable YOLOX basketball release.
  static const List<String> defaultClassLabels = <String>[
    'ball',
    'ball-in-basket',
    'number',
    'player',
    'player-in-possession',
    'player-jump-shot',
    'player-layup-dunk',
    'player-shot-block',
    'referee',
    'rim',
  ];

  final List<String> classLabels;
  final int inputSize;
  final double confidenceThreshold;
  final double iouThreshold;

  List<NuvoObjectDetection> decode({
    required List<double> output,
    required int candidateCount,
    required int attributesPerCandidate,
    required double sourceWidth,
    required double sourceHeight,
  }) {
    _requirePositive(sourceWidth, 'sourceWidth');
    _requirePositive(sourceHeight, 'sourceHeight');
    if (candidateCount <= 0 || attributesPerCandidate <= 5) {
      throw const FormatException('YOLOX output dimensions are invalid.');
    }
    if (attributesPerCandidate != classLabels.length + 5) {
      throw const FormatException('YOLOX class count does not match output.');
    }
    if (output.length != candidateCount * attributesPerCandidate) {
      throw const FormatException('YOLOX output length is invalid.');
    }

    final scale = math.min(inputSize / sourceWidth, inputSize / sourceHeight);
    final candidates = <_Candidate>[];
    for (var row = 0; row < candidateCount; row++) {
      final offset = row * attributesPerCandidate;
      final objectness = _probability(output[offset + 4]);
      if (objectness <= 0) continue;

      final centerX = output[offset];
      final centerY = output[offset + 1];
      final width = output[offset + 2];
      final height = output[offset + 3];
      if (![centerX, centerY, width, height].every(_isFinitePositiveBox)) {
        continue;
      }

      for (var classIndex = 0; classIndex < classLabels.length; classIndex++) {
        final label = classLabels[classIndex].trim();
        final kind = _kindFor(label);
        if (kind == null) continue;
        final confidence =
            objectness * _probability(output[offset + 5 + classIndex]);
        if (confidence < confidenceThreshold) continue;
        final detection = _detectionFromBox(
          label: label,
          confidence: confidence,
          centerX: centerX,
          centerY: centerY,
          width: width,
          height: height,
          scale: scale,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
        if (detection != null) {
          candidates.add(_Candidate(kind: kind, detection: detection));
        }
      }
    }

    candidates.sort(
      (a, b) => b.detection.confidence.compareTo(a.detection.confidence),
    );
    final kept = <_Candidate>[];
    for (final candidate in candidates) {
      if (kept.any(
        (existing) =>
            existing.kind == candidate.kind &&
            _iou(existing.detection, candidate.detection) > iouThreshold,
      )) {
        continue;
      }
      kept.add(candidate);
    }
    return [for (final candidate in kept) candidate.detection];
  }

  NuvoObjectDetection? _detectionFromBox({
    required String label,
    required double confidence,
    required double centerX,
    required double centerY,
    required double width,
    required double height,
    required double scale,
    required double sourceWidth,
    required double sourceHeight,
  }) {
    final left = ((centerX - width / 2) / scale / sourceWidth).clamp(0.0, 1.0);
    final top = ((centerY - height / 2) / scale / sourceHeight).clamp(0.0, 1.0);
    final right = ((centerX + width / 2) / scale / sourceWidth).clamp(0.0, 1.0);
    final bottom = ((centerY + height / 2) / scale / sourceHeight).clamp(
      0.0,
      1.0,
    );
    final detection = NuvoObjectDetection(
      label: label,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      confidence: confidence.clamp(0.0, 1.0),
    );
    return detection.isValid ? detection : null;
  }

  static double _probability(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0) : 0.0;

  static bool _isFinitePositiveBox(double value) => value.isFinite && value > 0;

  static void _requirePositive(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw FormatException('YOLOX $name is invalid.');
    }
  }

  static String? _kindFor(String label) {
    switch (label.toLowerCase()) {
      case 'ball':
      case 'basketball':
      case 'sports ball':
        return 'ball';
      case 'hoop':
      case 'rim':
      case 'basketball hoop':
      case 'basketball rim':
        return 'hoop';
      default:
        return null;
    }
  }

  static double _iou(NuvoObjectDetection a, NuvoObjectDetection b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final areaA = (a.right - a.left) * (a.bottom - a.top);
    final areaB = (b.right - b.left) * (b.bottom - b.top);
    final union = areaA + areaB - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}

class _Candidate {
  const _Candidate({required this.kind, required this.detection});

  final String kind;
  final NuvoObjectDetection detection;
}
