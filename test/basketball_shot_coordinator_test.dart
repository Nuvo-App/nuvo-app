import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/basketball_shot_coordinator.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_artifact.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_recorder.dart';
import 'package:nuvo/features/races/ai/object_composition_runtime.dart';
import 'package:nuvo/features/races/ai/object_composition_spec.dart';
import 'package:nuvo/features/races/ai/object_motion_models.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

Map<String, dynamic> _spec() => {
  'specSchemaVersion': 1,
  'releaseId': 'basketball_shot-composition-2026.09.1',
  'activityId': 'basketball_shot',
  'engineType': 'object_composition_v1',
  'measurementType': 'repetitions',
  'requiredLandmarks': ['leftWrist', 'rightWrist'],
  'requiredObjects': [
    {'id': 'ball', 'kind': 'ball', 'minLikelihood': 0.45},
    {'id': 'hoop', 'kind': 'hoop', 'minLikelihood': 0.55},
  ],
  'composition': {
    'states': [
      'ready',
      'released',
      'ascending',
      'descending',
      'made',
      'missed',
    ],
    'transitions': [
      {'from': 'ready', 'to': 'released', 'event': 'ball_released'},
      {'from': 'released', 'to': 'ascending', 'event': 'ball_ascending'},
      {'from': 'ascending', 'to': 'descending', 'event': 'ball_descending'},
      {'from': 'descending', 'to': 'made', 'event': 'ball_through_hoop'},
      {'from': 'ascending', 'to': 'missed', 'event': 'shot_timeout'},
      {'from': 'descending', 'to': 'missed', 'event': 'shot_timeout'},
    ],
    'startState': 'ready',
    'terminalStates': ['made', 'missed'],
    'ballObjectId': 'ball',
    'hoopObjectId': 'hoop',
    'stableFrames': 2,
    'maxShotMs': 8000,
    'controlDistance': 0.22,
    'releaseDistance': 0.16,
    'minUpwardVelocity': 0.06,
    'minDownwardVelocity': 0.04,
    'hoopPlaneTolerance': 0.08,
    'madeRadius': 0.18,
  },
};

NuvoObjectMotionFrame _frame(DateTime at, double ballX, double ballY) {
  NuvoPosePoint point(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.98);
  return NuvoObjectMotionFrame(
    pose: NuvoPoseFrame(
      points: {'leftWrist': point(0.35, 0.5), 'rightWrist': point(0.6, 0.5)},
      imageWidth: 1,
      imageHeight: 1,
      createdAt: at,
    ),
    objects: {
      'ball': NuvoObjectDot(
        id: 'ball',
        kind: 'ball',
        x: ballX,
        y: ballY,
        likelihood: 0.95,
      ),
      'hoop': const NuvoObjectDot(
        id: 'hoop',
        kind: 'hoop',
        x: 0.52,
        y: 0.5,
        likelihood: 0.95,
      ),
    },
    createdAt: at,
  );
}

void main() {
  test('coordinator records dot frames and graph decisions only', () {
    final recorder = MotionSessionRecorder(
      kind: MotionSessionKind.preset,
      activityId: 'basketball_shot',
      activityTitle: 'Basketball shot',
      measurementType: 'repetitions',
    )..start();
    final coordinator = BasketballShotCoordinator(
      runtime: BasketballShotRuntime(
        spec: ObjectCompositionSpec.fromJson(_spec()),
      ),
      recorder: recorder,
    );
    final start = DateTime.utc(2026, 9, 18);

    coordinator.process(_frame(start, 0.6, 0.5));
    coordinator.process(
      _frame(start.add(const Duration(milliseconds: 100)), 0.6, 0.5),
    );
    coordinator.process(
      _frame(start.add(const Duration(milliseconds: 200)), 0.8, 0.4),
    );

    final artifact = recorder.build();
    expect(artifact.objectFrames, hasLength(3));
    expect(
      artifact.objectFrames.first.toJson(),
      containsPair('objects', isA<List>()),
    );
    expect(artifact.toJson(), isNot(contains('video')));
    expect(
      artifact.events.map((event) => event.type),
      contains('object_composition'),
    );
    expect(coordinator.state, ObjectCompositionState.released);
  });
}
