import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_artifact.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_recorder.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_upload_queue.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPoseFrame _frame() => NuvoPoseFrame(
      points: const {
        'left_shoulder': NuvoPosePoint(x: 0.4, y: 0.3, z: 0, likelihood: 0.9),
      },
      imageWidth: 720,
      imageHeight: 1280,
      createdAt: DateTime.now(),
    );

void main() {
  MotionSessionRecorder recorder() => MotionSessionRecorder(
        kind: MotionSessionKind.preset,
        activityId: 'squats',
        activityTitle: 'Squat sprint',
        measurementType: 'repetitions',
        raceId: 'race-1',
        goalValue: 10,
      );

  test('recorder captures reps, state changes and the final result', () {
    final r = recorder()..start();
    r.recordFrame(_frame(),
        validatorState: 'ready', count: 0, confidence: 0.5, failedRuleReason: '');
    r.recordFrame(_frame(),
        validatorState: 'active', count: 1, confidence: 0.8, failedRuleReason: '',
        debugValues: {'kneeAngle': 92.4});
    r.recordFrame(_frame(),
        validatorState: 'active',
        count: 1,
        confidence: 0.8,
        failedRuleReason: 'depth_not_reached');
    r.finish(
        outcome: MotionSessionOutcome.failed,
        detectedValue: 1,
        confidence: 0.8,
        failedRuleReason: 'depth_not_reached');

    final a = r.build();
    expect(a.outcome, MotionSessionOutcome.failed);
    expect(a.detectedValue, 1);
    expect(a.frames.length, 3);
    expect(a.events.any((e) => e.type == 'rep_counted' && e.count == 1), isTrue);
    expect(a.events.any((e) => e.type == 'validator_state'), isTrue);
  });

  test('artifact gzip round-trips to the same JSON', () {
    final r = recorder()..start();
    r.recordFrame(_frame(),
        validatorState: 'active', count: 1, confidence: 0.9, failedRuleReason: '');
    r.finish(outcome: MotionSessionOutcome.verified, detectedValue: 1);
    final a = r.build();

    final bytes = a.toGzipBytes();
    final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)))
        as Map<String, dynamic>;
    expect(decoded, equals(a.toJson()));
    expect(decoded['schemaVersion'], kMotionSessionSchema);
    expect((decoded['result'] as Map)['outcome'], 'verified');
  });

  test('metadata carries every searchable key', () {
    final r = recorder()..start();
    r.finish(outcome: MotionSessionOutcome.incomplete);
    final m = r.build().metadata();
    for (final key in [
      'sessionId',
      'activityId',
      'raceId',
      'outcome',
      'detectedValue',
      'goalValue',
      'startedAt',
      'schemaVersion',
      'frameCount',
      'durationMs',
    ]) {
      expect(m.containsKey(key), isTrue, reason: 'missing $key');
    }
    expect(m['sessionId'], startsWith('ms_'));
  });

  test('upload queue retries a failed upload and clears it on success', () async {
    final dir = await Directory.systemTemp.createTemp('ms_queue_test');
    addTearDown(() => dir.delete(recursive: true));

    var attempts = 0;
    final q = MotionSessionUploadQueue(
      stagingDir: dir,
      upload: ({required metadata, required gzipBytes}) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
      },
    );

    final r = recorder()..start();
    r.finish(outcome: MotionSessionOutcome.failed, detectedValue: 2);
    // Point staging at a temp dir by writing the blob ourselves via the queue.
    await q.enqueue(r.build());
    // First enqueue triggers one failing attempt.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(attempts, greaterThanOrEqualTo(1));

    await q.flush(); // retry succeeds
    expect(attempts, greaterThanOrEqualTo(2));

    await q.flush(); // nothing left to send
    final settled = attempts;
    await q.flush();
    expect(attempts, settled, reason: 'successful upload should be cleared');
  });
}
