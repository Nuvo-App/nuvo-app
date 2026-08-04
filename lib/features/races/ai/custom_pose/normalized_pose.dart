import 'dart:math' as math;

const int normalizedPoseSchemaVersion = 1;

const canonicalPoseLandmarkIds = <String>{
  'nose',
  'leftEyeInner',
  'leftEye',
  'leftEyeOuter',
  'rightEyeInner',
  'rightEye',
  'rightEyeOuter',
  'leftEar',
  'rightEar',
  'leftMouth',
  'rightMouth',
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftPinky',
  'rightPinky',
  'leftIndex',
  'rightIndex',
  'leftThumb',
  'rightThumb',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
  'leftHeel',
  'rightHeel',
  'leftFootIndex',
  'rightFootIndex',
};

const poseFeatureKinds = <String>{'coord', 'angle', 'distance'};

class PoseDataFormatException implements Exception {
  const PoseDataFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NormalizedPose {
  const NormalizedPose({
    required this.schemaVersion,
    required this.landmarks,
    required this.features,
    required this.originX,
    required this.originY,
    required this.scale,
    required this.originReference,
    required this.scaleReference,
    required this.validLandmarkCount,
    required this.validFeatureCount,
    this.invalidReason,
  });

  factory NormalizedPose.fromJson(Map<String, dynamic> json) {
    _requireVersion(json['version']);
    final landmarksJson = _expectMap(json['landmarks'], 'landmarks');
    final features = PoseFeatureVector.fromJson(
      _expectMap(json['features'], 'features'),
    );
    final landmarks = <String, NormalizedPoseLandmark>{};
    for (final entry in landmarksJson.entries) {
      final id = entry.key;
      _checkLandmarkId(id);
      landmarks[id] = NormalizedPoseLandmark.fromJson(
        _expectMap(entry.value, 'landmarks.$id'),
      );
    }
    return NormalizedPose(
      schemaVersion: normalizedPoseSchemaVersion,
      landmarks: Map.unmodifiable(landmarks),
      features: features,
      originX: _finiteDouble(json['originX'], 'originX'),
      originY: _finiteDouble(json['originY'], 'originY'),
      scale: _positiveFiniteDouble(json['scale'], 'scale'),
      originReference: _string(json['originReference'], 'originReference'),
      scaleReference: _string(json['scaleReference'], 'scaleReference'),
      validLandmarkCount: _int(
        json['validLandmarkCount'],
        'validLandmarkCount',
      ),
      validFeatureCount: _int(json['validFeatureCount'], 'validFeatureCount'),
      invalidReason: json['invalidReason'] == null
          ? null
          : _string(json['invalidReason'], 'invalidReason'),
    );
  }

  final int schemaVersion;
  final Map<String, NormalizedPoseLandmark> landmarks;
  final PoseFeatureVector features;
  final double originX;
  final double originY;
  final double scale;
  final String originReference;
  final String scaleReference;
  final int validLandmarkCount;
  final int validFeatureCount;
  final String? invalidReason;

  bool get isValid => invalidReason == null;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'originX': _jsonDouble(originX),
    'originY': _jsonDouble(originY),
    'scale': _jsonDouble(scale),
    'originReference': originReference,
    'scaleReference': scaleReference,
    'validLandmarkCount': validLandmarkCount,
    'validFeatureCount': validFeatureCount,
    if (invalidReason != null) 'invalidReason': invalidReason,
    'landmarks': Map.fromEntries(
      landmarks.entries.map(
        (entry) => MapEntry(entry.key, entry.value.toJson()),
      ),
    ),
    'features': features.toJson(),
  };
}

