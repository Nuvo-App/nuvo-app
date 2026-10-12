import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_pose_features.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// sequence_match_v1 grammar v2: virtual midpoint landmarks and the
/// `axis_ratio` predicate, which together reproduce the torso-normalized
/// hip-to-knee depth signal the compiled squat validator uses.
const _lm = [
  'leftShoulder',
  'rightShoulder',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
];

Map<String, dynamic> _spec({String hipRef = 'midHip'}) => {
  'specSchemaVersion': 1,
  'releaseId': 'seq-v2-squat',
  'activityId': 'seq_v2_squat',
  'engineType': 'sequence_match_v1',
  'measurementType': 'repetitions',
  'requiredLandmarks': _lm,
  'stableFrames': 2,
  'phases': [
    for (final (id, next, op, v) in const [
      ('top', 'bottom', 'gt', 0.72),
      ('bottom', 'top2', 'lt', 0.5),
      ('top2', 'complete', 'gt', 0.72),
    ])
      {
        'id': id,
        'next': next,
        'predicates': [
          {
            'kind': 'axis_ratio',
            'a': 'midKnee',
            'b': hipRef,
            'axis': 'y',
            'refA': 'midHip',
            'refB': 'midShoulder',
            'refAxis': 'y',
            'operator': op,
            'ratio': v,
          },
        ],
      },
  ],
};

NuvoPoseFrame _frame(double kneeY, int ms, {double likelihood = 0.95}) {
  NuvoPosePoint p(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);
  return NuvoPoseFrame(
    points: {
      'leftShoulder': p(0.4, 0.3),
      'rightShoulder': p(0.6, 0.3),
      'leftHip': p(0.42, 0.55),
      'rightHip': p(0.58, 0.55),
      'leftKnee': p(0.42, kneeY),
      'rightKnee': p(0.58, kneeY),
    },
    imageWidth: 640,
    imageHeight: 480,
    createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  );
}

void main() {
  test('midpoint + axis_ratio counts a torso-normalized squat', () {
    final rt = createRemoteVerifierRuntime(
      spec: RemoteVerifierSpec.fromJson(_spec()),
      target: 5,
    );
    var ms = 0;
    // torso = 0.25. standing knee 0.8 → ratio 1.0; bottom knee 0.62 → 0.28.
    for (final y in [0.8, 0.8, 0.62, 0.62, 0.8, 0.8]) {
      rt.update(_frame(y, ms += 33));
    }
    expect(rt.count, 1);
    // Shallow bend (ratio 0.6) never reaches the bottom phase.
    for (final y in [0.8, 0.8, 0.7, 0.7, 0.8, 0.8]) {
      rt.update(_frame(y, ms += 33));
    }
    expect(rt.count, 1);
  });

  test('the ratio is scale invariant: same pose at half size counts alike', () {
    NuvoPoseFrame scaled(double kneeY, int ms) {
      NuvoPosePoint p(double x, double y) => NuvoPosePoint(
        x: 0.5 + (x - 0.5) / 2,
        y: 0.5 + (y - 0.5) / 2,
        z: 0,
        likelihood: 0.95,
      );
      final f = _frame(kneeY, ms);
      return NuvoPoseFrame(
        points: {
          for (final e in f.points.entries) e.key: p(e.value.x, e.value.y),
        },
        imageWidth: 640,
        imageHeight: 480,
        createdAt: f.createdAt,
      );
    }

    final rt = createRemoteVerifierRuntime(
      spec: RemoteVerifierSpec.fromJson(_spec()),
      target: 5,
    );
    var ms = 0;
    for (final y in [0.8, 0.8, 0.62, 0.62, 0.8, 0.8]) {
      rt.update(scaled(y, ms += 33));
    }
    expect(rt.count, 1);
  });

  test(
    'a missing or low-likelihood side makes the midpoint null (fail closed)',
    () {
      final feature = RemotePoseFeatures.midpoint(
        const NuvoPosePoint(x: 0.4, y: 0.5, z: 0, likelihood: 0.9),
        const NuvoPosePoint(x: 0.6, y: 0.5, z: 0, likelihood: 0.1),
      );
      expect(feature, isNull);
      expect(
        RemotePoseFeatures.axisRatio(
          a: const NuvoPosePoint(x: 0.5, y: 0.8, z: 0, likelihood: 0.9),
          b: const NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.9),
          refA: const NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.9),
          refB: const NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.9),
          isX: false,
        ),
        isNull,
        reason: 'degenerate reference segment',
      );
    },
  );

  test('unknown virtual landmarks and stray fields are rejected', () {
    final bad = _spec();
    ((bad['phases'] as List)[0]['predicates'] as List)[0]['a'] = 'midNose';
    expect(
      () => RemoteVerifierSpec.fromJson(bad),
      throwsA(isA<RemoteVerifierSpecException>()),
    );
    final stray = _spec();
    ((stray['phases'] as List)[0]['predicates'] as List)[0]['expr'] = '1+1';
    expect(
      () => RemoteVerifierSpec.fromJson(stray),
      throwsA(isA<RemoteVerifierSpecException>()),
    );
  });
}
