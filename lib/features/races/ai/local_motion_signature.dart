import 'dart:math';

import '../data/ai_motion_models.dart';

const kLocalMotionSignatureVersion = 'nuvo-local-motion-signature-v1';

const _trackedPoints = [
  'nose',
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
];

class LocalMotionSignature {
  const LocalMotionSignature({
    required this.version,
    required this.actionName,
    required this.startPoints,
    required this.endPoints,
    required this.activePointNames,
    required this.minCompleteness,
    required this.minProgressToCount,
    required this.resetProgress,
    this.rejectPoints = const {},
  });

  final String version;
  final String actionName;
  final Map<String, LocalMotionPoint> startPoints;
  final Map<String, LocalMotionPoint> endPoints;
  final Map<String, LocalMotionPoint> rejectPoints;
  final List<String> activePointNames;
  final double minCompleteness;
  final double minProgressToCount;
  final double resetProgress;

  factory LocalMotionSignature.fromFrames({
    required String actionName,
    required List<NuvoPoseFrame> cleanFrames,
    List<NuvoPoseFrame> rejectFrames = const [],
  }) {
    final usable = cleanFrames
        .where((frame) => frame.points.length >= 6)
        .toList(growable: false);
    if (usable.length < 4) {
      throw const LocalMotionSignatureException(
        'Nuvo needs a longer full-body clip.',
      );
    }

    final start = _averageWindow(usable.take(max(2, usable.length ~/ 4)));
    final end = _averageWindow(usable.skip(max(0, usable.length * 3 ~/ 4)));
    final active = _mostActivePoints(start, end);
    if (active.isEmpty) {
      throw const LocalMotionSignatureException(
        'Nuvo needs a clearer start and finish motion.',
      );
    }

    final rejectUsable = rejectFrames
        .where((frame) => frame.points.length >= 6)
        .toList(growable: false);
    final reject = rejectUsable.length < 2
        ? const <String, LocalMotionPoint>{}
        : _averageWindow(rejectUsable.skip(max(0, rejectUsable.length ~/ 2)));

    return LocalMotionSignature(
      version: kLocalMotionSignatureVersion,
      actionName: actionName,
      startPoints: start,
      endPoints: end,
      rejectPoints: reject,
      activePointNames: active,
      minCompleteness: 0.48,
      minProgressToCount: 0.82,
      resetProgress: 0.38,
    );
  }

