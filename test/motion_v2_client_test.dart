import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_client.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_models.dart';

NuvoPoseFrame _frame() => NuvoPoseFrame(
      points: {
        'leftShoulder': const NuvoPosePoint(x: 0.6, y: 0.3, z: 0, likelihood: 0.9),
        'rightHip': const NuvoPosePoint(x: 0.44, y: 0.55, z: 0, likelihood: 0.9),
      },
      imageWidth: 720,
      imageHeight: 1280,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  test('learn -> load -> update -> newRep flows through the client', () async {
    final calls = <String>[];
    final mock = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      final body = req.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(req.body) as Map<String, dynamic>;
      switch (req.url.path) {
        case '/motion-v2/learn':
          expect((body['demos'] as List).length, 3);
          return http.Response(
            jsonEncode({
              'spec': {
                'schema': 3,
                'name': 'Test Motion 001',
                'verifier': 'motion_v2',
                'encoder': 'release_action',
                'prototypes': [
                  [0.0]
                ],
                'canonical': [
                  [0.0]
                ],
                'rest_emb': [0.0],
                'accept_proto_dist': 0.3,
                'accept_traj_dist': 0.001,
                'demo_active_vel': 0.01,
                'demo_lengths': [40],
              }
            }),
            200,
          );
        case '/motion-v2/session':
          return http.Response(jsonEncode({'sessionId': 'abc123'}), 200);
        case '/motion-v2/session/abc123/frames':
          return http.Response(
            jsonEncode({
              'matched': true,
              'newRep': true,
              'count': 1,
              'confidence': 0.91,
              'progress': 1.0,
              'state': 'matched',
              'latencyMs': 82,
              'bufferFrames': 30,
              'proto_dist': 0.05,
            }),
            200,
          );
        default:
          return http.Response('{}', 404);
      }
    });

    final client = MotionV2ServiceClient(baseUrl: 'http://x', client: mock);

    final spec = await client.learn(
      movementName: 'Test Motion 001',
      demos: [
        [_frame(), _frame()],
        [_frame(), _frame()],
        [_frame(), _frame()],
      ],
    );
    expect(spec.movementName, 'Test Motion 001');
    expect(spec.verifierType, 'motion_v2');
    expect(spec.encoder, 'release_action');

    await client.load(spec);

    final r = await client.update([_frame(), _frame(), _frame(), _frame()]);
    expect(r.newRep, isTrue);
    expect(r.matched, isTrue);
    expect(r.count, 1);
    expect(r.confidence, closeTo(0.91, 1e-6));
    expect(r.state, MotionV2RuntimeState.matching);
    expect(r.inferenceLatency.inMilliseconds, 82);

    expect(calls, [
      'POST /motion-v2/learn',
      'POST /motion-v2/session',
      'POST /motion-v2/session/abc123/frames',
    ]);
  });

  test('update before load throws', () async {
    final client = MotionV2ServiceClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(() => client.update([_frame()]), throwsA(isA<MotionV2Exception>()));
  });
}
