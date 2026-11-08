// S5 timed battle — gap 7 app side. The camera take's contract as pure
// state: a 3-2-1 before anything opens, a window that runs exactly
// attemptDurationSeconds and demands a finish at zero, a stable
// clientAttemptId per take, a released slot when the take is abandoned
// pre-submit, and a hard stop when the attempt limit is spent.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/domain/timed_attempt_take.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

Race _timedRace({int? attemptLimit}) => Race(
  id: 'race-timed',
  creatorId: 'user-1',
  title: 'Timed battle',
  goalType: 'target',
  unit: 'reps',
  format: 'timed_attempt',
  attemptDurationSeconds: 30,
  attemptLimit: attemptLimit,
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  test('test_gap7_timed_attempt_countdown_auto_finishes', () {
    final take = TimedAttemptTake(
      durationSeconds: 30,
      clientAttemptId: 'take-1',
    );

    // The 3-2-1 gates the window — nothing is live until the last tick.
    expect(take.countingDown, isTrue);
    expect(take.secondsRemaining, isNull);
    expect(take.tickCountdown(), isFalse, reason: '3 -> 2');
    expect(take.tickCountdown(), isFalse, reason: '2 -> 1');
    expect(take.secondsRemaining, isNull);
    expect(take.tickCountdown(), isTrue, reason: '1 -> 0 opens the window');
    expect(take.countingDown, isFalse);
    expect(take.secondsRemaining, 30);

    // The window runs exactly attemptDurationSeconds and demands a finish
    // at zero — not a tick sooner, and never twice.
    for (var i = 0; i < 29; i++) {
      expect(take.tickWindow(), isFalse, reason: 'tick $i of 30');
    }
    expect(take.secondsRemaining, 1);
    expect(take.tickWindow(), isTrue, reason: 'auto-finish at zero');
    expect(take.secondsRemaining, 0);
    expect(take.tickWindow(), isFalse, reason: 'finish fires once');

    // The clientAttemptId is minted once per take and never mutates — open
    // retries always re-present the same idempotency key.
    expect(take.clientAttemptId, 'take-1');
  });

  test('test_gap7_cancel_releases_attempt', () async {
    final repo = _AttemptRepo(_timedRace());
    final controller = RaceController(repo);

    // A take cancelled during the countdown never opened anything — no
    // release needed and nothing to cancel.
    final early = TimedAttemptTake(
      durationSeconds: 30,
      clientAttemptId: 'take-early',
    );
    expect(early.needsRelease, isFalse);

    // An open attempt with no bound proof is released on abandon — the
    // DELETE reaches the server attempt id, not the client key.
    final live = TimedAttemptTake(
      durationSeconds: 30,
      clientAttemptId: 'take-live',
    )..markOpened('server-att-1');
    expect(live.needsRelease, isTrue);
    await controller.cancelAttempt('race-timed', live.openAttemptId!);
    expect(repo.cancelledAttemptIds, ['server-att-1']);

    // Once the proof binds, the attempt is spent — a submitted attempt is
    // immutable and must never be cancelled.
    final spent = TimedAttemptTake(
      durationSeconds: 30,
      clientAttemptId: 'take-spent',
    )
      ..markOpened('server-att-2')
      ..markSubmitted();
    expect(spent.needsRelease, isFalse);
  });

  test('test_gap7_attempt_limit_blocks_start', () {
    // At/over the limit the take cannot start; below it always can; no
    // limit never blocks.
    expect(
      timedAttemptLimitReached(attemptLimit: 3, attemptsUsed: 3),
      isTrue,
    );
    expect(
      timedAttemptLimitReached(attemptLimit: 1, attemptsUsed: 5),
      isTrue,
    );
    expect(
      timedAttemptLimitReached(attemptLimit: 3, attemptsUsed: 2),
      isFalse,
    );
    expect(
      timedAttemptLimitReached(attemptLimit: 1, attemptsUsed: 0),
      isFalse,
    );
    expect(
      timedAttemptLimitReached(attemptLimit: null, attemptsUsed: 9),
      isFalse,
      reason: 'an unlimited race never blocks',
    );

    // The pre-start usage copy only exists when a limit does.
    expect(timedAttemptsUsedLabel(3, 1), '1 of 3 attempts used');
    expect(timedAttemptsUsedLabel(3, 3), '3 of 3 attempts used');
    expect(timedAttemptsUsedLabel(null, 1), '');
  });
}

/// Repo that records attempt opens and cancels — the camera take's calls
/// land here through RaceController.
class _AttemptRepo extends RaceRepository {
  _AttemptRepo(this.race) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final Race race;
  final List<String?> clientAttemptIds = [];
  final List<String> cancelledAttemptIds = [];

  @override
  Future<RaceAttemptResult> startAttempt(
    String raceId, {
    String? clientAttemptId,
  }) async {
    clientAttemptIds.add(clientAttemptId);
    return const RaceAttemptResult(
      attemptId: 'server-att-1',
      attemptIndex: 1,
      status: 'open',
      attemptsUsed: 0,
    );
  }

  @override
  Future<void> cancelAttempt(String raceId, String attemptId) async {
    cancelledAttemptIds.add(attemptId);
  }
}
