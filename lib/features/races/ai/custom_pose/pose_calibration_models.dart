import 'normalized_pose.dart';
import 'pose_sequence_frame.dart';

const int poseCalibrationSchemaVersion = 1;

class CustomPoseCalibration {
  const CustomPoseCalibration({
    required this.schemaVersion,
    required this.movementName,
    required this.startPose,
    required this.demonstrations,
    required this.quality,
    required this.metadata,
  });

  factory CustomPoseCalibration.fromJson(Map<String, dynamic> json) {
    _requireVersion(json['version']);
    final demonstrationsJson = _list(json['demonstrations'], 'demonstrations');
    return CustomPoseCalibration(
      schemaVersion: poseCalibrationSchemaVersion,
      movementName: _string(json['movementName'], 'movementName'),
      startPose: NormalizedPose.fromJson(_map(json['startPose'], 'startPose')),
      demonstrations: demonstrationsJson
          .map(
            (value) => PoseDemonstration.fromJson(_map(value, 'demonstration')),
          )
          .toList(growable: false),
      quality: CalibrationQuality.fromJson(_map(json['quality'], 'quality')),
      metadata: CalibrationCaptureMetadata.fromJson(
        _map(json['metadata'], 'metadata'),
      ),
    );
  }

  final int schemaVersion;
  final String movementName;
  final NormalizedPose startPose;
  final List<PoseDemonstration> demonstrations;
  final CalibrationQuality quality;
  final CalibrationCaptureMetadata metadata;

  bool get isReady => quality.readyForBuilder;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'movementName': movementName,
    'startPose': startPose.toJson(),
    'demonstrations': demonstrations.map((demo) => demo.toJson()).toList(),
    'quality': quality.toJson(),
    'metadata': metadata.toJson(),
  };
}

class PoseDemonstration {
  const PoseDemonstration({
    required this.index,
    required this.frames,
    required this.durationMs,
    required this.processedFrameCount,
    required this.validFrameCount,
    required this.validFrameRatio,
    required this.averageVisibility,
    required this.accepted,
    this.rejectionReason,
  });

  factory PoseDemonstration.fromJson(Map<String, dynamic> json) {
    final framesJson = _list(json['frames'], 'frames');
    final accepted = _bool(json['accepted'], 'accepted');
    final rejectionReason = json['rejectionReason'] == null
        ? null
        : _string(json['rejectionReason'], 'rejectionReason');
    if (!accepted && rejectionReason == null) {
      throw const PoseDataFormatException(
        'Rejected demonstration must include rejectionReason.',
      );
    }
    return PoseDemonstration(
      index: _int(json['index'], 'index'),
      frames: framesJson
          .map((value) => PoseSequenceFrame.fromJson(_map(value, 'frame')))
          .toList(growable: false),
      durationMs: _int(json['durationMs'], 'durationMs'),
      processedFrameCount: _int(
        json['processedFrameCount'],
        'processedFrameCount',
      ),
      validFrameCount: _int(json['validFrameCount'], 'validFrameCount'),
      validFrameRatio: _ratio(json['validFrameRatio'], 'validFrameRatio'),
      averageVisibility: _ratio(json['averageVisibility'], 'averageVisibility'),
      accepted: accepted,
      rejectionReason: rejectionReason,
    );
  }

  final int index;
  final List<PoseSequenceFrame> frames;
  final int durationMs;
  final int processedFrameCount;
  final int validFrameCount;
  final double validFrameRatio;
  final double averageVisibility;
  final bool accepted;
  final String? rejectionReason;

  Map<String, dynamic> toJson() => {
    'index': index,
    'frames': frames.map((frame) => frame.toJson()).toList(),
    'durationMs': durationMs,
    'processedFrameCount': processedFrameCount,
    'validFrameCount': validFrameCount,
    'validFrameRatio': _jsonDouble(validFrameRatio),
    'averageVisibility': _jsonDouble(averageVisibility),
    'accepted': accepted,
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
  };
}

class CalibrationQuality {
  const CalibrationQuality({
    required this.startPoseValid,
    required this.startPoseStability,
    required this.startPoseCoverage,
    required this.demonstrationCount,
    required this.averageValidFrameRatio,
    required this.averagePoseCoverage,
    required this.interrupted,
    required this.readyForBuilder,
    required this.reasons,
  });

