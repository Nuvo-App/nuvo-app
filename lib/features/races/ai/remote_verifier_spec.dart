import '../data/ai_motion_models.dart';
import '../data/motion_package.dart';
import 'remote_pose_features.dart';

enum RemoteEngineType { stateMachineV1, alternatingRepV1, holdV1, sequenceMatchV1 }

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

/// The closed predicate grammar for `sequence_match_v1`. Exactly four kinds —
/// no expressions, no formulas, no scripting. Each predicate resolves a single
/// scalar from a pose frame via [RemotePoseFeatures] and compares it against
/// a bounded threshold. Any degenerate input evaluates to false.
enum SequencePredicateKind { landmarkAxis, angle, axisDelta, segmentRatio }

/// One declarative predicate inside a [SequencePhase]. The stored fields are
/// the wire format verbatim (bounded strings/numbers); interpretation is
/// fixed by [kind] — the spec can never invent a new predicate type.
class SequencePredicate {
  const SequencePredicate._({
    required this.kind,
    required this.operator,
    required this.threshold,
    required this.minLikelihood,
    this.point,
    this.axis,
    this.a,
    this.b,
    this.c,
    this.refA,
    this.refB,
  });

  final SequencePredicateKind kind;
  final RemoteOperator operator;

  /// landmarkAxis: normalized coordinate bound 0..1. angle: degrees 0..180.
  /// axisDelta: normalized signed delta -1..1. segmentRatio: 0..8.
  final double threshold;
  final double minLikelihood;

  /// landmarkAxis target point.
  final String? point;
  final RemoteAxis? axis;

  /// angle: a/b/c joint. axisDelta: a−b. segmentRatio: |a−b| / |refA−refB|.
  final String? a;
  final String? b;
  final String? c;
  final String? refA;
  final String? refB;

  bool matches(NuvoPoseFrame frame) {
    final value = switch (kind) {
      SequencePredicateKind.landmarkAxis => _axisValue(frame),
      SequencePredicateKind.angle => RemotePoseFeatures.angle(
        a: frame.point(a!),
        b: frame.point(b!),
        c: frame.point(c!),
        minLikelihood: minLikelihood,
      ),
      SequencePredicateKind.axisDelta => RemotePoseFeatures.axisDelta(
        a: frame.point(a!),
        b: frame.point(b!),
        isX: axis == RemoteAxis.x,
        minLikelihood: minLikelihood,
      ),
      SequencePredicateKind.segmentRatio => RemotePoseFeatures.segmentRatio(
        a: frame.point(a!),
        b: frame.point(b!),
        refA: frame.point(refA!),
        refB: frame.point(refB!),
        minLikelihood: minLikelihood,
      ),
    };
    if (value == null) return false;
    return switch (operator) {
      RemoteOperator.greaterThan => value > threshold,
      RemoteOperator.greaterThanOrEqual => value >= threshold,
      RemoteOperator.lessThan => value < threshold,
      RemoteOperator.lessThanOrEqual => value <= threshold,
    };
  }

  double? _axisValue(NuvoPoseFrame frame) {
    final pose = frame.point(point!);
    if (pose == null || pose.likelihood < minLikelihood) return null;
    final value = axis == RemoteAxis.x ? pose.x : pose.y;
    return value.isFinite ? value : null;
  }
}

/// One link in the linear `sequence_match_v1` phase chain.
///
/// Dwell semantics — the hysteresis contract:
/// * a phase's predicates must hold for [minDwellFrames] *consecutive* frames
///   before the sequence advances (a single noisy frame cannot jump phases);
/// * a miss resets the dwell counter, but up to [breakToleranceFrames]
///   consecutive misses are tolerated before the whole sequence resets —
///   hovering around a threshold stalls progress rather than chattering the
///   machine, and only a sustained break resets it.
class SequencePhase {
  const SequencePhase({
    required this.id,
    required this.predicates,
    required this.minDwellFrames,
    required this.breakToleranceFrames,
    required this.next,
    this.maxDwellMs,
  });

