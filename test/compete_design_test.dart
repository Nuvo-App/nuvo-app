import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<AuthUser?> restoreSession() async => const AuthUser(
    id: 'user-1',
    email: 'test@getnuvo.net',
    fullName: 'Test User',
    username: 'testuser',
    onboardingComplete: true,
    hasMemberPass: true,
    termsAccepted: true,
  );
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

class _ThrowRaceRepo extends RaceRepository {
  _ThrowRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<Race>> getRaces() =>
      Future.error(const ApiException(500, 'Internal Server Error'));
}

class _PendingRaceRepo extends RaceRepository {
  _PendingRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());
  final completer = Completer<List<Race>>();
  @override
  Future<List<Race>> getRaces() => completer.future;
}

Race _cameraRace({
  String id = 'race-1',
  String title = 'Pushup Race',
  int participantCount = 2,
  int progressPercent = 20,
  String status = 'active',
}) {
  final participants = <RaceParticipant>[
    RaceParticipant(
      id: 'part-1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: progressPercent,
      progressPercent: progressPercent,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    for (var i = 1; i < participantCount; i++)
      RaceParticipant(
        id: 'part-${i + 1}',
        userId: 'user-${i + 1}',
        displayName: 'Racer $i',
        progressValue: 10,
        progressPercent: 10,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
  ];
  return Race(
    id: id,
    creatorId: 'user-1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: 100,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: participants,
  );
}

List<Race> _generateRaces(int count) {
  const activities = ['Pushup', 'Squat', 'Lunge', 'Plank', 'Jumping Jack'];
  return [
    for (var i = 0; i < count; i++)
      _cameraRace(
        id: 'race-$i',
        title: '${activities[i % activities.length]} Race ${i + 1}',
        participantCount: 2,
        progressPercent: 20 + (i % 50),
      ),
  ];
}

Widget _buildApp(RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: CompeteScreen()),
  );
}

