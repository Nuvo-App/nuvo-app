// The request pipeline around AI Motion Proof submit (doc 22 §5.6, P3–P8):
// retries with a stable clientSubmissionId, sessionResult on /proof, a
// non-blocking `complete`, and the optimistic board (patch -> reconcile /
// rollback, never persisted).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

Map<String, dynamic> _rawRace({int me = 10, int rival = 14, int third = 3}) => {
  'id': 'r1',
  'creatorId': 'u-rival',
  'title': 'Pushup race',
  'targetValue': 100,
  'format': 'first_to_goal',
  'participants': [
    {
      'id': 'p1',
      'userId': 'u-me',
      'displayName': 'Me',
      'progressValue': me,
      'progressPercent': me,
      'rank': 2,
      'joinedAt': '2026-01-01T00:00:00Z',
    },
    {
      'id': 'p2',
      'userId': 'u-rival',
      'displayName': 'Rival',
      'progressValue': rival,
      'progressPercent': rival,
      'rank': 1,
      'joinedAt': '2026-01-01T00:00:01Z',
    },
    {
      'id': 'p3',
      'userId': 'u-third',
      'displayName': 'Third',
      'progressValue': third,
      'progressPercent': third,
      'rank': 3,
      'joinedAt': '2026-01-01T00:00:02Z',
    },
  ],
};

Race _race({int me = 10}) => Race.fromJson(_rawRace(me: me));

const _result = AiMotionResult(
  activity: AiMotionActivity.squats,
  targetReps: 20,
  detectedReps: 8,
  confidence: 0.9,
  verificationStatus: 'ai_verified',
  verificationSummary: 'ok',
  framesAnalyzed: 100,
  validPoseFrames: 90,
  durationMs: 5000,
  validatorVersion: 'v1',
);

class _Store extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'token';
}

/// Records every proof/session call; failures are scripted per call.
class _FakeApi extends RaceApi {
  _FakeApi() : super(client: MockClient((_) async => http.Response('{}', 200)));

  final List<String> calls = [];
  final List<String> submissionIds = [];
  final List<ProofSessionResult?> sessionResults = [];
  final List<Object> proofScript = []; // exception to throw, consumed in order
  final List<Object> completeScript = [];
  Race response = _race(me: 18);

  @override
  Future<Race> submitAiMotionProof(
    String token,
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
    String? verificationSessionId,
    ProofSessionResult? sessionResult,
  }) async {
    calls.add('proof');
    submissionIds.add(clientSubmissionId);
    sessionResults.add(sessionResult);
    if (proofScript.isNotEmpty) throw proofScript.removeAt(0);
    return response;
  }

  @override
  Future<VerificationSession> completeVerificationSession(
    String token,
    String sessionId, {
    required String releaseId,
    required String releaseChecksum,
    required String status,
    required int resultValue,
    required double confidence,
    String? failureReason,
    String? motionSessionId,
  }) async {
    calls.add('complete');
    if (completeScript.isNotEmpty) throw completeScript.removeAt(0);
    return VerificationSession.fromJson({
      'id': sessionId,
      'status': 'completed',
    });
  }

  @override
  Future<VerificationSession> startVerificationSession(
    String token,
    String sessionId,
  ) async {
    calls.add('start');
    return VerificationSession.fromJson({'id': sessionId, 'status': 'running'});
  }
}

RaceRepository _repo(_FakeApi api) =>
    RaceRepository(api, _Store(), AuthApi())
      ..proofRetryBackoff = const [Duration.zero, Duration.zero];

/// Controller-level fake: scripted proof outcome, no network.
class _CtrlRepo extends RaceRepository {
  _CtrlRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  Object? proofError;
  Race? proofResponse;
  List<Race> listed = const [];
  List<Object> completeScript = [];
  int completeCalls = 0;

  @override
  Future<Conditional<List<Race>>> getRacesConditional({String? etag}) async =>
      Conditional(data: listed, etag: '"e1"', raw: [_rawRace()]);

  @override
  Future<Race> submitAiMotionProof(
    String raceId, {
    required AiMotionResult result,
    required String clientSubmissionId,
    required String metric,
    String? verificationSessionId,
    ProofSessionResult? sessionResult,
  }) async {
    if (proofError != null) throw proofError!;
    return proofResponse!;
  }

  @override
  Future<VerificationSession> completeVerificationSession(
    String sessionId, {
    required String releaseId,
    required String releaseChecksum,
    required String status,
    required int resultValue,
    required double confidence,
    String? failureReason,
    String? motionSessionId,
  }) async {
    completeCalls++;
    if (completeScript.isNotEmpty) throw completeScript.removeAt(0);
    return VerificationSession.fromJson({
      'id': sessionId,
      'status': 'completed',
    });
  }
}