  factory LocalMotionSignature.fromJson(Map<String, dynamic> json) {
    Map<String, LocalMotionPoint> readPoints(Object? value) {
      if (value is! Map<String, dynamic>) return const {};
      return value.map(
        (key, raw) => MapEntry(
          key,
          LocalMotionPoint.fromJson(raw as Map<String, dynamic>? ?? const {}),
        ),
      );
    }

    return LocalMotionSignature(
      version: json['version'] as String? ?? kLocalMotionSignatureVersion,
      actionName: json['actionName'] as String? ?? 'action',
      startPoints: readPoints(json['startPoints']),
      endPoints: readPoints(json['endPoints']),
      rejectPoints: readPoints(json['rejectPoints']),
      activePointNames:
          (json['activePointNames'] as List?)?.whereType<String>().toList() ??
          const [],
      minCompleteness:
          (json['minCompleteness'] as num?)?.toDouble().clamp(0, 1) ?? 0.48,
      minProgressToCount:
          (json['minProgressToCount'] as num?)?.toDouble().clamp(0, 1) ?? 0.82,
      resetProgress:
          (json['resetProgress'] as num?)?.toDouble().clamp(0, 1) ?? 0.38,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'actionName': actionName,
    'startPoints': startPoints.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'endPoints': endPoints.map((key, value) => MapEntry(key, value.toJson())),
    'rejectPoints': rejectPoints.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'activePointNames': activePointNames,
    'minCompleteness': minCompleteness,
    'minProgressToCount': minProgressToCount,
    'resetProgress': resetProgress,
  };

  LocalMotionMatch evaluate(NuvoPoseFrame frame) {
    final names = activePointNames.isEmpty
        ? startPoints.keys.where(endPoints.containsKey).toList()
        : activePointNames;
    var visible = 0;
    var progressTotal = 0.0;
    var confidenceTotal = 0.0;

    for (final name in names) {
      final point = frame.point(name);
      final start = startPoints[name];
      final end = endPoints[name];
      if (point == null ||
          start == null ||
          end == null ||
          point.likelihood < 0.35) {
        continue;
      }
      final dx = end.x - start.x;
      final dy = end.y - start.y;
      final lengthSq = dx * dx + dy * dy;
      if (lengthSq < 0.0008) continue;
      final px = point.x - start.x;
      final py = point.y - start.y;
      final projected = ((px * dx + py * dy) / lengthSq).clamp(0.0, 1.0);
      progressTotal += projected;
      confidenceTotal += point.likelihood;
      visible++;
    }

    final completeness = names.isEmpty ? 0.0 : visible / names.length;
    final progress = visible == 0 ? 0.0 : progressTotal / visible;
    final confidence = visible == 0
        ? 0.0
        : ((confidenceTotal / visible) * completeness).clamp(0.0, 1.0);
    final rejectSimilarity = _rejectSimilarity(frame);

    return LocalMotionMatch(
      progress: progress,
      confidence: confidence,
      completeness: completeness,
      rejectSimilarity: rejectSimilarity,
      visible: completeness >= minCompleteness,
    );
  }

  double _rejectSimilarity(NuvoPoseFrame frame) {
    if (rejectPoints.isEmpty) return 0;
    var compared = 0;
    var distance = 0.0;
    for (final entry in rejectPoints.entries) {
      final point = frame.point(entry.key);
      if (point == null || point.likelihood < 0.35) continue;
      compared++;
      distance += _distance(point.x, point.y, entry.value.x, entry.value.y);
    }
    if (compared == 0) return 0;
    return (1 - (distance / compared / 0.35)).clamp(0.0, 1.0);
  }

  static Map<String, LocalMotionPoint> _averageWindow(
    Iterable<NuvoPoseFrame> frames,
  ) {
    final sums = <String, ({double x, double y, int count})>{};
    for (final frame in frames) {
      for (final name in _trackedPoints) {
        final point = frame.point(name);
        if (point == null || point.likelihood < 0.4) continue;
        final current = sums[name];
        sums[name] = (
          x: (current?.x ?? 0) + point.x,
          y: (current?.y ?? 0) + point.y,
          count: (current?.count ?? 0) + 1,
        );
      }
    }
    return sums.map(
      (key, value) => MapEntry(
        key,
        LocalMotionPoint(x: value.x / value.count, y: value.y / value.count),
      ),
    );
  }

  static List<String> _mostActivePoints(
    Map<String, LocalMotionPoint> start,
    Map<String, LocalMotionPoint> end,
  ) {
    final distances = <({String name, double distance})>[];
    for (final entry in start.entries) {
      final endPoint = end[entry.key];
      if (endPoint == null) continue;
      final distance = _distance(
        endPoint.x,
        endPoint.y,
        entry.value.x,
        entry.value.y,
      );
      if (distance >= 0.035) {
        distances.add((name: entry.key, distance: distance));
      }
    }
    distances.sort((a, b) => b.distance.compareTo(a.distance));
    return distances.take(6).map((entry) => entry.name).toList();
  }

  static double _distance(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return sqrt(dx * dx + dy * dy);
  }
}

class LocalMotionPoint {
  const LocalMotionPoint({required this.x, required this.y});

  final double x;
  final double y;

  factory LocalMotionPoint.fromJson(Map<String, dynamic> json) =>
      LocalMotionPoint(
        x: (json['x'] as num?)?.toDouble().clamp(0, 1) ?? 0,
        y: (json['y'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class LocalMotionMatch {
  const LocalMotionMatch({
    required this.progress,
    required this.confidence,
    required this.completeness,
    required this.rejectSimilarity,
    required this.visible,
  });

  final double progress;
  final double confidence;
  final double completeness;
  final double rejectSimilarity;
  final bool visible;
}

class LocalMotionSignatureException implements Exception {
  const LocalMotionSignatureException(this.message);

  final String message;

  @override
  String toString() => message;
}
