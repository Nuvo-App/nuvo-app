import 'ai_motion_models.dart';

/// Shared wire contract for phone capture, server inference, and future
/// portable models. Keep this versioned: stored results must remain readable
/// after the model changes.
const motionAnalysisSchemaVersion = 1;

class MotionAnalysisRequest {
  const MotionAnalysisRequest({
    required this.motionId,
    required this.frames,
    this.targetReps,
    this.durationMs,
  });

  final String motionId;
  final List<NuvoPoseFrame> frames;
  final int? targetReps;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
    'schemaVersion': motionAnalysisSchemaVersion,
    'motionId': motionId,
    if (targetReps != null) 'targetReps': targetReps,
    if (durationMs != null) 'durationMs': durationMs,
    'frames': frames.map((frame) => frame.toJson()).toList(),
  };
}

class MotionEvidence {
  const MotionEvidence({
    required this.key,
    required this.label,
    required this.status,
    this.value,
    this.expected,
  });

  factory MotionEvidence.fromJson(Map<String, dynamic> json) => MotionEvidence(
    key: json['key'] as String? ?? 'unknown',
    label: json['label'] as String? ?? 'Evidence',
    status: json['status'] as String? ?? 'unknown',
    value: (json['value'] as num?)?.toDouble(),
    expected: (json['expected'] as num?)?.toDouble(),
  );

  final String key;
  final String label;
  final String status;
  final double? value;
  final double? expected;
}

class MotionAnalysisResult {
  const MotionAnalysisResult({
    required this.motionId,
    required this.verdict,
    required this.detectedReps,
    required this.confidence,
    required this.uncertainty,
    required this.evidence,
    required this.failureReasons,
    required this.coaching,
    required this.modelVersion,
    required this.validatorVersion,
    required this.framesAnalyzed,
    required this.validPoseFrames,
    required this.durationMs,
  });

  factory MotionAnalysisResult.fromJson(Map<String, dynamic> json) =>
      MotionAnalysisResult(
        motionId: json['motionId'] as String? ?? 'unknown',
        verdict: json['verdict'] as String? ?? 'needs_review',
        detectedReps: (json['detectedReps'] as num?)?.toInt() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        uncertainty: (json['uncertainty'] as num?)?.toDouble() ?? 1,
        evidence: (json['evidence'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MotionEvidence.fromJson)
            .toList(growable: false),
        failureReasons: (json['failureReasons'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        coaching: (json['coaching'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        modelVersion: json['modelVersion'] as String? ?? 'unknown',
        validatorVersion: json['validatorVersion'] as String? ?? 'unknown',
        framesAnalyzed: (json['framesAnalyzed'] as num?)?.toInt() ?? 0,
        validPoseFrames: (json['validPoseFrames'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      );

  final String motionId;
  final String verdict;
  final int detectedReps;
  final double confidence;
  final double uncertainty;
  final List<MotionEvidence> evidence;
  final List<String> failureReasons;
  final List<String> coaching;
  final String modelVersion;
  final String validatorVersion;
  final int framesAnalyzed;
  final int validPoseFrames;
  final int durationMs;

  bool get isValid => verdict == 'valid';
}

extension NuvoPoseFrameWireFormat on NuvoPoseFrame {
  Map<String, dynamic> toJson() => {
    'timestampMs': createdAt.millisecondsSinceEpoch,
    'quality': points.isEmpty
        ? 0
        : points.values.map((p) => p.likelihood).reduce((a, b) => a + b) /
              points.length,
    'landmarks': points.map(
      (name, point) => MapEntry(name, {
        'x': point.x,
        'y': point.y,
        'z': point.z,
        'confidence': point.likelihood,
      }),
    ),
  };
}
