import 'dart:convert';

import 'normalized_pose.dart';

const int customPoseVerifierSpecSchemaVersion = 1;
const String customPoseVerifierType = 'custom_pose_sequence';
const String customPoseMeasurementType = 'count';

enum CustomPoseCompletionStrategy {
  completionAtTerminalPose('completionAtTerminalPose'),
  completionAfterSequenceReturn('completionAfterSequenceReturn');

  const CustomPoseCompletionStrategy(this.jsonValue);

  factory CustomPoseCompletionStrategy.fromJson(String value) {
    for (final strategy in values) {
      if (strategy.jsonValue == value) return strategy;
    }
    throw PoseDataFormatException('Unknown completion strategy: $value.');
  }

  final String jsonValue;
}

class CustomPoseVerifierSpec {
  const CustomPoseVerifierSpec({
    required this.schemaVersion,
    required this.verifierType,
    required this.movementName,
    required this.measurementType,
    required this.startPose,
    required this.completionPose,
    required this.completionStrategy,
    required this.canonicalSequence,
    required this.requiredFeatureIds,
    required this.activeFeatureIds,
    required this.sequenceSimilarityThreshold,
    required this.completionSimilarityThreshold,
    required this.resetSimilarityThreshold,
    required this.minimumValidFeatureRatio,
    required this.minimumVisibility,
    required this.cooldownMs,
    required this.expectedSequenceFrameCount,
    required this.calibrationSummary,
  });

  factory CustomPoseVerifierSpec.fromJson(Map<String, dynamic> json) {
    final sequence = _list(json['canonicalSequence'], 'canonicalSequence')
        .map((value) => PoseTemplateFrame.fromJson(_map(value, 'frame')))
        .toList(growable: false);
    return CustomPoseVerifierSpec(
      schemaVersion: _int(json['version'], 'version'),
      verifierType: _string(json['verifierType'], 'verifierType'),
      movementName: _string(json['movementName'], 'movementName'),
      measurementType: _string(json['measurementType'], 'measurementType'),
      startPose: NormalizedPose.fromJson(_map(json['startPose'], 'startPose')),
      completionPose: NormalizedPose.fromJson(
        _map(json['completionPose'], 'completionPose'),
      ),
      completionStrategy: CustomPoseCompletionStrategy.fromJson(
        _string(json['completionStrategy'], 'completionStrategy'),
      ),
      canonicalSequence: sequence,
      requiredFeatureIds: _stringList(
        json['requiredFeatureIds'],
        'requiredFeatureIds',
      ),
      activeFeatureIds: _stringList(
        json['activeFeatureIds'],
        'activeFeatureIds',
      ),
      sequenceSimilarityThreshold: _ratio(
        json['sequenceSimilarityThreshold'],
        'sequenceSimilarityThreshold',
      ),
      completionSimilarityThreshold: _ratio(
        json['completionSimilarityThreshold'],
        'completionSimilarityThreshold',
      ),
      resetSimilarityThreshold: _ratio(
        json['resetSimilarityThreshold'],
        'resetSimilarityThreshold',
      ),
      minimumValidFeatureRatio: _ratio(
        json['minimumValidFeatureRatio'],
        'minimumValidFeatureRatio',
      ),
      minimumVisibility: _ratio(json['minimumVisibility'], 'minimumVisibility'),
      cooldownMs: _positiveInt(json['cooldownMs'], 'cooldownMs'),
      expectedSequenceFrameCount: _positiveInt(
        json['expectedSequenceFrameCount'],
        'expectedSequenceFrameCount',
      ),
      calibrationSummary: CustomPoseCalibrationSummary.fromJson(
        _map(json['calibrationSummary'], 'calibrationSummary'),
      ),
    )..validate();
  }

