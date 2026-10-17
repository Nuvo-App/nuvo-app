import 'dart:async';

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
  final List<int> batchLengths = [];
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
    batchLengths.add(frames.length);
    _count++; // one rep per call, deterministic
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

/// Engine whose every update() is held until the test releases it, so we can
/// feed frames "while an eval is running" deterministically.
class _GatedEngine implements MotionVerifierV2 {
  final List<List<int>> calls = []; // frame timestamps (ms) per update()
  final List<Completer<void>> _gates = [];
  final List<int> countsToReport;
  int _i = 0;
  _GatedEngine(this.countsToReport);

  @override
  Future<void> load(TaughtMotionV2Spec spec) async {}

  @override
  Future<MotionV2RuntimeResult> update(List<NuvoPoseFrame> frames) async {
    calls.add([for (final f in frames) f.createdAt.millisecondsSinceEpoch]);
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    final count =
        countsToReport[_i < countsToReport.length
            ? _i
            : countsToReport.length - 1];
    _i++;
    return MotionV2RuntimeResult(
      matched: true,
      newRep: true,
      count: count,
      confidence: 0.9,
      motionProgress: 1,
      state: MotionV2RuntimeState.matching,
      inferenceLatency: Duration.zero,
    );
  }

  /// Let the oldest held update() return.
  Future<void> release() async {
    _gates.removeAt(0).complete();
    await pumpEventQueue();
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
  points: const {'nose': NuvoPosePoint(x: 0.5, y: 0.5, z: 0, likelihood: 0.9)},
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
      target: 1,
      engine: engine,
    );
    runtime.start();
    for (var i = 0; i < 8; i++) {
      runtime.update(_frame(i));
    }
    await pumpEventQueue();
    expect(engine.loads, 1);
    // Frames buffered during engine load drain coalesced — one call of 8,
    // not two of 4 — so a lagging engine stays near real-time.
    expect(engine.batchLengths, [8]);
    expect(runtime.currentValue, 1);
    final result = runtime.customResult();
    expect(result.verifierType, motionV2VerifierType);
    expect(result.count, 1);
    expect(result.verificationStatus, 'custom_verified');
    expect(result.movementName, 'Pull Ups');
    final finish = runtime.finish();
    expect(finish.type, VerifierType.motionV2);
    expect(finish.customPoseResult!.verificationStatus, 'custom_verified');
  });

  test(
    'motion_v2 race parses, resolves camera-verifiable, creates runtime',
    () {
      const v2SpecJson = {
        'schema': 2,
        'verifier': 'motion_v2',
        'version': 1,
        'name': 'Pull Ups',
        'references': [
          {
            'proto': [0.1],
            'traj': [
              [0.1],
            ],
            'length': 90,
          },
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
    },
  );

  test(
    'remote_release carrying a motion_v2 spec resolves to the V2 runtime',
    () {
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
            {
              'proto': [0.1],
              'traj': [
                [0.1],
              ],
              'length': 90,
            },
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
    },
  );

  test(
    'engine load failure surfaces as failedRuleReason, not a crash',
    () async {
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
    },
  );

  group('queueing while an eval is running', () {
    Future<(MotionV2VerifierRuntime, _GatedEngine)> started(
      List<int> counts,
    ) async {
      final engine = _GatedEngine(counts);
      final runtime = MotionV2VerifierRuntime(
        spec: _spec(),
        target: 5,
        engine: engine,
      );
      runtime.start();
      await pumpEventQueue(); // engine loaded
      return (runtime, engine);
    }

    test(
      'frames that arrive mid-eval are queued in order, none dropped',
      () async {
        final (runtime, engine) = await started([1, 1]);
        for (var i = 0; i < 4; i++) {
          runtime.update(_frame(i));
        }
        await pumpEventQueue();
        expect(engine.calls, hasLength(1)); // first eval is now "running"

        for (var i = 4; i < 40; i++) {
          runtime.update(_frame(i)); // arrive while busy
        }
        await pumpEventQueue();
        expect(engine.calls, hasLength(1)); // still only one in flight

        await engine
            .release(); // first eval returns -> backlog goes out as ONE call
        expect(engine.calls, hasLength(2));
        expect(engine.calls[1], [for (var i = 4; i < 40; i++) i * 33]);
        await engine.release();
        await runtime.drain();
        expect(
          engine.calls.expand((c) => c).length,
          40,
        ); // every frame reached the engine
      },
    );

    test(
      'a backlog larger than the window goes out in ordered chunks',
      () async {
        final (runtime, engine) = await started([1, 1, 1]);
        for (var i = 0; i < 4; i++) {
          runtime.update(_frame(i));
        }
        await pumpEventQueue();
        for (var i = 4; i < 4 + 160; i++) {
          runtime.update(_frame(i));
        }
        await engine.release();
        expect(engine.calls[1], hasLength(75)); // capped at the matcher window
        await engine.release();
        expect(engine.calls[2], hasLength(75));
        expect(
          engine.calls[2].first,
          engine.calls[1].last + 33,
        ); // contiguous, in order
      },
    );

    test(
      'two reps landing in one eval both count and completion events cover them',
      () async {
        final (runtime, engine) = await started([1, 3]);
        for (var i = 0; i < 4; i++) {
          runtime.update(_frame(i));
        }
        await pumpEventQueue();
        for (var i = 4; i < 20; i++) {
          runtime.update(_frame(i));
        }
        await engine.release(); // eval 1 -> count 1
        await engine.release(); // eval 2 -> count 3 (two reps in one eval)
        expect(runtime.currentValue, 3);
        final result = runtime.customResult();
        expect(result.count, 3);
        // The worker rejects a proof whose completion events don't cover the value.
        expect(result.completionEvents, greaterThanOrEqualTo(result.count));
      },
    );

    test('drain pushes a short queued tail through before finishing', () async {
      final (runtime, engine) = await started([1, 2]);
      for (var i = 0; i < 4; i++) {
        runtime.update(_frame(i));
      }
      await pumpEventQueue();
      await engine.release(); // eval 1 done, engine idle
      runtime.update(_frame(4));
      runtime.update(
        _frame(5),
      ); // 2 frames: below a full batch, would sit forever
      await pumpEventQueue();
      expect(engine.calls, hasLength(1));

      final drained = runtime.drain();
      await pumpEventQueue();
      expect(engine.calls, hasLength(2));
      expect(engine.calls[1], [4 * 33, 5 * 33]);
      await engine.release();
      await drained;
      expect(runtime.currentValue, 2);
    });
  });
}
