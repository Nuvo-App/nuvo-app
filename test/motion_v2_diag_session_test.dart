import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/diagnostics/motion_diagnostic_session.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'fixtures/pose_fixtures.dart';

NuvoPoseFrame _f(NuvoPoseFrame base, int ms) => NuvoPoseFrame(
      points: base.points,
      imageWidth: base.imageWidth,
      imageHeight: base.imageHeight,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: ms)),
    );

void main() {
  NuvoMotionDiagnosticSession build() {
    final demo = MotionDiagDemo(
      index: 1,
      startMs: 0,
      endMs: 1200,
      rawFrameCount: 18,
      trimmedFrameCount: 14,
      estFps: 15,
      tracking: const {'readyConfidence': 0.9, 'motionStarted': true},
      segmentation: const {'motionStartedAtMs': 400, 'trimmedFromStart': 4},
      frames: [
        for (var i = 0; i < 14; i++)
          MotionDiagFrame.fromFrames(
            tMs: i * 66,
            raw: _f(neutralStandingPose(), i * 66),
            smoothed: _f(neutralStandingPose(dx: 0.001 * i), i * 66),
            interpolated: i == 3 ? ['leftWrist'] : const [],
          ),
      ],
    );
    return NuvoMotionDiagnosticSession(
      sessionId: NuvoMotionDiagnosticSession.newId(DateTime.utc(2026, 9, 2), 'abc123'),
      timestamp: DateTime.utc(2026, 9, 2, 12),
      meta: const {
        'platform': 'ios',
        'buildMode': 'release',
        'encoder': 'release_action',
        'matcher': 'multi_reference/schema4',
      },
      teaching: [demo, demo, demo],
      selfValidation: const {
        'passed': true,
        'perDemo': [true, true, true],
        'leaveOneOut': [true, true, true],
      },
      spec: const {
        'schema': 4,
        'references': [<String, dynamic>{}, <String, dynamic>{}, <String, dynamic>{}],
        'proto_spread': 0.05,
        'traj_spread': 0.02,
        'proto_spread_max': 0.07,
        'traj_spread_max': 0.03,
        'demo_lengths': [40, 44, 42],
        'region_activity': {'right arm': 0.9, 'left leg': 0.02},
      },
      liveTest: MotionDiagLiveTest(
        startMs: 5000,
        endMs: 9000,
        finalCount: 0,
        finalAttempt: const {
          'outcome': 'failed',
          'failureCategory': 'trajectory_mismatch',
          'userFeedback': 'Move your right arm more',
        },
        matchTrace: [
          MotionDiagMatchWindow(
            tMs: 6000,
            bufferFrames: 30,
            protoDist: const [0.04, 0.09, 0.05],
            trajDist: const [0.5, 0.9, 0.6],
            votesList: const [true, false, false],
            separation: 0.22,
            motionProgress: 0.81,
            decision: 'reject',
            confidence: 0.4,
            state: 'returning',
            newRep: false,
            count: 0,
            inferenceMs: 40,
          ),
        ],
        frames: [
          for (var i = 0; i < 20; i++)
            MotionDiagFrame.fromFrames(
              tMs: 5000 + i * 66,
              raw: _f(neutralStandingPose(), i * 66),
              readiness: 'ready',
            ),
        ],
      ),
      performance: const {
        'framesReceived': 300,
        'framesProcessed': 292,
        'framesDropped': 8,
        'stages': {
          'encoder+matcher': {'p50': 38.0, 'p95': 62.0, 'max': 91.0, 'avg': 41.0}
        },
      },
    );
  }

  test('session id format', () {
    final id = NuvoMotionDiagnosticSession.newId(DateTime.utc(2026, 9, 2), 'aB3');
    expect(id, matches(RegExp(r'^MV2-20260902-[A-Z0-9]{6}$')));
  });

  test('toJson round-trips through gzip and is schema-versioned', () {
    final s = build();
    final j = s.toJson();
    expect(j['schema'], kMotionDiagSchema);
    expect(j['teaching'], hasLength(3));
    expect((j['teaching'] as List).first['frames'], hasLength(14));
    expect(j['liveTest']['matchTrace'], hasLength(1));

    final gz = s.toGzipBytes();
    final back = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
    expect(back['sessionId'], s.sessionId);
    expect(back['spec']['proto_spread'], 0.05);
    expect(back['liveTest']['finalAttempt']['failureCategory'],
        'trajectory_mismatch');
    // gzip should be a real compression win on repetitive pose data
    expect(gz.length, lessThan(utf8.encode(jsonEncode(j)).length));
  });

  test('toLogText is human-readable and names the failure + trace', () {
    final log = build().toLogText();
    expect(log, contains('NUVO MOTION V2 DIAGNOSTIC'));
    expect(log, contains('TEACHING DEMO 1'));
    expect(log, contains('SELF VALIDATION'));
    expect(log, contains('LEARNED SPEC'));
    expect(log, contains('MATCH TRACE'));
    expect(log, contains('votes=1/3'));
    expect(log, contains('trajectory_mismatch'));
    expect(log, contains('Full replayable session:'));
  });

  test('a written .json.gz is loadable (parity with replay_session.py)', () async {
    final s = build();
    final tmp = await Directory.systemTemp.createTemp('mv2diag');
    final file = File('${tmp.path}/${s.sessionId}.json.gz');
    await file.writeAsBytes(s.toGzipBytes());
    final loaded = jsonDecode(
        utf8.decode(gzip.decode(await file.readAsBytes()))) as Map<String, dynamic>;
    // the exact keys replay_session.py reads
    expect(loaded['teaching'][0]['frames'][0], contains('raw'));
    expect(loaded['liveTest']['frames'][0], contains('raw'));
    expect(loaded['meta'], contains('encoder'));
    await tmp.delete(recursive: true);
  });
}
