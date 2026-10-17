// loadRaces single-flight: non-forced callers share the in-flight request, but
// a forced caller (e.g. right after joining via an invite) must not be handed
// a pre-join response — exactly one follow-up fetch is queued for it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

class _GatedRepo extends RaceRepository {
  _GatedRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  final calls = <Completer<List<Race>>>[];

  @override
  Future<List<Race>> getRaces() {
    final c = Completer<List<Race>>();
    calls.add(c);
    return c.future;
  }
}

Race _race(String id) => Race(
  id: id,
  creatorId: 'u',
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

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('non-forced callers dedupe onto the in-flight request', () async {
    final repo = _GatedRepo();
    final c = RaceController(repo);
    final a = c.loadRaces(force: false);
    final b = c.loadRaces(force: false);
    expect(repo.calls, hasLength(1));
    repo.calls[0].complete([_race('a')]);
    await Future.wait([a, b]);
    expect(repo.calls, hasLength(1));
  });

  test('forced load during an in-flight request queues exactly one follow-up',
      () async {
    final repo = _GatedRepo();
    final c = RaceController(repo);
    final first = c.loadRaces(force: false);
    final f1 = c.loadRaces(force: true);
    final f2 = c.loadRaces(force: true);
    final f3 = c.loadRaces(force: true);
    expect(repo.calls, hasLength(1));

    // The pre-join response lands...
    repo.calls[0].complete([_race('pre')]);
    await first;
    await _pump();
    // ...and a single follow-up fetch starts for all forced callers.
    expect(repo.calls, hasLength(2));
    repo.calls[1].complete([_race('pre'), _race('joined')]);
    await Future.wait([f1, f2, f3]);
    expect(c.state.races.map((r) => r.id), ['pre', 'joined']);
    expect(repo.calls, hasLength(2));
  });

  test('a failed in-flight request still gets the forced follow-up', () async {
    final repo = _GatedRepo();
    final c = RaceController(repo);
    final first = c.loadRaces(force: false);
    final forced = c.loadRaces(force: true);
    repo.calls[0].completeError(const ApiException(500, 'boom'));
    try {
      await first;
    } catch (_) {}
    await _pump();
    expect(repo.calls, hasLength(2));
    repo.calls[1].complete([_race('x')]);
    await forced;
    expect(c.state.races.single.id, 'x');
  });

  test('clearRaces drops a queued follow-up', () async {
    final repo = _GatedRepo();
    final c = RaceController(repo);
    final first = c.loadRaces(force: false);
    final forced = c.loadRaces(force: true);
    c.clearRaces();
    repo.calls[0].complete([_race('old')]);
    await first;
    await forced;
    await _pump();
    expect(repo.calls, hasLength(1));
    expect(c.state.races, isEmpty);
  });
}
