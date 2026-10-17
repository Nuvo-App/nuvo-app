import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(AuthUser(
        id: 'user-1',
        email: 'test@getnuvo.net',
        fullName: 'Test User',
        username: 'testuser',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      ));
}

class _CountingRaceRepo extends RaceRepository {
  _CountingRaceRepo(this.races)
      : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  int calls = 0;
  @override
  Future<List<Race>> getRaces() {
    calls++;
    return Future.value(races);
  }
}

class _Store extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'tok';
}

class _FailApi extends ProgressionApi {
  @override
  Future<ProgressionFetch> getProgressionConditional(
    String token, {
    String? etag,
  }) async =>
      throw const ApiException(500, 'down');
  @override
  Future<List<NuvoBadge>> getBadges(String token) async => const [];
}

class _Seeded extends ProgressionController {
  _Seeded(NuvoProgression p)
      : super(ProgressionApi(), _Store(), isPresentationDemo: () => false) {
    state = AsyncValue.data(p);
  }
  int loads = 0;
  @override
  Future<void> load({bool force = true}) async {
    loads++;
  }

  @override
  Future<List<NuvoBadge>> getBadges() async => const [];
}

Race _race(String id, String status) => Race(
      id: id,
      creatorId: 'user-1',
      title: 'Race $id',
      goalType: 'first_to_goal',
      targetValue: 50,
      unit: 'reps',
      proofRequirement: 'ai_check',
      proofMode: 'ai_check',
      verificationMethod: 'camera_pose',
      status: status,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      winnerUserId: status == 'completed' ? 'user-1' : null,
      participants: [
        RaceParticipant(
          id: 'p-$id',
          userId: 'user-1',
          displayName: 'Test User',
          progressValue: 10,
          progressPercent: 20,
          joinedAt: '2026-01-01T00:00:00Z',
        ),
      ],
    );

const _record = {
  'active': 7,
  'finished': 12,
  'wins': 9,
  'winRatePercent': 75,
};

NuvoProgression _prog({Map<String, dynamic>? record}) =>
    NuvoProgression.fromBody({
      'progression': {'level': 3},
      'record': ?record,
    });

Widget _app(RaceRepository repo, ProgressionController c) => ProviderScope(
      overrides: [
        raceRepositoryProvider.overrideWithValue(repo),
        authControllerProvider
            .overrideWith((ref) => AuthController(_FakeAuthRepo())),
        progressionControllerProvider.overrideWith((ref) => c),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );

Finder _stat(String label) => find.bySemanticsLabel(label);

void main() {
  group('ProfileRecord parsing', () {
    test('full', () {
      final p = _prog(record: _record);
      expect(p.record!.active, 7);
      expect(p.record!.finished, 12);
      expect(p.record!.wins, 9);
      expect(p.record!.winRatePercent, 75);
    });
    test('missing record is null (older server)', () {
      expect(_prog().record, isNull);
    });
    test('null winRatePercent', () {
      final r = ProfileRecord.fromJson(
        {'active': 1, 'finished': 0, 'wins': 0, 'winRatePercent': null},
      );
      expect(r.winRatePercent, isNull);
      expect(r.finished, 0);
    });
  });

  group('Profile record strip', () {
    testWidgets('shows the server record without loading races',
        (tester) async {
      final repo = _CountingRaceRepo(const []);
      await tester.pumpWidget(_app(repo, _Seeded(_prog(record: _record))));
      await tester.pumpAndSettle();
      expect(_stat('7'), findsWidgets);
      expect(_stat('9'), findsWidgets);
      expect(_stat('75%'), findsWidgets);
      expect(repo.calls, 0);
    });

    testWidgets('null winRatePercent renders an em-dash', (tester) async {
      final repo = _CountingRaceRepo(const []);
      await tester.pumpWidget(_app(
        repo,
        _Seeded(_prog(record: {
          'active': 2,
          'finished': 0,
          'wins': 0,
          'winRatePercent': null,
        })),
      ));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsWidgets);
      expect(_stat('0%'), findsNothing);
    });

    testWidgets('falls back to the races list when record is null',
        (tester) async {
      final repo = _CountingRaceRepo([
        _race('a', 'active'),
        _race('b', 'active'),
        _race('c', 'active'),
        _race('d', 'completed'),
      ]);
      await tester.pumpWidget(_app(repo, _Seeded(_prog())));
      await tester.pumpAndSettle();
      expect(_stat('100%'), findsWidgets); // 1 win / 1 finished
      expect(_stat('3'), findsWidgets); // 3 active
    });

    testWidgets('renders a record hydrated from the disk snapshot',
        (tester) async {
      final cache = CacheStore.memory();
      await cache.write('u1', 'progression', {
        'progression': {'level': 3},
        'record': _record,
      }, etag: 'W/"1"');
      final c = ProgressionController(
        _FailApi(),
        _Store(),
        cache: cache,
        accountId: () => 'u1',
      );
      await c.load();
      expect(c.state.valueOrNull?.record?.wins, 9);

      final repo = _CountingRaceRepo(const []);
      await tester.pumpWidget(_app(repo, c));
      await tester.pumpAndSettle();
      expect(_stat('75%'), findsWidgets);
      expect(repo.calls, 0);
    });

    testWidgets('pull-to-refresh skips the races reload when record exists',
        (tester) async {
      final repo = _CountingRaceRepo(const []);
      final c = _Seeded(_prog(record: _record));
      await tester.pumpWidget(_app(repo, c));
      await tester.pumpAndSettle();
      final before = c.loads;
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(c.loads, greaterThan(before));
      expect(repo.calls, 0);
    });
  });
}
