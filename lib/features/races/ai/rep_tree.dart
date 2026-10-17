import 'dart:math' as math;

import '../data/ai_motion_models.dart';
import 'motion_validators.dart';

/// `rep_tree_v1` — the spec-driven twin of [RepMovementDefinition].
///
/// A rep is a START condition and an ACTIVE condition (each a small tree of
/// signal comparisons) fed through the same [RepCounterStateMachine] the
/// compiled validators use. The signals themselves are named, bounded and
/// implemented here once — a spec can pick signals, thresholds, and how they
/// combine, but can never introduce new math. That keeps a Cloudflare-published
/// release a data change while behavior stays reproducible and testable.
///
/// JSON grammar (closed — unknown keys fail closed):
///   cond := {"signal": S, "gt": n} | {"signal": S, "lt": n}
///         | {"flag": F}
///         | {"all": [cond, ...]} | {"any": [cond, ...]}
class RepTreeSpecException implements Exception {
  const RepTreeSpecException(this.message);

  final String message;

  @override
  String toString() => 'RepTreeSpecException: $message';
}

/// A numeric body signal. [landmarks] are the points it dereferences — a spec
/// that uses a signal must list all of them in `requiredLandmarks`.
class RepTreeSignal {
  const RepTreeSignal(this.landmarks, this.min, this.max, this.read);

  final List<String> landmarks;

  /// Inclusive bounds a threshold must fall inside.
  final double min;
  final double max;
  final double Function(PoseFeatureExtractor f) read;
}

const _shoulders = ['leftShoulder', 'rightShoulder'];
const _hips = ['leftHip', 'rightHip'];
const _knees = ['leftKnee', 'rightKnee'];
const _ankles = ['leftAnkle', 'rightAnkle'];
const _wrists = ['leftWrist', 'rightWrist'];

double _wristY(PoseFeatureExtractor f, bool high) {
  final l = f.frame.point('leftWrist')!.y;
  final r = f.frame.point('rightWrist')!.y;
  return high ? math.max(l, r) : math.min(l, r);
}

final Map<String, RepTreeSignal> kRepTreeSignals = {
  // (kneeY − hipY) / torsoHeight; lower = deeper squat.
  'hipToKneeRatio': RepTreeSignal(
    [..._shoulders, ..._hips, ..._knees],
    -2,
    3,
    (f) => f.hipToKneeRatio(),
  ),
  'ankleWidthToBodyWidth': RepTreeSignal(
    [..._shoulders, ..._hips, ..._ankles],
    0,
    12,
    (f) => f.ankleWidth / f.bodyWidth,
  ),
  'kneeSeparationToHipWidth': RepTreeSignal(
    [..._knees, ..._hips],
    0,
    12,
    (f) =>
        (f.frame.point('leftKnee')!.x - f.frame.point('rightKnee')!.x).abs() /
        f.hipWidth,
  ),
  'leftKneeAngle': RepTreeSignal(
    ['leftHip', 'leftKnee', 'leftAnkle'],
    0,
    180,
    (f) => f.kneeAngle(left: true),
  ),
  'rightKneeAngle': RepTreeSignal(
    ['rightHip', 'rightKnee', 'rightAnkle'],
    0,
    180,
    (f) => f.kneeAngle(left: false),
  ),
  'leftElbowAngle': RepTreeSignal(
    ['leftShoulder', 'leftElbow', 'leftWrist'],
    0,
    180,
    (f) => f.elbowAngle(left: true),
  ),
  'rightElbowAngle': RepTreeSignal(
    ['rightShoulder', 'rightElbow', 'rightWrist'],
    0,
    180,
    (f) => f.elbowAngle(left: false),
  ),
  // Both wrists at least this far ABOVE the shoulder line (torso-agnostic,
  // normalized image units). Positive = above.
  'wristsAboveShoulderMargin': RepTreeSignal(
    [..._wrists, ..._shoulders],
    -1,
    1,
    (f) => f.shoulderY - _wristY(f, true),
  ),
  // Both wrists at least this far BELOW the shoulder line. Positive = below.
  'wristsBelowShoulderMargin': RepTreeSignal(
    [..._wrists, ..._shoulders],
    -1,
    1,
    (f) => _wristY(f, false) - f.shoulderY,
  ),
  // Lowest wrist relative to the hip line. Positive = below the hips.
  'wristsBelowHipMargin': RepTreeSignal(
    [..._wrists, ..._hips],
    -1,
    1,
    (f) => _wristY(f, true) - f.hipY,
  ),
  // Torso-relative variants (scale-invariant): distance divided by the
  // shoulder→hip span, so one threshold works at any camera distance.
  'wristsAboveShoulderTorso': RepTreeSignal(
    [..._wrists, ..._shoulders, ..._hips],
    -4,
    4,
    (f) => (f.shoulderY - _wristY(f, true)) / f.torsoHeight,
  ),
  'wristsBelowShoulderTorso': RepTreeSignal(
    [..._wrists, ..._shoulders, ..._hips],
    -4,
    4,
    (f) => (_wristY(f, false) - f.shoulderY) / f.torsoHeight,
  ),
  // Left wrist relative to the hip line. Positive = below the hips.
  'leftWristBelowHipTorso': RepTreeSignal(
    ['leftWrist', ..._shoulders, ..._hips],
    -4,
    4,
    (f) => (f.frame.point('leftWrist')!.y - f.hipY) / f.torsoHeight,
  ),
};

