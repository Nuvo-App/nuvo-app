class ObjectCompositionSpecException implements Exception {
  const ObjectCompositionSpecException(this.message);

  final String message;

  @override
  String toString() => 'ObjectCompositionSpecException: $message';
}

class ObjectCompositionSpec {
  const ObjectCompositionSpec({
    required this.releaseId,
    required this.activityId,
    required this.schemaVersion,
    required this.requiredLandmarks,
    required this.requiredObjects,
    required this.states,
    required this.transitions,
    required this.ballObjectId,
    required this.hoopObjectId,
    required this.stableFrames,
    required this.maxShotMs,
    required this.controlDistance,
    required this.releaseDistance,
    required this.minUpwardVelocity,
    required this.minDownwardVelocity,
    required this.hoopPlaneTolerance,
    required this.madeRadius,
    required this.model,
  });

  final String releaseId;
  final String activityId;
  final int schemaVersion;
  final List<String> requiredLandmarks;
  final List<ObjectRequirement> requiredObjects;
  final List<String> states;
  final List<ObjectTransition> transitions;
  final String ballObjectId;
  final String hoopObjectId;
  final int stableFrames;
  final int maxShotMs;
  final double controlDistance;
  final double releaseDistance;
  final double minUpwardVelocity;
  final double minDownwardVelocity;
  final double hoopPlaneTolerance;
  final double madeRadius;
  final ObjectModelSpec model;

