import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/rep_tree.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Parity: every published `rep_tree_v1` spec in server/worker/motion_specs
/// must count reps identically to the compiled validator it replaces, frame
/// for frame, over a large randomized pose stream.
const _compiled = <String, RepMovementDefinition>{
  'squats': squatRepDefinition,
  'deep_squats': deepSquatRepDefinition,
  'sumo_squats': sumoSquatRepDefinition,
  'jumping_jacks': jumpingJackRepDefinition,
  'squat_jacks': squatJackRepDefinition,
  'lunges': lungeRepDefinition,
  'side_lunges': sideLungeRepDefinition,
};

/// A synthetic full-body pose from independent knobs. Sampling the knobs
/// broadly (and holding each pose a few frames) exercises every START/ACTIVE
/// transition, dead-band frame, and flicker the counters have to survive.
NuvoPoseFrame _pose(math.Random r, int ms) {
  double u(double a, double b) => a + r.nextDouble() * (b - a);
  final hipW = u(0.08, 0.2);
  final shoulderY = 0.3;
  final hipY = 0.3 + u(0.15, 0.3);
  final kneeY = hipY + u(0.0, 0.3);
  final ankleY = kneeY + u(0.1, 0.3);
  final ankleHalf = u(0.4, 2.0) * hipW;
  final kneeHalf = u(0.2, 1.3) * hipW;
  final kneeBendX = u(-0.12, 0.12);
  // Arms: mostly clearly up or clearly down (both wrists together), with
  // occasional mismatched or mid-height wrists to hit the margins.
  final armsUp = r.nextBool();
  final wristY = armsUp ? u(0.05, 0.28) : u(0.31, hipY + 0.3);
  final wristY2 = r.nextInt(6) == 0 ? u(0.05, 0.9) : wristY;
  NuvoPosePoint p(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
  return NuvoPoseFrame(
    points: {
      'leftShoulder': p(0.5 - hipW, shoulderY),
      'rightShoulder': p(0.5 + hipW, shoulderY),
      'leftElbow': p(0.5 - hipW, 0.45),
      'rightElbow': p(0.5 + hipW, 0.45),
      'leftWrist': p(0.5 - hipW, wristY),
      'rightWrist': p(0.5 + hipW, wristY2),
      'leftHip': p(0.5 - hipW / 1.1, hipY),
      'rightHip': p(0.5 + hipW / 1.1, hipY),
      'leftKnee': p(0.5 - kneeHalf + kneeBendX, kneeY),
      'rightKnee': p(0.5 + kneeHalf + kneeBendX, kneeY),
      'leftAnkle': p(0.5 - ankleHalf, ankleY),
      'rightAnkle': p(0.5 + ankleHalf, ankleY),
    },
    imageWidth: 640,
    imageHeight: 480,
    createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  );
}

/// Specs whose compiled twin is bespoke (not a RepMovementDefinition); each
/// has its own parity test.
const _bespoke = {'arm_raises'};

void main() {
  final dir = Directory('server/worker/motion_specs');
  final files = dir.listSync().whereType<File>().where(
    (f) =>
        f.path.endsWith('.json') &&
        (jsonDecode(f.readAsStringSync()) as Map)['engineType'] ==
            'rep_tree_v1' &&
        !_bespoke.contains(f.uri.pathSegments.last.replaceAll('.json', '')),
  );

  test(
    'signal table matches the Worker fixture (TS asserts the same file)',
    () {
      final fixture =
          jsonDecode(
                File(
                  'server/worker/test/fixtures/rep_tree_signals.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final signals = fixture['signals'] as Map<String, dynamic>;
      expect(kRepTreeSignals.keys.toSet(), signals.keys.toSet());
      for (final entry in signals.entries) {
        final def = entry.value as Map<String, dynamic>;
        final mine = kRepTreeSignals[entry.key]!;
        expect(mine.min, (def['min'] as num).toDouble(), reason: entry.key);
        expect(mine.max, (def['max'] as num).toDouble(), reason: entry.key);
        expect(mine.landmarks, def['landmarks'], reason: entry.key);
      }
      final flags = fixture['flags'] as Map<String, dynamic>;
      expect(kRepTreeFlags.keys.toSet(), flags.keys.toSet());
      for (final entry in flags.entries) {
        expect(kRepTreeFlags[entry.key]!.landmarks, entry.value);
      }
    },
  );

  test('malformed trees fail closed', () {
    Map<String, dynamic> spec(Object? tree, {List<String>? landmarks}) => {
      'specSchemaVersion': 1,
      'releaseId': 'x',
      'activityId': 'squats',
      'engineType': 'rep_tree_v1',
      'requiredLandmarks':
          landmarks ??
          [
            'leftShoulder',
            'rightShoulder',
            'leftHip',
            'rightHip',
            'leftKnee',
            'rightKnee',
          ],
      'repTree': tree,
    };
    const ok = {'signal': 'hipToKneeRatio', 'gt': 0.7};
    expect(
      () => RemoteVerifierSpec.fromJson(spec({'start': ok, 'active': ok})),
      returnsNormally,
    );
    for (final bad in <Object?>[
      {'start': ok},
      {
        'start': ok,
        'active': {'signal': 'nope', 'lt': 1},
      },
      {
        'start': ok,
        'active': {'signal': 'hipToKneeRatio', 'lt': 99},
      },
      {
        'start': ok,
        'active': {'flag': 'wristsNearBody'},
      },
      {
        'start': ok,
        'active': {'all': []},
      },
      {'start': ok, 'active': ok, 'extra': 1},
      'not a map',
    ]) {
      expect(
        () => RemoteVerifierSpec.fromJson(spec(bad)),
        throwsA(isA<RemoteVerifierSpecException>()),
        reason: '$bad',
      );
    }
  });

  test('every rep_tree spec file has a compiled counterpart', () {
    final names = files
        .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
        .toSet();
    expect(names, _compiled.keys.toSet());
  });

  for (final file in files) {
    final id = file.uri.pathSegments.last.replaceAll('.json', '');
    test('$id rep_tree_v1 matches the compiled validator frame by frame', () {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final spec = RemoteVerifierSpec.fromJson(json);
      final remote = createRemoteVerifierRuntime(spec: spec, target: 100000);
      final definition = _compiled[id]!;
      final compiled = ConfigurableRepValidator(
        definition: definition,
        targetValue: 100000,
      )..start();

      final r = math.Random(id.hashCode);
      var ms = 0;
      var reps = 0;
      for (var i = 0; i < 4000; i++) {
        final frame = _pose(r, ms);
        final hold = 3 + r.nextInt(5);
        for (var k = 0; k < hold; k++) {
          final f = NuvoPoseFrame(
            points: frame.points,
            imageWidth: frame.imageWidth,
            imageHeight: frame.imageHeight,
            createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
          );
          ms += 33;
          final a = remote.update(f).count;
          final b = compiled.update(f).currentValue;
          expect(a, b, reason: '$id diverged at frame $ms ms');
          reps = b;
        }
      }
      // The stream must actually exercise counting, or parity is vacuous.
      expect(reps, greaterThan(5), reason: '$id never counted a rep');
    });
  }
}