void main() {
  group('POST /proof retries (P3)', () {
    test('timeout then success reuses the same clientSubmissionId', () async {
      final api = _FakeApi()
        ..proofScript.addAll([
          const ApiException(408, 'timed out'),
          const ApiException(0, 'offline'),
        ]);
      final race = await _repo(api).submitAiMotionProof(
        'r1',
        result: _result,
        clientSubmissionId: 'sub-1',
        metric: 'reps',
      );
      expect(race.id, 'r1');
      expect(api.submissionIds, ['sub-1', 'sub-1', 'sub-1']);
    });

    test('5xx is retried, then surfaces after 3 attempts', () async {
      final api = _FakeApi()
        ..proofScript.addAll(List.filled(5, const ApiException(503, 'down')));
      await expectLater(
        _repo(api).submitAiMotionProof(
          'r1',
          result: _result,
          clientSubmissionId: 'sub-2',
          metric: 'reps',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.calls.where((c) => c == 'proof').length, 3);
      expect(api.submissionIds.toSet(), {'sub-2'});
    });

    for (final code in [400, 409, 422]) {
      test('$code is never retried', () async {
        final api = _FakeApi()..proofScript.add(ApiException(code, 'no'));
        await expectLater(
          _repo(api).submitAiMotionProof(
            'r1',
            result: _result,
            clientSubmissionId: 'sub-3',
            metric: 'reps',
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'code', code),
          ),
        );
        expect(api.calls, ['proof']);
      });
    }
  });

  group('sessionResult (P4)', () {
    test('is sent in the /proof body with release id and checksum', () async {
      late Map<String, dynamic> body;
      final api = RaceApi(
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'race': _rawRace()}), 200);
        }),
      );
      await api.submitAiMotionProof(
        'token',
        'r1',
        result: _result,
        clientSubmissionId: 'sub-4',
        metric: 'reps',
        verificationSessionId: 'vs-1',
        sessionResult: const ProofSessionResult(
          releaseId: 'rel-1',
          releaseChecksum: 'sum-1',
          resultValue: 8,
          confidence: 0.9,
        ),
      );
      expect(body['verificationSessionId'], 'vs-1');
      expect(body['clientSubmissionId'], 'sub-4');
      expect(body['sessionResult'], {
        'releaseId': 'rel-1',
        'releaseChecksum': 'sum-1',
        'resultValue': 8,
        'confidence': 0.9,
      });
    });

    test('is omitted when not supplied (old-server body unchanged)', () async {
      late Map<String, dynamic> body;
      final api = RaceApi(
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'race': _rawRace()}), 200);
        }),
      );
      await api.submitAiMotionProof(
        'token',
        'r1',
        result: _result,
        clientSubmissionId: 'sub-5',
        metric: 'reps',
      );
      expect(body.containsKey('sessionResult'), isFalse);
    });

    test('a failed complete is retried 3 times and never throws', () async {
      final repo = _CtrlRepo()
        ..completeScript = List.filled(5, const ApiException(503, 'down'));
      final c = RaceController(repo)
        ..sessionCompleteRetryBackoff = const [Duration.zero, Duration.zero];
      final ok = await c.completeVerificationSessionWithRetry(
        'vs-1',
        releaseId: 'rel',
        releaseChecksum: 'sum',
        status: 'completed',
        resultValue: 8,
        confidence: 0.9,
      );
      expect(ok, isFalse);
      expect(repo.completeCalls, 3);
    });

    test('complete succeeds on a later try; a 4xx stops retrying', () async {
      final repo = _CtrlRepo()
        ..completeScript = [const ApiException(0, 'offline')];
      final c = RaceController(repo)
        ..sessionCompleteRetryBackoff = const [Duration.zero, Duration.zero];
      expect(
        await c.completeVerificationSessionWithRetry(
          'vs-1',
          releaseId: 'rel',
          releaseChecksum: 'sum',
          status: 'completed',
          resultValue: 8,
          confidence: 0.9,
        ),
        isTrue,
      );
      expect(repo.completeCalls, 2);

      final repo2 = _CtrlRepo()
        ..completeScript = [const ApiException(409, 'mismatch')];
      final c2 = RaceController(repo2)
        ..sessionCompleteRetryBackoff = const [Duration.zero, Duration.zero];
      expect(
        await c2.completeVerificationSessionWithRetry(
          'vs-1',
          releaseId: 'rel',
          releaseChecksum: 'sum',
          status: 'completed',
          resultValue: 8,
          confidence: 0.9,
        ),
        isFalse,
      );
      expect(repo2.completeCalls, 1);
    });
  });

  group('optimistic board (P7)', () {
    Future<(RaceController, _CtrlRepo, CacheStore)> setup() async {
      final repo = _CtrlRepo()..listed = [_race()];
      final cache = CacheStore.memory();
      final c = RaceController(repo, cache: cache, accountId: () => 'u-me');
      await c.loadRaces(force: true);
      return (c, repo, cache);
    }

    test('patches my score and recomputes ranks', () async {
      final (c, _, _) = await setup();
      final patch = c.applyOptimisticProof('r1', 'u-me', 8)!;
      final mine = c.state.races.single.participantFor('u-me')!;
      expect(mine.progressValue, 18);
      expect(mine.rank, 1); // 18 passes the rival's 14
      expect(patch.rankBefore, 2);
      expect(patch.rankAfter, 1);
      expect(patch.peoplePassed, 1);
      expect(c.hasOptimisticProof('r1'), isTrue);
    });

    test('reconciles with the returned race on success', () async {
      final (c, repo, _) = await setup();
      c.applyOptimisticProof('r1', 'u-me', 8);
      repo.proofResponse = Race.fromJson(_rawRace(me: 19));
      await c.submitAiMotionProof(
        'r1',
        result: _result,
        clientSubmissionId: 's',
        metric: 'reps',
      );
      expect(c.hasOptimisticProof('r1'), isFalse);
      expect(c.state.races.single.participantFor('u-me')!.progressValue, 19);
    });

    test('rolls back when the server rejects', () async {
      final (c, repo, _) = await setup();
      c.applyOptimisticProof('r1', 'u-me', 8);
      repo.proofError = const ApiException(
        409,
        'Verification session was already used',
      );
      await expectLater(
        c.submitAiMotionProof(
          'r1',
          result: _result,
          clientSubmissionId: 's',
          metric: 'reps',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('already used'),
          ),
        ),
      );
      expect(c.hasOptimisticProof('r1'), isFalse);
      final mine = c.state.races.single.participantFor('u-me')!;
      expect(mine.progressValue, 10);
      expect(mine.rank, 2);
    });

    test('does not write optimistic data to the disk snapshot', () async {
      final (c, repo, cache) = await setup();
      final before = await cache.read('u-me', 'races');
      expect(before, isNotNull);
      c.applyOptimisticProof('r1', 'u-me', 8);
      final during = await cache.read('u-me', 'races');
      expect(jsonEncode(during!.data), jsonEncode(before!.data));
      expect(jsonEncode(during.data), isNot(contains('"progressValue":18')));

      // Reconcile: the stale snapshot is invalidated, never replaced by the
      // optimistic race.
      repo.proofResponse = Race.fromJson(_rawRace(me: 18));
      await c.submitAiMotionProof(
        'r1',
        result: _result,
        clientSubmissionId: 's',
        metric: 'reps',
      );
      expect((await cache.read('u-me', 'races'))?.data, isNull);
    });

    test('rollback leaves a fresher server copy alone', () async {
      final (c, repo, _) = await setup();
      c.applyOptimisticProof('r1', 'u-me', 8);
      repo.listed = [Race.fromJson(_rawRace(me: 40))];
      await c.loadRaces(force: true);
      c.rollbackOptimisticProof('r1');
      expect(c.state.races.single.participantFor('u-me')!.progressValue, 40);
    });

    test('unknown race or participant patches nothing', () async {
      final (c, _, _) = await setup();
      expect(c.applyOptimisticProof('nope', 'u-me', 8), isNull);
      expect(c.applyOptimisticProof('r1', 'stranger', 8), isNull);
      expect(c.hasOptimisticProof('r1'), isFalse);
    });
  });

  group('screen request pipeline (source contract)', () {
    final src = File(
      'lib/features/races/presentation/ai_motion_proof_screen_io.dart',
    ).readAsStringSync();

    test('POST …/start is no longer called (P5)', () {
      expect(src.contains('startVerificationSession'), isFalse);
    });

    test('session mint runs in parallel with the race detail (P6)', () {
      expect(src, contains('Future.wait<Object?>'));
      expect(src, contains('_mintVerificationSession()'));
    });

    test('proof carries sessionResult and does not block on complete (P4)', () {
      expect(src, contains('sessionResult: sessionResult'));
      expect(src, contains('completeVerificationSessionWithRetry'));
    });

    test('analyze + artifact upload wait for the proof response (P8)', () {
      final analyze = src.indexOf('Future<void> _analyzeCapturedMotion()');
      expect(
        src.indexOf('await _awaitProofSettled()', analyze),
        greaterThan(analyze),
      );
    });
  });
}