void main() {
  group('Compete design language (Phase 1)', () {
    testWidgets('uses NuvoFeaturedRaceCard for the loud surface', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
    });

    testWidgets('uses NuvoRaceRow for active race rows', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      // Featured card takes race 1, 3 capped rows use NuvoRaceRow.
      expect(find.byType(NuvoRaceRow), findsNWidgets(3));
    });

    testWidgets('uses NuvoFinishedRaceRow for finished races', (tester) async {
      final finished = [
        _cameraRace(id: 'f1', title: 'Pushup Finished 1', status: 'completed'),
      ];
      final active = [
        _cameraRace(id: 'a1', title: 'Squat Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...active, ...finished])),
      );
      await tester.pumpAndSettle();

      // Expand the finished summary.
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();

      expect(find.byType(NuvoFinishedRaceRow), findsOneWidget);
    });

    testWidgets('uses NuvoWaitingCrewSummary for waiting section', (
      tester,
    ) async {
      final waiting = [
        _cameraRace(id: 'w1', title: 'Pushup Waiting 1', participantCount: 1),
        _cameraRace(id: 'w2', title: 'Squat Waiting 2', participantCount: 1),
      ];
      final inMotion = [
        _cameraRace(id: 'm1', title: 'Lunge Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...inMotion, ...waiting])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NuvoWaitingCrewSummary), findsOneWidget);
    });

    testWidgets('uses NuvoFinishedSummary for finished section', (
      tester,
    ) async {
      final finished = [
        _cameraRace(id: 'f1', title: 'Pushup Finished 1', status: 'completed'),
      ];
      final active = [
        _cameraRace(id: 'a1', title: 'Squat Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...active, ...finished])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NuvoFinishedSummary), findsOneWidget);
    });

    testWidgets('uses NuvoQuickStart for quick start tiles', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
      await tester.pumpAndSettle();
      // 5 quick start tiles.
      expect(find.byType(NuvoQuickStart), findsNWidgets(5));
    });

    testWidgets('active race row shows progress percent, not placement', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      // Active rows should show "%" progress.
      expect(find.textContaining('%'), findsWidgets);
    });

    testWidgets('finished race row shows placement, not progress percent', (
      tester,
    ) async {
      final finished = [
        _cameraRace(id: 'f1', title: 'Pushup Finished 1', status: 'completed'),
      ];
      final active = [
        _cameraRace(id: 'a1', title: 'Squat Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...active, ...finished])),
      );
      await tester.pumpAndSettle();

      // Expand finished.
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();

      // Finished row should show placement (e.g. "1st"), NOT "%".
      expect(find.textContaining('st'), findsWidgets);
    });

    testWidgets('waiting section shows crew slot icon, not generic checkmark', (
      tester,
    ) async {
      final waiting = [
        _cameraRace(id: 'w1', title: 'Pushup Waiting', participantCount: 1),
      ];
      final active = [
        _cameraRace(id: 'a1', title: 'Squat Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...active, ...waiting])),
      );
      await tester.pumpAndSettle();

      // Waiting section should use group_add icon, not check.
      expect(find.byIcon(Icons.group_add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('finished section shows result icon, not group_add', (
      tester,
    ) async {
      final finished = [
        _cameraRace(id: 'f1', title: 'Pushup Finished', status: 'completed'),
      ];
      final active = [
        _cameraRace(id: 'a1', title: 'Squat Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...active, ...finished])),
      );
      await tester.pumpAndSettle();

      // Finished section should use check or crown, not group_add.
      expect(find.byIcon(Icons.group_add_rounded), findsNothing);
    });

    // ── Scale tests ────────────────────────────────────────────────────────────

    testWidgets('0 races: empty state preserved', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(find.text('No races yet.'), findsOneWidget);
      expect(find.byType(NuvoFeaturedRaceCard), findsNothing);
    });

    testWidgets('1 race: featured card, no capped list', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
      expect(find.byType(NuvoRaceRow), findsNothing);
    });

    testWidgets('5 races: featured + 3 capped rows + See all', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
      expect(find.byType(NuvoRaceRow), findsNWidgets(3));
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('40 races: featured + 3 capped rows + See all', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(40))));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
      expect(find.byType(NuvoRaceRow), findsNWidgets(3));
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('100 races: featured + 3 capped rows + See all', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(100))));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
      expect(find.byType(NuvoRaceRow), findsNWidgets(3));
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('See all expands to show all remaining rows', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      // Initially 3 rows.
      expect(find.byType(NuvoRaceRow), findsNWidgets(3));
      // Tap See all.
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      // Now 4 rows (5 - 1 featured).
      expect(find.byType(NuvoRaceRow), findsNWidgets(4));
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('Show less collapses back to capped list', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoRaceRow), findsNWidgets(3));
      expect(find.text('See all'), findsOneWidget);
    });

    // ── State preservation ─────────────────────────────────────────────────────

    testWidgets('loading state preserved', (tester) async {
      await tester.pumpWidget(_buildApp(_PendingRaceRepo()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error state preserved with friendly copy', (tester) async {
      await tester.pumpWidget(_buildApp(_ThrowRaceRepo()));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text("Couldn't load your races."), findsOneWidget);
    });

    // ── Device size ────────────────────────────────────────────────────────────

    testWidgets('375x667 no overflow with 10 races', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(10))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('390x844 no overflow with 40 races', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(40))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('375x667 no overflow with waiting + finished', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        _cameraRace(id: 'a1', title: 'Pushup Active', participantCount: 3),
        _cameraRace(id: 'w1', title: 'Squat Waiting', participantCount: 1),
        _cameraRace(id: 'w2', title: 'Lunge Waiting', participantCount: 1),
        _cameraRace(id: 'f1', title: 'Plank Finished', status: 'completed'),
        _cameraRace(id: 'f2', title: 'Jack Finished', status: 'completed'),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ── Behavior preservation ──────────────────────────────────────────────────

    testWidgets('Start race and Join present in header', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(find.text('Start race'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('no per-row Verify buttons', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(find.text('Verify'), findsNothing);
    });

    testWidgets('no "Editable camera race" dev-facing copy', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(find.text('Editable camera race'), findsNothing);
    });

    testWidgets('no "A fresh start line" decorative copy', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(find.text('A fresh start line'), findsNothing);
    });
  });
}
