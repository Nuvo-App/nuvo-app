class VisionObservation {
  const VisionObservation({
    required this.observationId,
    required this.activityId,
    required this.activityDetected,
    required this.actionComplete,
    required this.confidence,
    required this.summary,
    this.raw,
  });

  final String observationId;
  final String activityId;
  final bool activityDetected;
  final bool actionComplete;
  final double confidence;
  final String summary;
  final String? raw;

  factory VisionObservation.fromJson(Map<String, dynamic> json) {
    return VisionObservation(
      observationId: json['observationId'] as String? ?? '',
      activityId: json['activityId'] as String? ?? '',
      activityDetected: json['activityDetected'] as bool? ?? false,
      actionComplete: json['actionComplete'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      summary: json['summary'] as String? ?? '',
      raw: json['raw'] as String?,
    );
  }
}
