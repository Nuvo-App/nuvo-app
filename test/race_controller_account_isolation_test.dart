// Regression test for the cross-account state leak fixed in RaceController:
// a getRaces() request started before sign-out could still be in flight when
// clearRaces() resets state for the *next* session, and its late response
// would silently overwrite the new session with the previous account's
// races. RaceController._generation guards against this — see
// docs/agents/18-data-freshness-contract.md and the matching guards in
// ArenaController/CrewController/NotificationController.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

/// Repo whose getRaces() only resolves when the test tells it to.
class _PendingRaceRepo extends RaceRepository {
  _PendingRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  final completer = Completer<List<Race>>();

  @override
  Future<List<Race>> getRaces() => completer.future;
}

Race _race(String id, String creatorId) => Race(
  id: id,
  creatorId: creatorId,
  title: 'Race $id',
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'reps',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  group('RaceController account isolation', () {
    test('a fetch in flight across sign-out does not resurrect the previous '
        'account\'s races after clearRaces()', () async {
      final repo = _PendingRaceRepo();
      final controller = RaceController(repo);

      // User A's session starts a load...
      final load = controller.loadRaces(force: false);
      expect(controller.state.loading, isTrue);
      expect(controller.state.races, isEmpty);

      // ...then signs out before the response arrives. This must fully
      // reset state for whoever signs in next.
      controller.clearRaces();
      expect(controller.state.races, isEmpty);
      expect(controller.state.loading, isFalse);

      // User A's stale request finally resolves with User A's races.
      repo.completer.complete([_race('race-a', 'user-a')]);
      await load;
      // Let the .then continuation (which applies the result) run.
      await Future<void>.delayed(Duration.zero);

      // The cleared state must NOT have been overwritten by the late,
      // now-irrelevant response.
      expect(controller.state.races, isEmpty);
    });

    test(
      'a fetch that completes before any sign-out still applies normally',
      () async {
        final repo = _PendingRaceRepo();
        final controller = RaceController(repo);

        final load = controller.loadRaces(force: false);
        repo.completer.complete([_race('race-a', 'user-a')]);
        await load;

        expect(controller.state.races, hasLength(1));
        expect(controller.state.races.single.id, 'race-a');
      },
    );

    test(
      'a successful list refresh notifies derived surfaces such as Arena',
      () async {
        final repo = _PendingRaceRepo();
        var refreshNotifications = 0;
        final controller = RaceController(
          repo,
          onMutated: () => refreshNotifications++,
        );

        final load = controller.loadRaces(force: false);
        repo.completer.complete([_race('race-a', 'user-a')]);
        await load;

        expect(refreshNotifications, 1);
      },
    );

    test('after clearRaces(), a fresh load for the next account populates '
        'normally', () async {
      final repo = _PendingRaceRepo();
      final controller = RaceController(repo);

      final firstLoad = controller.loadRaces(force: false);
      controller.clearRaces();
      repo.completer.complete([_race('race-a', 'user-a')]);
      await firstLoad;
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.races, isEmpty);

      // User B signs in and loads fresh — this request must apply.
      final secondRepo = _PendingRaceRepo();
      final secondController = RaceController(secondRepo);
      final secondLoad = secondController.loadRaces(force: false);
      secondRepo.completer.complete([_race('race-b', 'user-b')]);
      await secondLoad;

      expect(secondController.state.races, hasLength(1));
      expect(secondController.state.races.single.id, 'race-b');
    });
  });

  group('attempt binding on submitProof', () {
    // The Worker rejects proofs to best_attempt/timed_attempt races that have
    // no open attempt ("Start an attempt before submitting a score"). The
    // controller must declare an attempt first — invisibly — so a manual
    // submit stays one obvious action.

    Race attemptRace(String format) => Race(
      id: 'race-attempt',
      creatorId: 'user-1',
      title: 'Highest score',
      goalType: 'target',
      targetValue: 100,
      unit: 'points',
      format: format,
      proofRequirement: 'manual',
      proofMode: 'manual',
      status: 'active',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    );

    test('best_attempt race declares an attempt before submitting', () async {
      final repo = _AttemptRepo(attemptRace('best_attempt'));
      final controller = RaceController(repo);
      await controller.loadRaces();

      await controller.submitProof('race-attempt', value: 95);

      expect(repo.startAttemptCalls, 1);
      expect(repo.submitProofCalls, 1);
      expect(repo.callOrder, ['attempt', 'proof']);
    });

    test('timed_attempt race declares an attempt before submitting', () async {
      final repo = _AttemptRepo(attemptRace('timed_attempt'));
      final controller = RaceController(repo);
      await controller.loadRaces();

      await controller.submitProof('race-attempt', value: 30);

      expect(repo.startAttemptCalls, 1);
      expect(repo.submitProofCalls, 1);
    });

    test('an already-open attempt (409) still submits the proof', () async {
      final repo = _AttemptRepo(attemptRace('best_attempt'))
        ..startAttemptError = const ApiException(409, 'attempt already open');
      final controller = RaceController(repo);
      await controller.loadRaces();

      await controller.submitProof('race-attempt', value: 95);

      expect(repo.submitProofCalls, 1);
    });

    test('a real startAttempt failure blocks the submission', () async {
      final repo = _AttemptRepo(attemptRace('best_attempt'))
        ..startAttemptError = const ApiException(500, 'server error');
      final controller = RaceController(repo);
      await controller.loadRaces();

      await expectLater(
        controller.submitProof('race-attempt', value: 95),
        throwsA(isA<ApiException>()),
      );
      expect(repo.submitProofCalls, 0);
    });

    test('a race absent from state (deep link) still declares an attempt', () async {
      // loadRaces is never called — the controller must fetch the race's
      // format before deciding whether an attempt is required.
      final repo = _AttemptRepo(attemptRace('best_attempt'));
      final controller = RaceController(repo);

      await controller.submitProof('race-attempt', value: 95);

      expect(repo.getRaceDetailCalls, 1);
      expect(repo.callOrder, ['attempt', 'proof']);
    });

    test('first_to_goal race submits without declaring an attempt', () async {
      final repo = _AttemptRepo(attemptRace('first_to_goal'));
      final controller = RaceController(repo);
      await controller.loadRaces();

      await controller.submitProof('race-attempt', value: 5);

      expect(repo.startAttemptCalls, 0);
      expect(repo.submitProofCalls, 1);
    });
  });
}

class _AttemptRepo extends RaceRepository {
  _AttemptRepo(this.race) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final Race race;
  final List<String> callOrder = [];
  int startAttemptCalls = 0;
  int submitProofCalls = 0;
  int getRaceDetailCalls = 0;
  ApiException? startAttemptError;

  @override
  Future<List<Race>> getRaces() async => [race];

  @override
  Future<Race> getRaceDetail(String id) async {
    getRaceDetailCalls++;
    return race;
  }

  @override
  Future<RaceAttemptResult> startAttempt(
    String raceId, {
    String? clientAttemptId,
  }) async {
    startAttemptCalls++;
    callOrder.add('attempt');
    final error = startAttemptError;
    if (error != null) throw error;
    return const RaceAttemptResult(
      attemptId: 'attempt-1',
      attemptIndex: 1,
      status: 'open',
      attemptsUsed: 1,
    );
  }

  @override
  Future<Race> submitProof(
    String raceId, {
    String proofType = 'manual',
    String? note,
    required int value,
    String? mediaObjectKey,
  }) async {
    submitProofCalls++;
    callOrder.add('proof');
    return race;
  }
}