  final int schemaVersion;
  final String verifierType;
  final String movementName;
  final String measurementType;
  final NormalizedPose startPose;
  final NormalizedPose completionPose;
  final CustomPoseCompletionStrategy completionStrategy;
  final List<PoseTemplateFrame> canonicalSequence;
  final List<String> requiredFeatureIds;
  final List<String> activeFeatureIds;
  final double sequenceSimilarityThreshold;
  final double completionSimilarityThreshold;
  final double resetSimilarityThreshold;
  final double minimumValidFeatureRatio;
  final double minimumVisibility;
  final int cooldownMs;
  final int expectedSequenceFrameCount;
  final CustomPoseCalibrationSummary calibrationSummary;

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'verifierType': verifierType,
    'movementName': movementName,
    'measurementType': measurementType,
    'startPose': startPose.toJson(),
    'completionPose': completionPose.toJson(),
    'completionStrategy': completionStrategy.jsonValue,
    'canonicalSequence': canonicalSequence
        .map((frame) => frame.toJson())
        .toList(growable: false),
    'requiredFeatureIds': [...requiredFeatureIds]..sort(),
    'activeFeatureIds': [...activeFeatureIds]..sort(),
    'sequenceSimilarityThreshold': _jsonDouble(sequenceSimilarityThreshold),
    'completionSimilarityThreshold': _jsonDouble(completionSimilarityThreshold),
    'resetSimilarityThreshold': _jsonDouble(resetSimilarityThreshold),
    'minimumValidFeatureRatio': _jsonDouble(minimumValidFeatureRatio),
    'minimumVisibility': _jsonDouble(minimumVisibility),
    'cooldownMs': cooldownMs,
    'expectedSequenceFrameCount': expectedSequenceFrameCount,
    'calibrationSummary': calibrationSummary.toJson(),
  };

  String toDeterministicJson() => jsonEncode(toJson());

  void validate() => validateCustomPoseVerifierSpec(this);
}

class PoseTemplateFrame {
  const PoseTemplateFrame({required this.position, required this.features});

  factory PoseTemplateFrame.fromJson(Map<String, dynamic> json) {
    final featuresJson = _map(json['features'], 'features');
    return PoseTemplateFrame(
      position: _ratio(json['position'], 'position'),
      features: Map.unmodifiable(
        Map.fromEntries(
          featuresJson.entries.map(
            (entry) => MapEntry(
              entry.key,
              PoseTemplateFeature.fromJson(_map(entry.value, entry.key)),
            ),
          ),
        ),
      ),
    );
  }

  final double position;
  final Map<String, PoseTemplateFeature> features;

  Map<String, dynamic> toJson() => {
    'position': _jsonDouble(position),
    'features': Map.fromEntries(
      (features.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map(
        (entry) => MapEntry(entry.key, entry.value.toJson()),
      ),
    ),
  };
}

class PoseTemplateFeature {
  const PoseTemplateFeature({
    required this.value,
    required this.confidence,
    required this.reliability,
    required this.allowedVariation,
    required this.contributingDemonstrationCount,
    required this.kind,
  });

  factory PoseTemplateFeature.fromJson(Map<String, dynamic> json) {
    final kind = _string(json['kind'], 'kind');
    if (!poseFeatureKinds.contains(kind)) {
      throw PoseDataFormatException('Unknown template feature kind: $kind.');
    }
    return PoseTemplateFeature(
      value: _finiteDouble(json['value'], 'value'),
      confidence: _ratio(json['confidence'], 'confidence'),
      reliability: _ratio(json['reliability'], 'reliability'),
      allowedVariation: _nonNegativeFiniteDouble(
        json['allowedVariation'],
        'allowedVariation',
      ),
      contributingDemonstrationCount: _positiveInt(
        json['contributingDemonstrationCount'],
        'contributingDemonstrationCount',
      ),
      kind: kind,
    );
  }

  final double value;
  final double confidence;
  final double reliability;
  final double allowedVariation;
  final int contributingDemonstrationCount;
  final String kind;