/// Boolean signals, exactly as the compiled validators define them.
final Map<String, RepTreeSignal> kRepTreeFlags = {
  'wristsAboveShoulders': RepTreeSignal(
    [..._wrists, ..._shoulders],
    0,
    1,
    (f) => f.wristsAboveShoulders ? 1 : 0,
  ),
  'wristsNearBody': RepTreeSignal(
    [..._wrists, ..._shoulders, ..._hips],
    0,
    1,
    (f) => f.wristsNearBody ? 1 : 0,
  ),
};

const _maxDepth = 4;
const _maxNodes = 24;

abstract class RepTreeCondition {
  const RepTreeCondition();

  bool evaluate(PoseFeatureExtractor f);

  /// Landmarks every leaf dereferences.
  Set<String> get landmarks;
}

class _Compare extends RepTreeCondition {
  const _Compare(this.signal, this.threshold, {required this.greaterThan});

  final RepTreeSignal signal;
  final double threshold;
  final bool greaterThan;

  @override
  bool evaluate(PoseFeatureExtractor f) {
    final value = signal.read(f);
    if (!value.isFinite) return false;
    return greaterThan ? value > threshold : value < threshold;
  }

  @override
  Set<String> get landmarks => signal.landmarks.toSet();
}

class _Flag extends RepTreeCondition {
  const _Flag(this.signal);

  final RepTreeSignal signal;

  @override
  bool evaluate(PoseFeatureExtractor f) => signal.read(f) > 0;

  @override
  Set<String> get landmarks => signal.landmarks.toSet();
}

class _Group extends RepTreeCondition {
  const _Group(this.children, {required this.all});

  final List<RepTreeCondition> children;
  final bool all;

  @override
  bool evaluate(PoseFeatureExtractor f) => all
      ? children.every((c) => c.evaluate(f))
      : children.any((c) => c.evaluate(f));

  @override
  Set<String> get landmarks => {for (final c in children) ...c.landmarks};
}

class RepTreeSpec {
  const RepTreeSpec({required this.start, required this.active});

  final RepTreeCondition start;
  final RepTreeCondition active;

  /// Every landmark the two conditions dereference.
  Set<String> get landmarks => {...start.landmarks, ...active.landmarks};

  /// Parses `{start: cond, active: cond}`. [requiredLandmarks] must cover
  /// every landmark a signal reads, otherwise the evaluator could dereference
  /// a point the runtime never verified is present — that fails closed here.
  factory RepTreeSpec.fromJson(Object? json, List<String> requiredLandmarks) {
    if (json is! Map<String, dynamic> ||
        json.keys.any((k) => k != 'start' && k != 'active')) {
      throw const RepTreeSpecException('repTree needs only start and active.');
    }
    var nodes = 0;
    RepTreeCondition parse(Object? node, int depth) {
      if (++nodes > _maxNodes) {
        throw const RepTreeSpecException('repTree has too many nodes.');
      }
      if (depth > _maxDepth || node is! Map<String, dynamic>) {
        throw const RepTreeSpecException('Invalid repTree condition.');
      }
      final keys = node.keys.toSet();
      if (keys.length == 1 && (keys.first == 'all' || keys.first == 'any')) {
        final list = node[keys.first];
        if (list is! List || list.isEmpty || list.length > 8) {
          throw const RepTreeSpecException('all/any needs 1..8 conditions.');
        }
        return _Group([
          for (final child in list) parse(child, depth + 1),
        ], all: keys.first == 'all');
      }
      if (keys.length == 1 && keys.first == 'flag') {
        final flag = kRepTreeFlags[node['flag']];
        if (flag == null) throw const RepTreeSpecException('Unknown flag.');
        return _Flag(flag);
      }
      if (keys.length == 2 &&
          keys.contains('signal') &&
          (keys.contains('gt') || keys.contains('lt'))) {
        final signal = kRepTreeSignals[node['signal']];
        if (signal == null) throw const RepTreeSpecException('Unknown signal.');
        final greater = keys.contains('gt');
        final value = node[greater ? 'gt' : 'lt'];
        if (value is! num ||
            !value.isFinite ||
            value < signal.min ||
            value > signal.max) {
          throw const RepTreeSpecException('Threshold is outside its range.');
        }
        return _Compare(signal, value.toDouble(), greaterThan: greater);
      }
      throw const RepTreeSpecException('Unrecognized repTree condition.');
    }

    final spec = RepTreeSpec(
      start: parse(json['start'], 1),
      active: parse(json['active'], 1),
    );
    final missing = spec.landmarks.difference(requiredLandmarks.toSet());
    if (missing.isNotEmpty) {
      throw RepTreeSpecException(
        'requiredLandmarks must include: ${missing.join(', ')}.',
      );
    }
    return spec;
  }

  /// START/ACTIVE classification for one frame — active wins, matching the
  /// compiled [ConfigurableRepValidator].
  MovementPhase measure(NuvoPoseFrame frame) {
    final features = PoseFeatureExtractor(frame);
    if (active.evaluate(features)) return MovementPhase.active;
    if (start.evaluate(features)) return MovementPhase.start;
    return MovementPhase.unknown;
  }
}
