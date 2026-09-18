import '../data/ai_motion_models.dart';

enum RemoteEngineType { stateMachineV1, alternatingRepV1, holdV1 }

enum RemoteAxis { x, y }

enum RemoteOperator {
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
}

class RemoteVerifierSpecException implements Exception {
  const RemoteVerifierSpecException(this.message);

  final String message;

  @override
  String toString() => 'RemoteVerifierSpecException: $message';
}

class RemotePoseRule {
  const RemotePoseRule({
    required this.point,
    required this.axis,
    required this.operator,
    required this.threshold,
    this.minLikelihood = 0.35,
  });

  final String point;
  final RemoteAxis axis;
  final RemoteOperator operator;
  final double threshold;
  final double minLikelihood;

  bool matches(NuvoPoseFrame frame) {
    final pose = frame.point(point);
    if (pose == null || pose.likelihood < minLikelihood) return false;
    final value = axis == RemoteAxis.x ? pose.x : pose.y;
    return switch (operator) {
      RemoteOperator.greaterThan => value > threshold,
      RemoteOperator.greaterThanOrEqual => value >= threshold,
      RemoteOperator.lessThan => value < threshold,
      RemoteOperator.lessThanOrEqual => value <= threshold,
    };
  }
}

class RemoteVerifierSpec {
  const RemoteVerifierSpec({
    required this.releaseId,
    required this.activityId,
    required this.engine,
    required this.schemaVersion,
    required this.requiredLandmarks,
    required this.stableFrames,
    required this.startRules,
    required this.activeRules,
    required this.leftRules,
    required this.rightRules,
    required this.holdRules,
    this.minHoldMs = 250,
    this.maxHoldMs = 60 * 60 * 1000,
  });

  final String releaseId;
  final String activityId;
  final RemoteEngineType engine;
  final int schemaVersion;
  final List<String> requiredLandmarks;
  final int stableFrames;
  final List<RemotePoseRule> startRules;
  final List<RemotePoseRule> activeRules;
  final List<RemotePoseRule> leftRules;
  final List<RemotePoseRule> rightRules;
  final List<RemotePoseRule> holdRules;
  final int minHoldMs;
  final int maxHoldMs;

  factory RemoteVerifierSpec.fromJson(Map<String, dynamic> json) {
    const allowedKeys = {
      'specSchemaVersion',
      'releaseId',
      'activityId',
      'engineType',
      'measurementType',
      'requiredCapabilities',
      'requiredLandmarks',
      'stableFrames',
      'startRules',
      'activeRules',
      'leftRules',
      'rightRules',
      'holdRules',
      'minHoldMs',
      'maxHoldMs',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const RemoteVerifierSpecException('Unknown verifier spec field.');
    }
    final schemaVersion = _int(json['specSchemaVersion'], 'specSchemaVersion');
    if (schemaVersion != 1) {
      throw RemoteVerifierSpecException('Unsupported verifier spec schema.');
    }
    final releaseId = _string(json['releaseId'], 'releaseId');
    final activityId = _string(json['activityId'], 'activityId');
    final engineRaw = _string(json['engineType'], 'engineType');
    final engine = switch (engineRaw) {
      'state_machine_v1' => RemoteEngineType.stateMachineV1,
      'alternating_rep_v1' => RemoteEngineType.alternatingRepV1,
      'hold_v1' => RemoteEngineType.holdV1,
      _ => throw RemoteVerifierSpecException('Unknown verifier engine.'),
    };
    final measurementType = _string(
      json['measurementType'] ?? 'repetitions',
      'measurementType',
    );
    if (measurementType != 'repetitions' && measurementType != 'duration') {
      throw const RemoteVerifierSpecException('Unsupported measurement type.');
    }
    final capabilities = json['requiredCapabilities'];
    if (capabilities != null) {
      if (capabilities is! List ||
          capabilities.length > 16 ||
          capabilities.any(
            (entry) => entry is! String || entry.trim().isEmpty,
          )) {
        throw const RemoteVerifierSpecException(
          'Invalid required capabilities.',
        );
      }
    }
    final requiredLandmarks = _strings(
      json['requiredLandmarks'],
      'requiredLandmarks',
      max: 24,
    );
    final stableFrames = _boundedInt(
      json['stableFrames'],
      'stableFrames',
      1,
      12,
      fallback: 3,
    );
    final startRules = _rules(json['startRules'], 'startRules');
    final activeRules = _rules(json['activeRules'], 'activeRules');
    final leftRules = _rules(json['leftRules'], 'leftRules');
    final rightRules = _rules(json['rightRules'], 'rightRules');
    final holdRules = _rules(json['holdRules'], 'holdRules');
    final minHoldMs = _boundedInt(
      json['minHoldMs'],
      'minHoldMs',
      50,
      60 * 60 * 1000,
      fallback: 250,
    );
    final maxHoldMs = _boundedInt(
      json['maxHoldMs'],
      'maxHoldMs',
      minHoldMs,
      60 * 60 * 1000,
      fallback: 60 * 60 * 1000,
    );

    if (requiredLandmarks.isEmpty)
      throw RemoteVerifierSpecException('requiredLandmarks cannot be empty.');
    if (engine == RemoteEngineType.stateMachineV1 &&
        (startRules.isEmpty || activeRules.isEmpty)) {
      throw RemoteVerifierSpecException(
        'state_machine_v1 requires startRules and activeRules.',
      );
    }
    if (engine == RemoteEngineType.alternatingRepV1 &&
        (leftRules.isEmpty || rightRules.isEmpty)) {
      throw RemoteVerifierSpecException(
        'alternating_rep_v1 requires leftRules and rightRules.',
      );
    }
    if (engine == RemoteEngineType.holdV1 && holdRules.isEmpty) {
      throw RemoteVerifierSpecException('hold_v1 requires holdRules.');
    }
    return RemoteVerifierSpec(
      releaseId: releaseId,
      activityId: activityId,
      engine: engine,
      schemaVersion: schemaVersion,
      requiredLandmarks: requiredLandmarks,
      stableFrames: stableFrames,
      startRules: startRules,
      activeRules: activeRules,
      leftRules: leftRules,
      rightRules: rightRules,
      holdRules: holdRules,
      minHoldMs: minHoldMs,
      maxHoldMs: maxHoldMs,
    );
  }

