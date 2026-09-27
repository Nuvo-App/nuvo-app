import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

/// Verify composition contracts — the screen is a proof command center:
/// "what can I prove next" (closest-to-finish ordering), "how close am I"
/// (progress + rank + remaining in every row), "what did proof change"
/// (Won/Finished + time on Completed; +reps + rank delta + ago on Recent).
/// All copy must come from canonical race/proof fields — nothing invented.
class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async =>
      const RestoreOk(AuthUser(
    id: 'user-1',
    email: 'test@getnuvo.net',
    fullName: 'Test User',
    username: 'testuser',
    onboardingComplete: true,
    hasMemberPass: true,
    termsAccepted: true,
  ));
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Race _race({
  required String id,
  required String title,
  int myProgress = 0,
  int target = 100,
  List<int> otherProgress = const [],
  String status = 'active',
  String? winnerUserId,
  String? completedAt,
  List<RaceProof> recentProofs = const [],
}) {
  return Race(
    id: id,
    creatorId: 'user-1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: target,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    winnerUserId: winnerUserId,
    completedAt: completedAt,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: [
      RaceParticipant(
        id: 'part-me',
        userId: 'user-1',
        displayName: 'Test User',
        progressValue: myProgress,
        progressPercent: (myProgress / target * 100).round(),
        joinedAt: '2026-01-01T00:00:00Z',
      ),
      for (var i = 0; i < otherProgress.length; i++)
        RaceParticipant(
          id: 'part-$i',
          userId: 'user-${i + 2}',
          displayName: 'Racer ${i + 2}',
          progressValue: otherProgress[i],
          progressPercent: (otherProgress[i] / target * 100).round(),
          joinedAt: '2026-01-01T00:00:00Z',
        ),
    ],
    recentProofs: recentProofs,
  );
}

RaceProof _proof({
  String id = 'p1',
  int value = 10,
  String status = 'ai_verified',
  int? rankBefore,
  int? rankAfter,
  required DateTime at,
}) =>
    RaceProof(
      id: id,
      userId: 'user-1',
      displayName: 'Test User',
      proofType: 'ai_motion',
      verificationStatus: status,
      value: value,
      rankBefore: rankBefore,
      rankAfter: rankAfter,
      createdAt: at.toUtc().toIso8601String(),
    );

Widget _buildApp(RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: MoveScreen()),
  );
}

void main() {
  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Ready ordering — closest to the finish line leads', () {
    testWidgets('Up next is the race nearest its finish line', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(id: 'mid', title: 'Mid Race', myProgress: 20),
        _race(id: 'close', title: 'Close Race', myProgress: 90),
        _race(id: 'start', title: 'Start Race', myProgress: 0),
      ])));
      await tester.pumpAndSettle();

      // The hero carries the race that needs the least proof, not the
      // newest one.
      final hero = tester.widget<RaceHero>(find.byType(RaceHero));
      expect(hero.raceTitle, 'Close Race');
    });

    testWidgets('ties keep the server order', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(id: 'a', title: 'Alpha Race', myProgress: 20),
        _race(id: 'b', title: 'Bravo Race', myProgress: 20),
      ])));
      await tester.pumpAndSettle();

      final hero = tester.widget<RaceHero>(find.byType(RaceHero));
      expect(hero.raceTitle, 'Alpha Race');
    });
  });

  group('Up next hero — stakes line', () {
    testWidgets('chase copy renders when there is someone to beat', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(
          id: 'r1',
          title: 'Pushup Battle',
          myProgress: 20,
          otherProgress: [40],
        ),
      ])));
      await tester.pumpAndSettle();

      // Canonical ChaseContext copy — "Beat Racer. 20 to take #1."
      // (the opponent's display name is first-named in the copy).
      expect(find.textContaining('Beat Racer'), findsOneWidget);
    });

    testWidgets('solo race keeps canonical pace-setting copy', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(id: 'r1', title: 'Solo Squats', myProgress: 5),
      ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('Set the pace'), findsOneWidget);
    });
  });

  group('Also ready rows — real state, not settings rows', () {
    testWidgets('in-progress row carries progress, rank, and a thin track', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(id: 'up', title: 'Up Race', myProgress: 90),
        _race(
          id: 'r1',
          title: 'First To 25 Squats',
          myProgress: 12,
          target: 25,
          otherProgress: [20, 5],
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('12 / 25 reps'), findsOneWidget);
      expect(find.textContaining('#2'), findsOneWidget);
      expect(find.textContaining('13 reps left'), findsOneWidget);
      // Hero path + the row's thin track.
      expect(find.byType(RaceProgress), findsWidgets);
    });

    testWidgets('start-line row says so with the racer count', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(id: 'up', title: 'Up Race', myProgress: 90),
        _race(
          id: 'r1',
          title: 'First To 100 Mountain Climbers',
          myProgress: 0,
          otherProgress: [0, 0, 0, 0, 0, 0, 0],
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.textContaining('Start line · 8 racers'), findsOneWidget);
    });
  });

  group('Completed — consequence, not queue', () {
    testWidgets('won race says Won with finish time', (tester) async {
      final ago = DateTime.now().subtract(const Duration(hours: 3));
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(
          id: 'c1',
          title: 'Pushup Battle',
          myProgress: 50,
          target: 50,
          status: 'completed',
          winnerUserId: 'user-1',
          completedAt: ago.toUtc().toIso8601String(),
          otherProgress: [30],
        ),
      ])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Won'), findsOneWidget);
      expect(find.textContaining('3h ago'), findsOneWidget);
    });

    testWidgets('finished-but-not-won race says Finished', (tester) async {
      final ago = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(
          id: 'c1',
          title: 'Squat Race',
          myProgress: 30,
          target: 30,
          status: 'completed',
          winnerUserId: 'user-2',
          completedAt: ago.toUtc().toIso8601String(),
          otherProgress: [30],
        ),
      ])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Finished'), findsWidgets);
    });
  });

  group('Recent — proof history with consequence', () {
    testWidgets('proof row shows amount, rank move, and time', (
      tester,
    ) async {
      final at = DateTime.now().subtract(const Duration(minutes: 8));
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(
          id: 'r1',
          title: 'Pushup Battle',
          myProgress: 39,
          recentProofs: [
            _proof(rankBefore: 9, rankAfter: 8, at: at),
          ],
          otherProgress: [41],
        ),
      ])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('+10 reps'), findsOneWidget);
      expect(find.textContaining('#9 → #8'), findsOneWidget);
      expect(find.textContaining('8m ago'), findsOneWidget);
      expect(find.textContaining('Verified'), findsOneWidget);
    });

    testWidgets('proof without a rank move shows no invented delta', (
      tester,
    ) async {
      final at = DateTime.now().subtract(const Duration(minutes: 4));
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _race(
          id: 'r1',
          title: 'Lunge Race',
          myProgress: 10,
          recentProofs: [_proof(at: at)],
        ),
      ])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('+10 reps'), findsOneWidget);
      expect(find.textContaining('→'), findsNothing);
      expect(find.textContaining('4m ago'), findsOneWidget);
    });
  });

  group('Responsive', () {
    for (final width in [320.0, 390.0, 430.0]) {
      testWidgets('no overflow at ${width.round()} with a long title', (
        tester,
      ) async {
        setViewport(tester, Size(width, 844));
        await tester.pumpWidget(_buildApp(_StubRaceRepo([
          _race(id: 'up', title: 'Up Race', myProgress: 90),
          _race(
            id: 'long',
            title: 'First To 100 Mountain Climbers Regional Qualifier',
            myProgress: 41,
            otherProgress: [65, 30],
          ),
        ])));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