  factory ObjectCompositionSpec.fromJson(Map<String, dynamic> json) {
    const allowed = {
      'specSchemaVersion',
      'releaseId',
      'activityId',
      'engineType',
      'measurementType',
      'requiredCapabilities',
      'requiredLandmarks',
      'requiredObjects',
      'composition',
      'model',
    };
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const ObjectCompositionSpecException('Unknown object spec field.');
    }
    final engine = _string(json['engineType'], 'engineType');
    if (engine != 'object_composition_v1') {
      throw const ObjectCompositionSpecException('Object engine mismatch.');
    }
    final measurement = _string(
      json['measurementType'] ?? 'repetitions',
      'measurementType',
    );
    if (measurement != 'repetitions') {
      throw const ObjectCompositionSpecException(
        'Object composition must count repetitions.',
      );
    }
    final requiredLandmarks = _strings(
      json['requiredLandmarks'],
      'requiredLandmarks',
      24,
    );
    final requiredObjects = _objects(json['requiredObjects']);
    final model = ObjectModelSpec.fromJson(json['model']);
    final composition = json['composition'];
    if (composition is! Map<String, dynamic>) {
      throw const ObjectCompositionSpecException('composition is required.');
    }
    const compositionKeys = {
      'states',
      'transitions',
      'startState',
      'terminalStates',
      'ballObjectId',
      'hoopObjectId',
      'stableFrames',
      'maxShotMs',
      'controlDistance',
      'releaseDistance',
      'minUpwardVelocity',
      'minDownwardVelocity',
      'hoopPlaneTolerance',
      'madeRadius',
    };
    if (composition.keys.any((key) => !compositionKeys.contains(key))) {
      throw const ObjectCompositionSpecException('Unknown composition field.');
    }
    final states = _strings(composition['states'], 'states', 16);
    final transitions = _transitions(composition['transitions'], states);
    final startState = _string(composition['startState'], 'startState');
    if (!states.contains(startState)) {
      throw const ObjectCompositionSpecException('startState is not declared.');
    }
    final terminalStates = _strings(
      composition['terminalStates'],
      'terminalStates',
      8,
    );
    if (terminalStates.any((state) => !states.contains(state))) {
      throw const ObjectCompositionSpecException(
        'terminalStates are not declared.',
      );
    }
    final ballObjectId = _string(composition['ballObjectId'], 'ballObjectId');
    final hoopObjectId = _string(composition['hoopObjectId'], 'hoopObjectId');
    final objectIds = requiredObjects.map((entry) => entry.id).toSet();
    if (!objectIds.contains(ballObjectId) ||
        !objectIds.contains(hoopObjectId)) {
      throw const ObjectCompositionSpecException(
        'Ball and hoop objects are required.',
      );
    }
    final stableFrames = _boundedInt(
      composition['stableFrames'],
      'stableFrames',
      1,
      12,
    );
    final maxShotMs = _boundedInt(
      composition['maxShotMs'],
      'maxShotMs',
      1000,
      60 * 1000,
    );
    final controlDistance = _boundedDouble(
      composition['controlDistance'],
      'controlDistance',
      0.01,
      1,
    );
    final releaseDistance = _boundedDouble(
      composition['releaseDistance'],
      'releaseDistance',
      0.01,
      1,
    );
    final minUpwardVelocity = _boundedDouble(
      composition['minUpwardVelocity'],
      'minUpwardVelocity',
      0.001,
      10,
    );
    final minDownwardVelocity = _boundedDouble(
      composition['minDownwardVelocity'],
      'minDownwardVelocity',
      0.001,
      10,
    );
    final hoopPlaneTolerance = _boundedDouble(
      composition['hoopPlaneTolerance'],
      'hoopPlaneTolerance',
      0.001,
      1,
    );
    final madeRadius = _boundedDouble(
      composition['madeRadius'],
      'madeRadius',
      0.001,
      1,
    );
    return ObjectCompositionSpec(
      releaseId: _string(json['releaseId'], 'releaseId'),
      activityId: _string(json['activityId'], 'activityId'),
      schemaVersion: _boundedInt(
        json['specSchemaVersion'],
        'specSchemaVersion',
        1,
        1,
      ),
      requiredLandmarks: requiredLandmarks,
      requiredObjects: requiredObjects,
      states: states,
      transitions: transitions,
      ballObjectId: ballObjectId,
      hoopObjectId: hoopObjectId,
      stableFrames: stableFrames,
      maxShotMs: maxShotMs,
      controlDistance: controlDistance,
      releaseDistance: releaseDistance,
      minUpwardVelocity: minUpwardVelocity,
      minDownwardVelocity: minDownwardVelocity,
      hoopPlaneTolerance: hoopPlaneTolerance,
      madeRadius: madeRadius,
      model: model,
    );
  }

  static String _string(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty && value.length <= 160)
      return value.trim();
    throw ObjectCompositionSpecException('$field is invalid.');
  }

  static List<String> _strings(Object? value, String field, int max) {
    if (value is! List || value.isEmpty || value.length > max) {
      throw ObjectCompositionSpecException('$field is invalid.');
    }
    final values = value.map((entry) => _string(entry, field)).toList();
    if (values.toSet().length != values.length)
      throw ObjectCompositionSpecException('$field contains duplicates.');
    return List.unmodifiable(values);
  }

  static int _boundedInt(Object? value, String field, int min, int max) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      throw ObjectCompositionSpecException('$field is invalid.');
    }
    final parsed = value.toInt();
    if (parsed < min || parsed > max)
      throw ObjectCompositionSpecException(
        '$field is outside the supported range.',
      );
    return parsed;
  }

  static double _boundedDouble(
    Object? value,
    String field,
    double min,
    double max,
  ) {
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw ObjectCompositionSpecException(
        '$field is outside the supported range.',
      );
    }
    return value.toDouble();
  }

  static List<ObjectRequirement> _objects(Object? value) {
    if (value is! List || value.isEmpty || value.length > 8) {
      throw const ObjectCompositionSpecException('requiredObjects is invalid.');
    }
    final result = value.map((entry) {
      if (entry is! Map<String, dynamic>)
        throw const ObjectCompositionSpecException(
          'Object requirement is invalid.',
        );
      const keys = {'id', 'kind', 'minLikelihood'};
      if (entry.keys.any((key) => !keys.contains(key)))
        throw const ObjectCompositionSpecException(
          'Unknown object requirement field.',
        );
      final id = _string(entry['id'], 'object.id');
      final kind = _string(entry['kind'], 'object.kind');
      if (!{'ball', 'hoop'}.contains(kind))
        throw const ObjectCompositionSpecException('Unsupported object kind.');
      final likelihood = _boundedDouble(
        entry['minLikelihood'] ?? 0.35,
        'object.minLikelihood',
        0.2,
        1,
      );
      return ObjectRequirement(id: id, kind: kind, minLikelihood: likelihood);
    }).toList();
    if (result.map((entry) => entry.id).toSet().length != result.length) {
      throw const ObjectCompositionSpecException('Object IDs must be unique.');
    }
    return List.unmodifiable(result);
  }

  static List<ObjectTransition> _transitions(
    Object? value,
    List<String> states,
  ) {
    if (value is! List || value.isEmpty || value.length > 24) {
      throw const ObjectCompositionSpecException('transitions is invalid.');
    }
    const events = {
      'ball_controlled',
      'ball_released',
      'ball_ascending',
      'ball_descending',
      'ball_through_hoop',
      'shot_timeout',
    };
    return List.unmodifiable(
      value.map((entry) {
        if (entry is! Map<String, dynamic>)
          throw const ObjectCompositionSpecException('Transition is invalid.');
        const keys = {'from', 'to', 'event'};
        if (entry.keys.any((key) => !keys.contains(key)))
          throw const ObjectCompositionSpecException(
            'Unknown transition field.',
          );
        final from = _string(entry['from'], 'transition.from');
        final to = _string(entry['to'], 'transition.to');
        final event = _string(entry['event'], 'transition.event');
        if (!states.contains(from) ||
            !states.contains(to) ||
            !events.contains(event)) {
          throw const ObjectCompositionSpecException(
            'Transition references an unsupported state or event.',
          );
        }
        return ObjectTransition(from: from, to: to, event: event);
      }),
    );
  }
}