  Map<String, dynamic> toJson() => {
    'value': _jsonDouble(value),
    'confidence': _jsonDouble(confidence),
    'reliability': _jsonDouble(reliability),
    'allowedVariation': _jsonDouble(allowedVariation),
    'contributingDemonstrationCount': contributingDemonstrationCount,
    'kind': kind,
  };
}

class CustomPoseCalibrationSummary {
  const CustomPoseCalibrationSummary({
    required this.sourceCalibrationSchemaVersion,
    required this.demonstrationCount,
    required this.selectedActiveFeatureCount,
    required this.requiredFeatureCount,
    required this.canonicalSequenceLength,
    required this.pairwiseSimilarityScores,
    required this.overallConsistencyScore,
    required this.lowestPairwiseSimilarityScore,
    required this.sequenceSimilarityThreshold,
    required this.completionSimilarityThreshold,
    required this.resetSimilarityThreshold,
    required this.minimumValidFeatureRatio,
    required this.minimumVisibility,
    required this.cooldownMs,
    required this.completionStrategy,
    required this.builderVersion,
  });

  factory CustomPoseCalibrationSummary.fromJson(Map<String, dynamic> json) {
    return CustomPoseCalibrationSummary(
      sourceCalibrationSchemaVersion: _int(
        json['sourceCalibrationSchemaVersion'],
        'sourceCalibrationSchemaVersion',
      ),
      demonstrationCount: _positiveInt(
        json['demonstrationCount'],
        'demonstrationCount',
      ),
      selectedActiveFeatureCount: _positiveInt(
        json['selectedActiveFeatureCount'],
        'selectedActiveFeatureCount',
      ),
      requiredFeatureCount: _positiveInt(
        json['requiredFeatureCount'],
        'requiredFeatureCount',
      ),
      canonicalSequenceLength: _positiveInt(
        json['canonicalSequenceLength'],
        'canonicalSequenceLength',
      ),
      pairwiseSimilarityScores: _stringDoubleMap(
        json['pairwiseSimilarityScores'],
        'pairwiseSimilarityScores',
      ),
      overallConsistencyScore: _ratio(
        json['overallConsistencyScore'],
        'overallConsistencyScore',
      ),
      lowestPairwiseSimilarityScore: _ratio(
        json['lowestPairwiseSimilarityScore'],
        'lowestPairwiseSimilarityScore',
      ),
      sequenceSimilarityThreshold: _ratio(
        json['sequenceSimilarityThreshold'],
        'sequenceSimilarityThreshold',
      ),
      completionSimilarityThreshold: _ratio(
        json['completionSimilarityThreshold'],
        'completionSimilarityThreshold',
      ),
      resetSimilarityThreshold: _ratio(
        json['resetSimilarityThreshold'],
        'resetSimilarityThreshold',
      ),
      minimumValidFeatureRatio: _ratio(
        json['minimumValidFeatureRatio'],
        'minimumValidFeatureRatio',
      ),
      minimumVisibility: _ratio(json['minimumVisibility'], 'minimumVisibility'),
      cooldownMs: _positiveInt(json['cooldownMs'], 'cooldownMs'),
      completionStrategy: CustomPoseCompletionStrategy.fromJson(
        _string(json['completionStrategy'], 'completionStrategy'),
      ),
      builderVersion: _string(json['builderVersion'], 'builderVersion'),
    );
  }

  final int sourceCalibrationSchemaVersion;
  final int demonstrationCount;
  final int selectedActiveFeatureCount;
  final int requiredFeatureCount;
  final int canonicalSequenceLength;
  final Map<String, double> pairwiseSimilarityScores;
  final double overallConsistencyScore;
  final double lowestPairwiseSimilarityScore;
  final double sequenceSimilarityThreshold;
  final double completionSimilarityThreshold;
  final double resetSimilarityThreshold;
  final double minimumValidFeatureRatio;
  final double minimumVisibility;
  final int cooldownMs;
  final CustomPoseCompletionStrategy completionStrategy;
  final String builderVersion;

