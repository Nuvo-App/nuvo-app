import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

Map<String, dynamic> _spec(String id) =>
    jsonDecode(File('server/worker/motion_specs/$id.json').readAsStringSync())
        as Map<String, dynamic>;

NuvoPoseFrame _pose(math.Random r, int ms) {
  double u(double a, double b) => a + r.nextDouble() * (b - a);
  NuvoPosePoint p(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
  final hipY = 0.5 + u(0, 0.15);
  final kneeY = hipY + u(-0.1, 0.3);
  final w = u(0.06, 0.15);
  final shoulderY = 0.25 + u(0, 0.05);
  final elbowBend = u(-0.2, 0.2);
  final wristY = shoulderY + u(0.05, 0.4);
  return NuvoPoseFrame(
    points: {
      'leftShoulder': p(0.5 - w, shoulderY),
      'rightShoulder': p(0.5 + w, shoulderY),
      'leftElbow': p(0.5 - w - elbowBend, shoulderY + 0.12),
      'rightElbow': p(0.5 + w + elbowBend, shoulderY + 0.12),
      'leftWrist': p(0.5 - w, wristY),
      'rightWrist': p(0.5 + w, wristY),
      'leftHip': p(0.5 - w, hipY),
      'rightHip': p(0.5 + w, hipY),
      'leftKnee': p(0.5 - w, kneeY),
      'rightKnee': p(0.5 + w, kneeY),
      'leftAnkle': p(0.5 - u(0.05, 0.2), kneeY + u(0.05, 0.3)),
      'rightAnkle': p(0.5 + u(0.05, 0.2), kneeY + u(0.05, 0.3)),
    },
    imageWidth: 640,
    imageHeight: 480,
    createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  );
}

void main() {
  final fixture =
      (jsonDecode(
                File(
                  'server/worker/test/fixtures/native_tunables.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['tunables']
          as Map<String, dynamic>;

  test('tunable table matches the Worker fixture', () {
    expect(kNativeTunables.keys.toSet(), fixture.keys.toSet());
    for (final e in fixture.entries) {
      final mine = kNativeTunables[e.key]!;
      final theirs = e.value as Map<String, dynamic>;
      expect(mine.keys.toSet(), theirs.keys.toSet(), reason: e.key);
      for (final k in theirs.keys) {
        final t = (theirs[k] as List).map((x) => (x as num).toDouble());
        expect([mine[k]!.$1, mine[k]!.$2, mine[k]!.$3], t.toList());
      }
    }
  });

  for (final id in kNativeTunables.keys) {
    group(id, () {
      test(
        'published spec parses and its params are the compiled defaults',
        () {
          final spec = RemoteVerifierSpec.fromJson(_spec(id));
          expect(spec.engine, RemoteEngineType.nativeTunedV1);
          final params = _spec(id)['params'] as Map<String, dynamic>;
          expect(params.keys.toSet(), kNativeTunables[id]!.keys.toSet());
          for (final e in params.entries) {
            expect(
              (e.value as num).toDouble(),
              kNativeTunables[id]![e.key]!.$1,
              reason: e.key,
            );
          }
        },
      );

      test(
        'default params count exactly like the untuned compiled validator',
        () {
          final spec = RemoteVerifierSpec.fromJson(_spec(id));
          final tuned = createRemoteVerifierRuntime(spec: spec, target: 100000);
          final plain = createMotionValidator(
            AiMotionActivity.fromBackendValue(id),
            100000,
          )..start();
          final r = math.Random(id.hashCode);
          var ms = 0;
          for (var i = 0; i < 3000; i++) {
            final f = _pose(r, ms);
            ms += 33;
            expect(
              tuned.update(f).count,
              plain.update(f).currentValue,
              reason: '$id diverged at $ms ms',
            );
          }
        },
      );

      test('rejects unknown and out-of-range parameters', () {
        final bad1 = _spec(id)..['params'] = {'nope': 1};
        expect(
          () => RemoteVerifierSpec.fromJson(bad1),
          throwsA(isA<RemoteVerifierSpecException>()),
        );
        final key = kNativeTunables[id]!.keys.first;
        final bad2 = _spec(id)
          ..['params'] = {key: kNativeTunables[id]![key]!.$3 + 1000};
        expect(
          () => RemoteVerifierSpec.fromJson(bad2),
          throwsA(isA<RemoteVerifierSpecException>()),
        );
      });
    });
  }

  test('params are required by, and only valid for, native_tuned_v1', () {
    final noParams = _spec('high_knees')..remove('params');
    expect(
      () => RemoteVerifierSpec.fromJson(noParams),
      throwsA(isA<RemoteVerifierSpecException>()),
    );
    final wrongEngine = _spec('squats')..['params'] = {'raiseLift': 0};
    expect(
      () => RemoteVerifierSpec.fromJson(wrongEngine),
      throwsA(isA<RemoteVerifierSpecException>()),
    );
  });

  test(
    'an override changes behavior: stricter high-knee lift counts fewer',
    () {
      NuvoPoseFrame frame(double kneeY, int ms) {
        NuvoPosePoint p(double x, double y) =>
            NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
        return NuvoPoseFrame(
          points: {
            'leftShoulder': p(0.4, 0.3),
            'rightShoulder': p(0.6, 0.3),
            'leftHip': p(0.42, 0.6),
            'rightHip': p(0.58, 0.6),
            'leftKnee': p(0.42, kneeY),
            'rightKnee': p(0.58, 1.2),
          },
          imageWidth: 640,
          imageHeight: 480,
          createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        );
      }

      int run(Map<String, num> params) {
        final json = _spec('high_knees')..['params'] = params;
        final rt = createRemoteVerifierRuntime(
          spec: RemoteVerifierSpec.fromJson(json),
          target: 100,
        );
        var ms = 0;
        var count = 0;
        for (var rep = 0; rep < 5; rep++) {
          // Left knee rises to y=0.75 (lift = -0.5 torso) then drops.
          for (final y in [
            0.95,
            0.95,
            0.95,
            0.75,
            0.75,
            0.75,
            0.95,
            0.95,
            0.95,
          ]) {
            count = rt.update(frame(y, ms)).count;
            ms += 33;
          }
        }
        return count;
      }

      expect(run({}), 0); // lift -0.5 never beats the default -0.35 line
      expect(run({'raiseLift': -0.6, 'lowerLift': -0.8}), 5);
    },
  );

  test(
    'a tuned treadmill release keeps its live distance and pace metrics',
    () {
      final rt = createRemoteVerifierRuntime(
        spec: RemoteVerifierSpec.fromJson(_spec('treadmill_running')),
        target: 1000,
      );
      final u = rt.update(_pose(math.Random(1), 0));
      expect(u.metrics.keys, contains('virtualDistanceM'));
      expect(u.metrics.keys, contains('paceSecPerMile'));
    },
  );
}