  factory CalibrationQuality.fromJson(Map<String, dynamic> json) {
    return CalibrationQuality(
      startPoseValid: _bool(json['startPoseValid'], 'startPoseValid'),
      startPoseStability: _ratio(
        json['startPoseStability'],
        'startPoseStability',
      ),
      startPoseCoverage: _ratio(json['startPoseCoverage'], 'startPoseCoverage'),
      demonstrationCount: _int(
        json['demonstrationCount'],
        'demonstrationCount',
      ),
      averageValidFrameRatio: _ratio(
        json['averageValidFrameRatio'],
        'averageValidFrameRatio',
      ),
      averagePoseCoverage: _ratio(
        json['averagePoseCoverage'],
        'averagePoseCoverage',
      ),
      interrupted: _bool(json['interrupted'], 'interrupted'),
      readyForBuilder: _bool(json['readyForBuilder'], 'readyForBuilder'),
      reasons: _list(
        json['reasons'],
        'reasons',
      ).map((value) => _string(value, 'reason')).toList(growable: false),
    );
  }

  final bool startPoseValid;
  final double startPoseStability;
  final double startPoseCoverage;
  final int demonstrationCount;
  final double averageValidFrameRatio;
  final double averagePoseCoverage;
  final bool interrupted;
  final bool readyForBuilder;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {
    'startPoseValid': startPoseValid,
    'startPoseStability': _jsonDouble(startPoseStability),
    'startPoseCoverage': _jsonDouble(startPoseCoverage),
    'demonstrationCount': demonstrationCount,
    'averageValidFrameRatio': _jsonDouble(averageValidFrameRatio),
    'averagePoseCoverage': _jsonDouble(averagePoseCoverage),
    'interrupted': interrupted,
    'readyForBuilder': readyForBuilder,
    'reasons': reasons,
  };
}

class CalibrationCaptureMetadata {
  const CalibrationCaptureMetadata({
    required this.capturedAtIso8601,
    required this.cameraLensDirection,
    required this.orientation,
    required this.normalizerVersion,
    required this.deviceNote,
  });

  factory CalibrationCaptureMetadata.fromJson(Map<String, dynamic> json) {
    return CalibrationCaptureMetadata(
      capturedAtIso8601: _string(
        json['capturedAtIso8601'],
        'capturedAtIso8601',
      ),
      cameraLensDirection: _string(
        json['cameraLensDirection'],
        'cameraLensDirection',
      ),
      orientation: _string(json['orientation'], 'orientation'),
      normalizerVersion: _string(
        json['normalizerVersion'],
        'normalizerVersion',
      ),
      deviceNote: _string(json['deviceNote'], 'deviceNote'),
    );
  }

  final String capturedAtIso8601;
  final String cameraLensDirection;
  final String orientation;
  final String normalizerVersion;
  final String deviceNote;

  Map<String, dynamic> toJson() => {
    'capturedAtIso8601': capturedAtIso8601,
    'cameraLensDirection': cameraLensDirection,
    'orientation': orientation,
    'normalizerVersion': normalizerVersion,
    'deviceNote': deviceNote,
  };
}

String? validateMovementName(String value, {int maxLength = 40}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Name the movement first.';
  if (trimmed.length > maxLength) return 'Use $maxLength characters or fewer.';
  return null;
}

void _requireVersion(Object? value) {
  if (value != poseCalibrationSchemaVersion) {
    throw PoseDataFormatException(
      'Unsupported calibration schema version: $value.',
    );
  }
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map) throw PoseDataFormatException('Expected object $field.');
  return value.cast<String, dynamic>();
}

List<dynamic> _list(Object? value, String field) {
  if (value is! List) throw PoseDataFormatException('Expected list $field.');
  return value;
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw PoseDataFormatException('Expected non-empty string $field.');
  }
  return value;
}

int _int(Object? value, String field) {
  if (value is! int || value < 0) {
    throw PoseDataFormatException('Expected non-negative integer $field.');
  }
  return value;
}

bool _bool(Object? value, String field) {
  if (value is! bool) throw PoseDataFormatException('Expected boolean $field.');
  return value;
}

double _ratio(Object? value, String field) {
  if (value is! num) throw PoseDataFormatException('Expected numeric $field.');
  final result = value.toDouble();
  if (!result.isFinite || result < 0 || result > 1) {
    throw PoseDataFormatException('Expected finite ratio $field.');
  }
  return result;
}

double _jsonDouble(double value) {
  if (!value.isFinite) {
    throw const PoseDataFormatException('Cannot encode non-finite value.');
  }
  return value;
}