  Map<String, dynamic> toJson() => {
    'sourceCalibrationSchemaVersion': sourceCalibrationSchemaVersion,
    'demonstrationCount': demonstrationCount,
    'selectedActiveFeatureCount': selectedActiveFeatureCount,
    'requiredFeatureCount': requiredFeatureCount,
    'canonicalSequenceLength': canonicalSequenceLength,
    'pairwiseSimilarityScores': Map.fromEntries(
      (pairwiseSimilarityScores.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .map((entry) => MapEntry(entry.key, _jsonDouble(entry.value))),
    ),
    'overallConsistencyScore': _jsonDouble(overallConsistencyScore),
    'lowestPairwiseSimilarityScore': _jsonDouble(lowestPairwiseSimilarityScore),
    'sequenceSimilarityThreshold': _jsonDouble(sequenceSimilarityThreshold),
    'completionSimilarityThreshold': _jsonDouble(completionSimilarityThreshold),
    'resetSimilarityThreshold': _jsonDouble(resetSimilarityThreshold),
    'minimumValidFeatureRatio': _jsonDouble(minimumValidFeatureRatio),
    'minimumVisibility': _jsonDouble(minimumVisibility),
    'cooldownMs': cooldownMs,
    'completionStrategy': completionStrategy.jsonValue,
    'builderVersion': builderVersion,
  };
}

void validateCustomPoseVerifierSpec(CustomPoseVerifierSpec spec) {
  if (spec.schemaVersion != customPoseVerifierSpecSchemaVersion) {
    throw PoseDataFormatException(
      'Unsupported custom pose verifier schema version: ${spec.schemaVersion}.',
    );
  }
  if (spec.verifierType != customPoseVerifierType) {
    throw PoseDataFormatException(
      'Unsupported verifier type: ${spec.verifierType}.',
    );
  }
  if (spec.measurementType != customPoseMeasurementType) {
    throw PoseDataFormatException(
      'Unsupported measurement type: ${spec.measurementType}.',
    );
  }
  if (spec.movementName.trim().isEmpty) {
    throw const PoseDataFormatException('Movement name is required.');
  }
  if (!spec.startPose.isValid) {
    throw const PoseDataFormatException('Start pose must be valid.');
  }
  if (!spec.completionPose.isValid) {
    throw const PoseDataFormatException('Completion pose must be valid.');
  }
  if (spec.canonicalSequence.isEmpty) {
    throw const PoseDataFormatException('Canonical sequence is required.');
  }
  if (spec.expectedSequenceFrameCount != spec.canonicalSequence.length) {
    throw const PoseDataFormatException(
      'Expected sequence frame count does not match canonical sequence.',
    );
  }
  _rejectDuplicates(spec.activeFeatureIds, 'activeFeatureIds');
  _rejectDuplicates(spec.requiredFeatureIds, 'requiredFeatureIds');
  if (spec.activeFeatureIds.isEmpty) {
    throw const PoseDataFormatException(
      'At least one active feature is required.',
    );
  }
  for (final id in [...spec.activeFeatureIds, ...spec.requiredFeatureIds]) {
    if (!isKnownPoseFeatureId(id)) {
      throw PoseDataFormatException('Unknown pose feature id: $id.');
    }
  }
  final activeSet = spec.activeFeatureIds.toSet();
  for (final id in spec.requiredFeatureIds) {
    if (!activeSet.contains(id)) {
      throw PoseDataFormatException('Required feature is not active: $id.');
    }
  }
  var previous = -1.0;
  for (final frame in spec.canonicalSequence) {
    if (frame.position < 0 ||
        frame.position > 1 ||
        frame.position <= previous) {
      throw const PoseDataFormatException(
        'Canonical sequence positions must be strictly increasing.',
      );
    }
    previous = frame.position;
    for (final id in frame.features.keys) {
      if (!activeSet.contains(id)) {
        throw PoseDataFormatException(
          'Template frame contains inactive feature: $id.',
        );
      }
      if (!isKnownPoseFeatureId(id)) {
        throw PoseDataFormatException('Unknown pose feature id: $id.');
      }
    }
  }
  if (spec.canonicalSequence.first.position != 0 ||
      spec.canonicalSequence.last.position != 1) {
    throw const PoseDataFormatException(
      'Canonical sequence must include positions 0 and 1.',
    );
  }
  for (final threshold in [
    spec.sequenceSimilarityThreshold,
    spec.completionSimilarityThreshold,
    spec.resetSimilarityThreshold,
    spec.minimumValidFeatureRatio,
    spec.minimumVisibility,
  ]) {
    if (!threshold.isFinite || threshold < 0 || threshold > 1) {
      throw const PoseDataFormatException('Verifier thresholds must be 0..1.');
    }
  }
  if (spec.cooldownMs <= 0) {
    throw const PoseDataFormatException('Cooldown must be positive.');
  }
  if (spec.calibrationSummary.demonstrationCount < 2 ||
      spec.calibrationSummary.selectedActiveFeatureCount !=
          spec.activeFeatureIds.length ||
      spec.calibrationSummary.requiredFeatureCount !=
          spec.requiredFeatureIds.length ||
      spec.calibrationSummary.canonicalSequenceLength !=
          spec.canonicalSequence.length) {
    throw const PoseDataFormatException('Calibration summary is inconsistent.');
  }
}

bool isKnownPoseFeatureId(String id) {
  final landmark = RegExp(r'^landmark\.([A-Za-z]+)\.[xy]$').firstMatch(id);
  if (landmark != null) {
    return canonicalPoseLandmarkIds.contains(landmark.group(1));
  }
  const angleIds = {
    'angle.left_elbow',
    'angle.right_elbow',
    'angle.left_shoulder',
    'angle.right_shoulder',
    'angle.left_hip',
    'angle.right_hip',
    'angle.left_knee',
    'angle.right_knee',
  };
  const distanceIds = {
    'distance.hand_separation',
    'distance.foot_separation',
    'distance.left_wrist_to_shoulder',
    'distance.right_wrist_to_shoulder',
    'distance.left_wrist_to_hip',
    'distance.right_wrist_to_hip',
    'distance.left_knee_to_hip',
    'distance.right_knee_to_hip',
  };
  return angleIds.contains(id) || distanceIds.contains(id);
}

void _rejectDuplicates(List<String> values, String field) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw PoseDataFormatException('Duplicate $field value: $value.');
    }
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

List<String> _stringList(Object? value, String field) {
  return _list(
    value,
    field,
  ).map((item) => _string(item, field)).toList(growable: false);
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

int _positiveInt(Object? value, String field) {
  final result = _int(value, field);
  if (result <= 0) {
    throw PoseDataFormatException('Expected positive integer $field.');
  }
  return result;
}

double _finiteDouble(Object? value, String field) {
  if (value is! num) throw PoseDataFormatException('Expected numeric $field.');
  final result = value.toDouble();
  if (!result.isFinite) {
    throw PoseDataFormatException('Expected finite numeric $field.');
  }
  return result;
}

double _nonNegativeFiniteDouble(Object? value, String field) {
  final result = _finiteDouble(value, field);
  if (result < 0) {
    throw PoseDataFormatException('Expected non-negative numeric $field.');
  }
  return result;
}

double _ratio(Object? value, String field) {
  final result = _finiteDouble(value, field);
  if (result < 0 || result > 1) {
    throw PoseDataFormatException('Expected ratio $field.');
  }
  return result;
}

Map<String, double> _stringDoubleMap(Object? value, String field) {
  final map = _map(value, field);
  return Map.unmodifiable(
    map.map((key, value) => MapEntry(key, _ratio(value, '$field.$key'))),
  );
}

double _jsonDouble(double value) {
  if (!value.isFinite) {
    throw const PoseDataFormatException(
      'Cannot encode non-finite verifier value.',
    );
  }
  return value;
}
