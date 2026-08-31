import 'dart:math' as math;

import 'normalized_pose.dart';
import 'pose_calibration_models.dart';

class PoseAverager {
  const PoseAverager({this.minPoseCount = 2, this.minSharedRatio = 0.70});

  final int minPoseCount;
  final double minSharedRatio;

  NormalizedPose average(List<NormalizedPose> poses) {
    final validPoses = poses.where((pose) => pose.isValid).toList();
    if (validPoses.length < minPoseCount) {
      throw const PoseDataFormatException('Not enough valid poses to average.');
    }
    final requiredCount = math.max(
      1,
      (validPoses.length * minSharedRatio).ceil(),
    );
    final landmarkIds = <String>{
      for (final pose in validPoses) ...pose.landmarks.keys,
    };
    final averagedLandmarks = <String, NormalizedPoseLandmark>{};
    for (final id in landmarkIds.toList()..sort()) {
      final values = validPoses
          .map((pose) => pose.landmarks[id])
          .whereType<NormalizedPoseLandmark>()
          .where((landmark) => landmark.valid)
          .toList();
      if (values.length < requiredCount) continue;
      averagedLandmarks[id] = NormalizedPoseLandmark(
        x: _average(values.map((value) => value.x)),
        y: _average(values.map((value) => value.y)),
        z: _average(values.map((value) => value.z)),
        confidence: _average(values.map((value) => value.confidence)),
        valid: true,
      );
    }

    final featureIds = <String>{
      for (final pose in validPoses) ...pose.features.values.keys,
    };
    final averagedFeatures = <String, PoseFeatureValue>{};
    for (final id in featureIds.toList()..sort()) {
      final values = validPoses
          .map((pose) => pose.features.values[id])
          .whereType<PoseFeatureValue>()
          .where((feature) => feature.valid)
          .toList();
      if (values.length < requiredCount) continue;
      final kind = values.first.kind;
      if (values.any((value) => value.kind != kind)) continue;
      averagedFeatures[id] = PoseFeatureValue(
        value: _average(values.map((value) => value.value)),
        confidence: _average(values.map((value) => value.confidence)),
        valid: true,
        kind: kind,
      );
    }
    if (averagedFeatures.isEmpty) {
      throw const PoseDataFormatException(
        'No shared pose features to average.',
      );
    }
    return NormalizedPose(
      schemaVersion: normalizedPoseSchemaVersion,
      landmarks: Map.unmodifiable(averagedLandmarks),
      features: PoseFeatureVector(Map.unmodifiable(averagedFeatures)),
      originX: _average(validPoses.map((pose) => pose.originX)),
      originY: _average(validPoses.map((pose) => pose.originY)),
      scale: _average(validPoses.map((pose) => pose.scale)),
      originReference: validPoses.first.originReference,
      scaleReference: validPoses.first.scaleReference,
      validLandmarkCount: averagedLandmarks.length,
      validFeatureCount: averagedFeatures.length,
    );
  }

  double _average(Iterable<double> values) {
    final list = values.toList(growable: false);
    final total = list.fold<double>(0, (sum, value) => sum + value);
    final result = total / list.length;
    if (!result.isFinite) {
      throw const PoseDataFormatException(
        'Averaged pose produced non-finite value.',
      );
    }
    return result;
  }
}

CalibrationQuality evaluateCalibrationQuality({
  required NormalizedPose? startPose,
  required double startPoseStability,
  required List<PoseDemonstration> demonstrations,
  bool interrupted = false,
  int requiredDemonstrations = 3,
}) {
  final reasons = <String>[];
  final accepted = demonstrations.where((demo) => demo.accepted).toList();
  final startValid = startPose?.isValid == true;
  if (!startValid) reasons.add('start_pose_invalid');
  if (accepted.length != requiredDemonstrations) {
    reasons.add('requires_three_demonstrations');
  }
  for (final demo in demonstrations) {
    if (!demo.accepted) {
      reasons.add('demo_${demo.index}_${demo.rejectionReason ?? 'rejected'}');
    }
  }
  if (interrupted) reasons.add('capture_interrupted');
  final avgRatio = accepted.isEmpty
      ? 0.0
      : accepted.map((demo) => demo.validFrameRatio).reduce((a, b) => a + b) /
            accepted.length;
  final avgCoverage = accepted.isEmpty
      ? 0.0
      : accepted.map((demo) => demo.averageVisibility).reduce((a, b) => a + b) /
            accepted.length;
  final startCoverage = startPose == null
      ? 0.0
      : (startPose.validFeatureCount /
                math.max(1, startPose.features.values.length))
            .clamp(0.0, 1.0);
  final ready = reasons.isEmpty;
  return CalibrationQuality(
    startPoseValid: startValid,
    startPoseStability: startPoseStability.clamp(0.0, 1.0),
    startPoseCoverage: startCoverage,
    demonstrationCount: accepted.length,
    averageValidFrameRatio: avgRatio.clamp(0.0, 1.0),
    averagePoseCoverage: avgCoverage.clamp(0.0, 1.0),
    interrupted: interrupted,
    readyForBuilder: ready,
    reasons: List.unmodifiable(reasons),
  );
}
