import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPoseFrame _frame({
  required DateTime at,
  double hipY = 0.35,
  double leftWristY = 0.6,
  double rightWristY = 0.6,
}) {
  final points = <String, NuvoPosePoint>{};
  for (final point in const [
    'leftHip',
    'rightHip',
    'leftShoulder',
    'rightShoulder',
    'leftWrist',
    'rightWrist',
  ]) {
    points[point] = NuvoPosePoint(
      x: point.startsWith('left') ? 0.35 : 0.65,
      y: point == 'leftHip' || point == 'rightHip'
          ? hipY
          : point == 'leftWrist'
          ? leftWristY
          : point == 'rightWrist'
          ? rightWristY
          : 0.45,
      z: 0,
      likelihood: 0.95,
    );
  }
  return NuvoPoseFrame(
    points: points,
    imageWidth: 100,
    imageHeight: 100,
    createdAt: at,
  );
}

Map<String, dynamic> _base(String engine) => {
  'specSchemaVersion': 1,
  'releaseId': 'push_ups-remote-1',
  'activityId': 'push_ups',
  'engineType': engine,
  'requiredLandmarks': ['leftHip', 'rightHip', 'leftWrist', 'rightWrist'],
  'stableFrames': 1,
};

void main() {
  test('strict parser rejects unknown engines and unbounded thresholds', () {
    expect(
      () => RemoteVerifierSpec.fromJson({
        ..._base('unknown_v1'),
        'holdRules': [],
      }),
      throwsA(isA<RemoteVerifierSpecException>()),
    );
    expect(
      () => RemoteVerifierSpec.fromJson({
        ..._base('hold_v1'),
        'holdRules': [
          {'point': 'leftHip', 'axis': 'y', 'operator': 'lte', 'threshold': 2},
        ],
      }),
      throwsA(isA<RemoteVerifierSpecException>()),
    );
  });

  test('state machine counts only a stable active-to-start cycle', () {
    final json = _base('state_machine_v1')
      ..['startRules'] = [
        {'point': 'leftHip', 'axis': 'y', 'operator': 'lte', 'threshold': 0.4},
      ]
      ..['activeRules'] = [
        {'point': 'leftHip', 'axis': 'y', 'operator': 'gte', 'threshold': 0.6},
      ];
    final runtime = createRemoteVerifierRuntime(
      spec: RemoteVerifierSpec.fromJson(json),
      target: 2,
    );
    final t = DateTime(2026, 9, 17);
    runtime.start();
    expect(runtime.update(_frame(at: t)).state, RemoteRuntimeState.ready);
    expect(
      runtime
          .update(
            _frame(at: t.add(const Duration(milliseconds: 30)), hipY: 0.7),
          )
          .state,
      RemoteRuntimeState.tracking,
    );
    final accepted = runtime.update(
      _frame(at: t.add(const Duration(milliseconds: 60))),
    );
    expect(accepted.state, RemoteRuntimeState.repAccepted);
    expect(accepted.count, 1);
  });

  test(
    'alternating runtime flips sides and hold runtime uses monotonic timestamps',
    () {
      final alternating = _base('alternating_rep_v1')
        ..['leftRules'] = [
          {
            'point': 'leftWrist',
            'axis': 'y',
            'operator': 'lte',
            'threshold': 0.3,
          },
        ]
        ..['rightRules'] = [
          {
            'point': 'rightWrist',
            'axis': 'y',
            'operator': 'lte',
            'threshold': 0.3,
          },
        ];
      final alt = createRemoteVerifierRuntime(
        spec: RemoteVerifierSpec.fromJson(alternating),
        target: 2,
      );
      final t = DateTime(2026, 9, 17);
      expect(alt.update(_frame(at: t, leftWristY: 0.2)).count, 1);
      expect(
        alt
            .update(
              _frame(
                at: t.add(const Duration(milliseconds: 30)),
                rightWristY: 0.2,
              ),
            )
            .count,
        2,
      );

      final hold = _base('hold_v1')
        ..['holdRules'] = [
          {
            'point': 'leftHip',
            'axis': 'y',
            'operator': 'lte',
            'threshold': 0.5,
          },
        ];
      final holdRuntime = createRemoteVerifierRuntime(
        spec: RemoteVerifierSpec.fromJson(hold),
        target: 1,
      );
      expect(
        holdRuntime.update(_frame(at: t)).state,
        RemoteRuntimeState.holdProgress,
      );
      final done = holdRuntime.update(
        _frame(at: t.add(const Duration(seconds: 1))),
      );
      expect(done.state, RemoteRuntimeState.completed);
      expect(done.elapsedMs, 1000);
    },
  );
}
