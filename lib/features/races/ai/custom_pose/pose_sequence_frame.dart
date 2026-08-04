import 'normalized_pose.dart';

class PoseSequenceFrame {
  const PoseSequenceFrame({
    required this.schemaVersion,
    required this.position,
    required this.elapsedMs,
    required this.pose,
  });

  factory PoseSequenceFrame.fromJson(Map<String, dynamic> json) {
    if (json['version'] != normalizedPoseSchemaVersion) {
      throw PoseDataFormatException(
        'Unsupported sequence frame schema version: ${json['version']}.',
      );
    }
    final position = _finiteDouble(json['position'], 'position');
    if (position < 0 || position > 1) {
      throw const PoseDataFormatException(
        'Expected sequence frame position between 0 and 1.',
      );
    }
    final elapsedMs = json['elapsedMs'];
    if (elapsedMs is! int || elapsedMs < 0) {
      throw const PoseDataFormatException(
        'Expected non-negative integer elapsedMs.',
      );
    }
    final pose = json['pose'];
    if (pose is! Map) {
      throw const PoseDataFormatException('Expected object pose.');
    }
    return PoseSequenceFrame(
      schemaVersion: normalizedPoseSchemaVersion,
      position: position,
      elapsedMs: elapsedMs,
      pose: NormalizedPose.fromJson(pose.cast<String, dynamic>()),
    );
  }

  final int schemaVersion;
  final double position;
  final int elapsedMs;
  final NormalizedPose pose;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'position': _jsonDouble(position),
    'elapsedMs': elapsedMs,
    'pose': pose.toJson(),
  };
}

double _finiteDouble(Object? value, String field) {
  if (value is! num) {
    throw PoseDataFormatException('Expected numeric $field.');
  }
  final result = value.toDouble();
  if (!result.isFinite) {
    throw PoseDataFormatException('Expected finite numeric $field.');
  }
  return result;
}

double _jsonDouble(double value) {
  if (!value.isFinite) {
    throw const PoseDataFormatException('Cannot encode non-finite pose value.');
  }
  return value;
}