  static String _string(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty && value.length <= 160)
      return value.trim();
    throw RemoteVerifierSpecException('$field must be a bounded string.');
  }

  static int _int(Object? value, String field) {
    if (value is num && value.isFinite && value == value.roundToDouble())
      return value.toInt();
    throw RemoteVerifierSpecException('$field must be an integer.');
  }

  static int _boundedInt(
    Object? value,
    String field,
    int min,
    int max, {
    required int fallback,
  }) {
    if (value == null) return fallback;
    final parsed = _int(value, field);
    if (parsed < min || parsed > max)
      throw RemoteVerifierSpecException(
        '$field is outside the supported range.',
      );
    return parsed;
  }

  static List<String> _strings(
    Object? value,
    String field, {
    required int max,
  }) {
    if (value is! List || value.length > max)
      throw RemoteVerifierSpecException('$field must be a bounded list.');
    final values = value.map((entry) => _string(entry, field)).toSet().toList();
    const allowed = {
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
      'nose',
    };
    if (values.any((entry) => !allowed.contains(entry))) {
      throw RemoteVerifierSpecException(
        '$field contains an unsupported pose landmark.',
      );
    }
    return values;
  }

  static List<RemotePoseRule> _rules(Object? value, String field) {
    if (value == null) return const [];
    if (value is! List || value.length > 12)
      throw RemoteVerifierSpecException('$field must be a bounded rule list.');
    return value.map((entry) {
      if (entry is! Map<String, dynamic>)
        throw RemoteVerifierSpecException('$field contains an invalid rule.');
      final point = _strings([entry['point']], 'point', max: 1).single;
      final axis = switch (_string(entry['axis'], 'axis')) {
        'x' => RemoteAxis.x,
        'y' => RemoteAxis.y,
        _ => throw RemoteVerifierSpecException('axis must be x or y.'),
      };
      final operator = switch (_string(entry['operator'], 'operator')) {
        'gt' => RemoteOperator.greaterThan,
        'gte' => RemoteOperator.greaterThanOrEqual,
        'lt' => RemoteOperator.lessThan,
        'lte' => RemoteOperator.lessThanOrEqual,
        _ => throw RemoteVerifierSpecException('Unknown pose rule operator.'),
      };
      final threshold = entry['threshold'];
      final likelihood = entry['minLikelihood'];
      if (threshold is! num ||
          !threshold.isFinite ||
          threshold < 0 ||
          threshold > 1) {
        throw RemoteVerifierSpecException(
          'Pose rule threshold is outside 0..1.',
        );
      }
      if (likelihood != null &&
          (likelihood is! num ||
              !likelihood.isFinite ||
              likelihood < 0.2 ||
              likelihood > 1)) {
        throw RemoteVerifierSpecException('minLikelihood is outside 0.2..1.');
      }
      return RemotePoseRule(
        point: point,
        axis: axis,
        operator: operator,
        threshold: threshold.toDouble(),
        minLikelihood: likelihood is num ? likelihood.toDouble() : 0.35,
      );
    }).toList();
  }
}