  final String id;
  final List<SequencePredicate> predicates;
  final int minDwellFrames;
  final int breakToleranceFrames;

  /// Next phase id, or the literal `'complete'` — which fires a rep and
  /// resets the machine to phase 0. V1 enforces a strict linear chain:
  /// every phase's `next` must be exactly the following phase, and only the
  /// last phase may complete. No branches, no mid-sequence cycles.
  final String next;

  /// Optional per-phase time cap once the sequence has begun.
  final int? maxDwellMs;

  bool get completesRep => next == 'complete';
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
    this.measurementType = 'repetitions',
    this.phases = const [],
    this.repTimeoutMs = 8000,
    this.lostPoseMs = 1500,
    this.activity,
    this.package,
  });

  final String releaseId;
  final String activityId;
  final RemoteEngineType engine;
  final int schemaVersion;

  /// 'repetitions' or 'duration' — drives hold-vs-rep display and runtime
  /// semantics without consulting a compiled activity definition.
  final String measurementType;

  /// Optional server-owned activity metadata (see [RemoteActivityInfo]).
  /// Lets a motion this build has never heard of supply camera framing,
  /// instructions, and labels without a compiled definition.
  final RemoteActivityInfo? activity;

  /// Optional asset manifest (see [MotionPackageManifest]).
  final MotionPackageManifest? package;
  final List<String> requiredLandmarks;
  final int stableFrames;
  final List<RemotePoseRule> startRules;
  final List<RemotePoseRule> activeRules;
  final List<RemotePoseRule> leftRules;
  final List<RemotePoseRule> rightRules;
  final List<RemotePoseRule> holdRules;
  final int minHoldMs;
  final int maxHoldMs;

  /// `sequence_match_v1` only: the ordered phase chain. Empty for every
  /// other engine — a spec may never carry sequence data for a different
  /// engine.
  final List<SequencePhase> phases;

  /// `sequence_match_v1` only: once a sequence has begun (past phase 0),
  /// exceeding this elapsed time resets to phase 0.
  final int repTimeoutMs;

  /// `sequence_match_v1` only: mid-sequence, required landmarks may be
  /// absent this long before the sequence resets (dwell pauses instead).
  final int lostPoseMs;

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
      'phases',
      'repTimeoutMs',
      'lostPoseMs',
      'activity',
      'package',
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
      'sequence_match_v1' => RemoteEngineType.sequenceMatchV1,
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
    // Sequence fields are engine-scoped: carrying them under another engine
    // is a spec authoring bug and fails closed, never silently ignored.
    final isSequence = engine == RemoteEngineType.sequenceMatchV1;
    if (!isSequence &&
        (json.containsKey('phases') ||
            json.containsKey('repTimeoutMs') ||
            json.containsKey('lostPoseMs'))) {
      throw RemoteVerifierSpecException(
        'Sequence fields require sequence_match_v1.',
      );
    }
    if (isSequence && measurementType != 'repetitions') {
      throw RemoteVerifierSpecException(
        'sequence_match_v1 supports repetitions only.',
      );
    }
    final phases = isSequence
        ? _phases(json['phases'], stableFrames)
        : const <SequencePhase>[];
    final repTimeoutMs = _boundedInt(
      json['repTimeoutMs'],
      'repTimeoutMs',
      500,
      60 * 1000,
      fallback: 8000,
    );
    final lostPoseMs = _boundedInt(
      json['lostPoseMs'],
      'lostPoseMs',
      100,
      10 * 1000,
      fallback: 1500,
    );
    // `activity` degrades to null on malformed input — camera framing and
    // instructions fall back to generic remote guidance, never to a wrong
    // activity's metadata. `package` is fail-closed: a release that claims to
    // carry assets must declare them correctly or be rejected outright.
    final activity = RemoteActivityInfo.tryParse(json['activity']);
    final package = json.containsKey('package')
        ? MotionPackageManifest.tryParse(json['package'])
        : null;
    if (json.containsKey('package') && package == null) {
      throw const RemoteVerifierSpecException('Invalid package manifest.');
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
      measurementType: measurementType,
      phases: phases,
      repTimeoutMs: repTimeoutMs,
      lostPoseMs: lostPoseMs,
      activity: activity,
      package: package,
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

  /// Parses and validates the `phases` chain for `sequence_match_v1`.
  ///
  /// V1 enforces a STRICT LINEAR chain — no branches, no cycles:
  /// * 2..8 phases, unique kebab/snake ids;
  /// * every phase's `next` must be exactly the following phase's id;
  /// * the last phase's `next` must be the literal `'complete'`.
  ///
  /// Any deviation (skipped phases, jumps, self loops, missing complete
  /// edge) is a spec authoring bug and fails closed.
  static List<SequencePhase> _phases(Object? value, int stableFrames) {
    if (value is! List || value.length < 2 || value.length > 8) {
      throw RemoteVerifierSpecException(
        'sequence_match_v1 requires 2..8 phases.',
      );
    }
    final parsed = <SequencePhase>[];
    final seenIds = <String>{};
    for (final entry in value) {
      if (entry is! Map<String, dynamic>) {
        throw RemoteVerifierSpecException('Invalid sequence phase.');
      }
      const allowedKeys = {
        'id',
        'predicates',
        'minDwellFrames',
        'breakToleranceFrames',
        'maxDwellMs',
        'next',
      };
      if (entry.keys.any((key) => !allowedKeys.contains(key))) {
        throw RemoteVerifierSpecException('Unknown sequence phase field.');
      }
      final id = _string(entry['id'], 'phase.id');
      if (!RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(id)) {
        throw RemoteVerifierSpecException('Invalid sequence phase id.');
      }
      if (!seenIds.add(id)) {
        throw RemoteVerifierSpecException('Duplicate sequence phase id.');
      }
      final predicates = _predicates(entry['predicates']);
      final dwell = _boundedInt(
        entry['minDwellFrames'],
        'minDwellFrames',
        1,
        30,
        fallback: stableFrames,
      );
      final tolerance = _boundedInt(
        entry['breakToleranceFrames'],
        'breakToleranceFrames',
        0,
        8,
        fallback: 1,
      );
      final maxDwellMs = entry['maxDwellMs'] == null
          ? null
          : _boundedInt(entry['maxDwellMs'], 'maxDwellMs', 50, 60 * 1000,
              fallback: 0);
      final next = _string(entry['next'], 'phase.next');
      parsed.add(
        SequencePhase(
          id: id,
          predicates: predicates,
          minDwellFrames: dwell,
          breakToleranceFrames: tolerance,
          maxDwellMs: maxDwellMs,
          next: next,
        ),
      );
    }
    for (var i = 0; i < parsed.length; i++) {
      final expected = i == parsed.length - 1 ? 'complete' : parsed[i + 1].id;
      if (parsed[i].next != expected) {
        throw RemoteVerifierSpecException(
          'sequence_match_v1 requires a strict linear phase chain.',
        );
      }
    }
    return parsed;
  }

  static List<SequencePredicate> _predicates(Object? value) {
    if (value is! List || value.isEmpty || value.length > 6) {
      throw RemoteVerifierSpecException(
        'Each sequence phase requires 1..6 predicates.',
      );
    }
    return value.map(_predicate).toList();
  }

  /// Parses one predicate. The `kind` field selects the grammar — every
  /// other field is validated against that kind's closed key set, so a
  /// predicate can never smuggle in an expression the engine doesn't own.
  static SequencePredicate _predicate(Object? entry) {
    if (entry is! Map<String, dynamic>) {
      throw RemoteVerifierSpecException('Invalid sequence predicate.');
    }
    final kind = switch (_string(entry['kind'], 'predicate.kind')) {
      'landmark_axis' => SequencePredicateKind.landmarkAxis,
      'angle' => SequencePredicateKind.angle,
      'axis_delta' => SequencePredicateKind.axisDelta,
      'segment_ratio' => SequencePredicateKind.segmentRatio,
      _ => throw RemoteVerifierSpecException(
        'Unknown sequence predicate kind.',
      ),
    };
    const kindKeys = {
      SequencePredicateKind.landmarkAxis: {
        'kind', 'point', 'axis', 'operator', 'threshold', 'minLikelihood',
      },
      SequencePredicateKind.angle: {
        'kind', 'a', 'b', 'c', 'operator', 'degrees', 'minLikelihood',
      },
      SequencePredicateKind.axisDelta: {
        'kind', 'a', 'b', 'axis', 'operator', 'delta', 'minLikelihood',
      },
      SequencePredicateKind.segmentRatio: {
        'kind', 'a', 'b', 'refA', 'refB', 'operator', 'ratio', 'minLikelihood',
      },
    };
    if (entry.keys.any((key) => !kindKeys[kind]!.contains(key))) {
      throw RemoteVerifierSpecException('Unknown sequence predicate field.');
    }
    final operator = _operator(entry['operator']);
    final likelihood = entry['minLikelihood'];
    if (likelihood != null &&
        (likelihood is! num ||
            !likelihood.isFinite ||
            likelihood < 0.2 ||
            likelihood > 1)) {
      throw RemoteVerifierSpecException('minLikelihood is outside 0.2..1.');
    }
    final minLikelihood = likelihood is num ? likelihood.toDouble() : 0.35;
    String landmark(String field) =>
        _strings([entry[field]], field, max: 1).single;
    RemoteAxis axis() => switch (_string(entry['axis'], 'axis')) {
      'x' => RemoteAxis.x,
      'y' => RemoteAxis.y,
      _ => throw RemoteVerifierSpecException('axis must be x or y.'),
    };
    double bounded(String field, double min, double max) {
      final value = entry[field];
      if (value is! num ||
          !value.isFinite ||
          value < min ||
          value > max) {
        throw RemoteVerifierSpecException('$field is outside its range.');
      }
      return value.toDouble();
    }

    return switch (kind) {
      SequencePredicateKind.landmarkAxis => SequencePredicate._(
        kind: kind,
        operator: operator,
        threshold: bounded('threshold', 0, 1),
        minLikelihood: minLikelihood,
        point: landmark('point'),
        axis: axis(),
      ),
      SequencePredicateKind.angle => SequencePredicate._(
        kind: kind,
        operator: operator,
        threshold: bounded('degrees', 0, 180),
        minLikelihood: minLikelihood,
        a: landmark('a'),
        b: landmark('b'),
        c: landmark('c'),
      ),
      SequencePredicateKind.axisDelta => SequencePredicate._(
        kind: kind,
        operator: operator,
        threshold: bounded('delta', -1, 1),
        minLikelihood: minLikelihood,
        a: landmark('a'),
        b: landmark('b'),
        axis: axis(),
      ),
      SequencePredicateKind.segmentRatio => SequencePredicate._(
        kind: kind,
        operator: operator,
        threshold: bounded('ratio', 0, 8),
        minLikelihood: minLikelihood,
        a: landmark('a'),
        b: landmark('b'),
        refA: landmark('refA'),
        refB: landmark('refB'),
      ),
    };
  }

  static RemoteOperator _operator(Object? value) =>
      switch (_string(value, 'operator')) {
        'gt' => RemoteOperator.greaterThan,
        'gte' => RemoteOperator.greaterThanOrEqual,
        'lt' => RemoteOperator.lessThan,
        'lte' => RemoteOperator.lessThanOrEqual,
        _ => throw RemoteVerifierSpecException('Unknown predicate operator.'),
      };
}