class NormalizedPoseLandmark {
  const NormalizedPoseLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
    required this.valid,
  });

  factory NormalizedPoseLandmark.fromJson(Map<String, dynamic> json) =>
      NormalizedPoseLandmark(
        x: _finiteDouble(json['x'], 'x'),
        y: _finiteDouble(json['y'], 'y'),
        z: _finiteDouble(json['z'], 'z'),
        confidence: _confidence(json['confidence'], 'confidence'),
        valid: _bool(json['valid'], 'valid'),
      );

  final double x;
  final double y;
  final double z;
  final double confidence;
  final bool valid;

  Map<String, dynamic> toJson() => {
    'x': _jsonDouble(x),
    'y': _jsonDouble(y),
    'z': _jsonDouble(z),
    'confidence': _jsonDouble(confidence),
    'valid': valid,
  };
}

class PoseFeatureVector {
  const PoseFeatureVector(this.values);

  factory PoseFeatureVector.fromJson(Map<String, dynamic> json) {
    _requireVersion(json['version']);
    final valuesJson = _expectMap(json['values'], 'values');
    return PoseFeatureVector(
      Map.unmodifiable(
        valuesJson.map(
          (key, value) => MapEntry(
            key,
            PoseFeatureValue.fromJson(_expectMap(value, 'values.$key')),
          ),
        ),
      ),
    );
  }

  final Map<String, PoseFeatureValue> values;

  int get validCount => values.values.where((value) => value.valid).length;

  Map<String, dynamic> toJson() => {
    'version': normalizedPoseSchemaVersion,
    'values': Map.fromEntries(
      values.entries.map((entry) => MapEntry(entry.key, entry.value.toJson())),
    ),
  };
}

class PoseFeatureValue {
  const PoseFeatureValue({
    required this.value,
    required this.confidence,
    required this.valid,
    required this.kind,
  });

  factory PoseFeatureValue.fromJson(Map<String, dynamic> json) {
    final kind = _string(json['kind'], 'kind');
    if (!poseFeatureKinds.contains(kind)) {
      throw PoseDataFormatException('Unknown pose feature kind: $kind.');
    }
    return PoseFeatureValue(
      value: _finiteDouble(json['value'], 'value'),
      confidence: _confidence(json['confidence'], 'confidence'),
      valid: _bool(json['valid'], 'valid'),
      kind: kind,
    );
  }

  final double value;
  final double confidence;
  final bool valid;
  final String kind;

  Map<String, dynamic> toJson() => {
    'value': _jsonDouble(value),
    'confidence': _jsonDouble(confidence),
    'valid': valid,
    'kind': kind,
  };
}

void _requireVersion(Object? value) {
  if (value != normalizedPoseSchemaVersion) {
    throw PoseDataFormatException('Unsupported pose schema version: $value.');
  }
}

void _checkLandmarkId(String id) {
  if (!canonicalPoseLandmarkIds.contains(id)) {
    throw PoseDataFormatException('Unknown pose landmark id: $id.');
  }
}

Map<String, dynamic> _expectMap(Object? value, String field) {
  if (value is! Map) {
    throw PoseDataFormatException('Expected object for $field.');
  }
  return value.cast<String, dynamic>();
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

double _positiveFiniteDouble(Object? value, String field) {
  final result = _finiteDouble(value, field);
  if (result <= 0) {
    throw PoseDataFormatException('Expected positive numeric $field.');
  }
  return result;
}

double _confidence(Object? value, String field) {
  final result = _finiteDouble(value, field);
  if (result < 0 || result > 1) {
    throw PoseDataFormatException('Expected $field between 0 and 1.');
  }
  return result;
}

bool _bool(Object? value, String field) {
  if (value is! bool) throw PoseDataFormatException('Expected boolean $field.');
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) throw PoseDataFormatException('Expected integer $field.');
  return value;
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw PoseDataFormatException('Expected non-empty string $field.');
  }
  return value;
}

double _jsonDouble(double value) {
  if (!value.isFinite) {
    throw const PoseDataFormatException('Cannot encode non-finite pose value.');
  }
  return value;
}

double distance2d(double ax, double ay, double bx, double by) {
  final dx = ax - bx;
  final dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}