/// Immutable model identity carried by an object-composition release.
///
/// The client may download bytes for this exact version, but it cannot choose
/// a different model or accept an artifact whose digest does not match this
/// descriptor.
class ObjectModelSpec {
  const ObjectModelSpec({
    required this.modelVersion,
    required this.inputSchemaVersion,
    required this.artifactSha256,
    required this.inputSize,
  });

  final String modelVersion;
  final int inputSchemaVersion;
  final String artifactSha256;
  final int inputSize;

  factory ObjectModelSpec.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const ObjectCompositionSpecException('model is required.');
    }
    const keys = {
      'modelVersion',
      'inputSchemaVersion',
      'artifactSha256',
      'inputSize',
    };
    if (value.keys.any((key) => !keys.contains(key))) {
      throw const ObjectCompositionSpecException('Unknown model field.');
    }
    final version = ObjectCompositionSpec._string(
      value['modelVersion'],
      'model.modelVersion',
    );
    final schema = ObjectCompositionSpec._boundedInt(
      value['inputSchemaVersion'],
      'model.inputSchemaVersion',
      1,
      1,
    );
    final digest = ObjectCompositionSpec._string(
      value['artifactSha256'],
      'model.artifactSha256',
    ).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const ObjectCompositionSpecException(
        'model.artifactSha256 is invalid.',
      );
    }
    final inputSize = ObjectCompositionSpec._boundedInt(
      value['inputSize'],
      'model.inputSize',
      160,
      1280,
    );
    return ObjectModelSpec(
      modelVersion: version,
      inputSchemaVersion: schema,
      artifactSha256: digest,
      inputSize: inputSize,
    );
  }
}

class ObjectRequirement {
  const ObjectRequirement({
    required this.id,
    required this.kind,
    required this.minLikelihood,
  });

  final String id;
  final String kind;
  final double minLikelihood;
}

class ObjectTransition {
  const ObjectTransition({
    required this.from,
    required this.to,
    required this.event,
  });

  final String from;
  final String to;
  final String event;
}
