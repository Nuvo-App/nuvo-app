import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:nuvo/features/races/ai/object_composition_runtime.dart';
import 'package:nuvo/features/races/ai/object_composition_spec.dart';
import 'package:nuvo/features/races/ai/object_dot_producer.dart';
import 'package:nuvo/features/races/ai/object_motion_models.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/motion_capabilities.dart';

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
  test('object frame wire format contains dots, never camera pixels', () {
    final frame = _frame(DateTime.utc(2026, 9, 18), 0.6, 0.5);
    final json = frame.toJson();

    expect(json['objects'], isA<List<dynamic>>());
    expect(json.containsKey('image'), isFalse);
    expect(json.containsKey('video'), isFalse);
    expect(json.containsKey('pose'), isFalse);
  });

  test('object capabilities require an installed producer', () {
    expect(MotionCapabilities.current(), isNot(contains('object_dots_v1')));
    expect(
      MotionCapabilities.current(
        objectDotProducer: const _TestObjectDotProducer(),
      ),
      containsAll(<String>['object_dots_v1', 'object_composition_v1']),
    );
  });

  test('strict object composition parser rejects unknown fields', () {
    final json = _spec()..['unexpected'] = true;
    expect(
      () => ObjectCompositionSpec.fromJson(json),
      throwsA(isA<ObjectCompositionSpecException>()),
    );
  });

  test(
    'basketball runtime composes control, release, arc, and made basket',
    () {
      final runtime = BasketballShotRuntime(
        spec: ObjectCompositionSpec.fromJson(_spec()),
      );
      final start = DateTime.utc(2026, 9, 18);

      expect(
        runtime.update(_frame(start, 0.6, 0.5)).event,
        'waiting_for_release',
      );
      expect(
        runtime
            .update(
              _frame(start.add(const Duration(milliseconds: 100)), 0.6, 0.5),
            )
            .event,
        'ball_controlled',
      );
      expect(
        runtime
            .update(
              _frame(start.add(const Duration(milliseconds: 200)), 0.8, 0.4),
            )
            .event,
        'ball_released',
      );
      expect(
        runtime
            .update(
              _frame(start.add(const Duration(milliseconds: 300)), 0.75, 0.3),
            )
            .event,
        'ball_ascending',
      );
      expect(
        runtime
            .update(
              _frame(start.add(const Duration(milliseconds: 400)), 0.7, 0.32),
            )
            .event,
        'ball_descending',
      );
      final made = runtime.update(
        _frame(start.add(const Duration(milliseconds: 500)), 0.52, 0.51),
      );
      expect(made.state, ObjectCompositionState.made);
      expect(made.count, 1);
      expect(made.event, 'ball_through_hoop');
    },
  );

  test('basketball runtime cannot skip an undeclared graph transition', () {
    final json = _spec();
    final originalComposition = json['composition'] as Map;
    final composition = Map<String, dynamic>.from(originalComposition)
      ..['transitions'] = (originalComposition['transitions'] as List<dynamic>)
          .where((entry) => (entry as Map)['event'] != 'ball_through_hoop')
          .toList();
    json['composition'] = composition;
    final runtime = BasketballShotRuntime(
      spec: ObjectCompositionSpec.fromJson(json),
    );
    final start = DateTime.utc(2026, 9, 18);

    runtime.update(_frame(start, 0.6, 0.5));
    runtime.update(
      _frame(start.add(const Duration(milliseconds: 100)), 0.6, 0.5),
    );
    runtime.update(
      _frame(start.add(const Duration(milliseconds: 200)), 0.8, 0.4),
    );
    runtime.update(
      _frame(start.add(const Duration(milliseconds: 300)), 0.75, 0.3),
    );
    runtime.update(
      _frame(start.add(const Duration(milliseconds: 400)), 0.7, 0.32),
    );
    final blocked = runtime.update(
      _frame(start.add(const Duration(milliseconds: 500)), 0.52, 0.51),
    );

    expect(blocked.state, ObjectCompositionState.descending);
    expect(blocked.count, 0);
  });
}

class _TestObjectDotProducer implements ObjectDotProducer {
  const _TestObjectDotProducer();

  @override
  Set<String> get capabilities => const <String>{
    'object_dots_v1',
    'object_composition_v1',
  };

  @override
  Future<NuvoObjectMotionFrame?> process({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    required NuvoPoseFrame pose,
    required DateTime createdAt,
  }) async => null;
}
