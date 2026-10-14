import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_models.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_verifier_v2.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

class _FakeV2Engine implements MotionVerifierV2 {
  int loads = 0;
  int batches = 0;
  int _count = 0;
  bool throwOnLoad = false;

  @override
  Future<void> load(TaughtMotionV2Spec spec) async {
    loads++;
    if (throwOnLoad) throw const MotionV2Exception('engine dead');
  }

  @override
  Future<MotionV2RuntimeResult> update(List<NuvoPoseFrame> frames) async {
    batches++;
    _count++; // one rep per batch, deterministic
    return MotionV2RuntimeResult(
      matched: true,
      newRep: true,
      count: _count,
      confidence: 0.91,
      motionProgress: 1,
      state: MotionV2RuntimeState.matching,
      inferenceLatency: Duration.zero,
    );
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}
}

TaughtMotionV2Spec _spec() => const TaughtMotionV2Spec(
  json: {'verifier': 'motion_v2', 'name': 'Pull Ups'},
  movementName: 'Pull Ups',
);

NuvoPoseFrame _frame(int i) => NuvoPoseFrame(
  points: const {
    'nose': NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.9),
  },
  imageWidth: 720,
  imageHeight: 1280,
  createdAt: DateTime.fromMillisecondsSinceEpoch(i * 33),
);

void main() {
  test('motion_v2 verifier type round-trips through fromId', () {
    expect(VerifierType.fromId('motion_v2'), VerifierType.motionV2);
    expect(VerifierType.motionV2.id, 'motion_v2');
  });

  test('adapter batches frames to the engine and counts reps', () async {
    final engine = _FakeV2Engine();
    final runtime = MotionV2VerifierRuntime(
      spec: _spec(),
      target: 2,
      engine: engine,
    );
    runtime.start();
    for (var i = 0; i < 8; i++) {
      runtime.update(_frame(i));
    }
    await pumpEventQueue();
    expect(engine.loads, 1);
    expect(engine.batches, 2);
    expect(runtime.currentValue, 2);
    final result = runtime.customResult();
    expect(result.verifierType, motionV2VerifierType);
    expect(result.count, 2);
    expect(result.verificationStatus, 'custom_verified');
    expect(result.movementName, 'Pull Ups');
    final finish = runtime.finish();
    expect(finish.type, VerifierType.motionV2);
    expect(finish.customPoseResult!.verificationStatus, 'custom_verified');
  });

  test('motion_v2 race parses, resolves camera-verifiable, creates runtime', () {
    const v2SpecJson = {
      'schema': 2,
      'verifier': 'motion_v2',
      'version': 1,
      'name': 'Pull Ups',
      'references': [
        {'proto': [0.1], 'traj': [[0.1]], 'length': 90},
      ],
    };
    final race = Race.fromJson({
      'id': 'r1',
      'title': 'Pull Ups',
      'goalType': 'first_to_goal',
      'targetValue': 8,
      'metric': 'reps',
      'proofRequirement': 'ai_check',
      'verifierType': 'motion_v2',
      'verifierVersion': 1,
      'customActivityName': 'Pull Ups',
      'verifierSpec': v2SpecJson,
      'status': 'active',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });
    expect(race.isCustomVerifierRace, isTrue);
    expect(race.customMotionV2Spec, isNotNull);
    expect(race.customVerifierSpec, isNull);
    expect(race.customMotionV2Spec!.movementName, 'Pull Ups');

    final eligibility = resolveCameraVerification(race);
    expect(eligibility.isCameraVerifiable, isTrue);
    expect(eligibility.isCustomVerifier, isTrue);
    expect(eligibility.customMotionV2Spec, isNotNull);

    const resolver = VerifierRuntimeResolver();
    final resolution = resolver.resolve(
      eligibility: eligibility,
      explicitVerifierType: 'motion_v2',
    );
    expect(resolution.canCreateRuntime, isTrue);
    final runtime = resolution.createRuntime(
      target: 8,
      motionV2SpecOverride: race.customMotionV2Spec,
    );
    expect(runtime.type, VerifierType.motionV2);
    expect(runtime.targetValue, 8);
  });

  test('remote_release carrying a motion_v2 spec resolves to the V2 runtime', () {
    const releaseSpec = {
      'specSchemaVersion': 1,
      'releaseId': 'rel-v2-1',
      'activityId': 'pull_ups',
      'engineType': 'motion_v2',
      'requiredCapabilities': ['motion_v2'],
      'activity': {
        'displayName': 'Pull Ups',
        'measurementType': 'repetitions',
        'defaultTarget': 10,
        'preferredCameraView': 'front_or_angle',
        'instructions': ['Keep your whole body in frame.'],
      },
      'motionV2Spec': {
        'schema': 2,
        'verifier': 'motion_v2',
        'version': 1,
        'name': 'Pull Ups',
        'references': [
          {'proto': [0.1], 'traj': [[0.1]], 'length': 90},
        ],
      },
    };
    final race = Race.fromJson({
      'id': 'r1',
      'title': 'Pull Ups',
      'goalType': 'first_to_goal',
      'targetValue': 8,
      'metric': 'reps',
      'proofRequirement': 'ai_check',
      'verificationMethod': 'ai',
      'activityId': 'pull_ups',
      'aiActivityType': 'pull_ups',
      'verifierType': 'remote_release',
      'verifierReleaseId': 'rel-v2-1',
      'verifierSpec': releaseSpec,
      'status': 'active',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

    final eligibility = resolveCameraVerification(race);
    expect(eligibility.isCameraVerifiable, isTrue);
    expect(eligibility.isRemoteVerifier, isTrue);
    expect(eligibility.customMotionV2Spec, isNotNull);
    expect(eligibility.remoteVerifierSpec, isNull);
    expect(eligibility.movementDefinition?.title, 'Pull Ups');

    const resolver = VerifierRuntimeResolver();
    final resolution = resolver.resolve(eligibility: eligibility);
    expect(resolution.type, VerifierType.motionV2);
    expect(resolution.canCreateRuntime, isTrue);
    expect(resolution.createRuntime(target: 8).type, VerifierType.motionV2);
  });

  test('engine load failure surfaces as failedRuleReason, not a crash', () async {
    final engine = _FakeV2Engine()..throwOnLoad = true;
    final runtime = MotionV2VerifierRuntime(
      spec: _spec(),
      target: 2,
      engine: engine,
    );
    runtime.start();
    runtime.update(_frame(0));
    await pumpEventQueue();
    expect(runtime.failedRuleReason, 'engine dead');
    expect(runtime.currentValue, 0);
    expect(runtime.customResult().verificationStatus, 'custom_failed');
  });
}
