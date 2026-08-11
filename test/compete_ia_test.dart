import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
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

/// Creates a camera-verifiable race with [participantCount] participants.
/// The first participant is always the test user with [progressPercent].
/// Title must contain a supported activity keyword (Pushup, Squat, etc.) for
/// the camera verification resolver to mark it as camera-verifiable.
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
  // Cycle through supported activity keywords so every race is
  // camera-verifiable via title inference.
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
  group('Compete IA (Variant B)', () {
    testWidgets(
      '1 active race: Continue competing shows, no Your races section',
      (tester) async {
        await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
        await tester.pumpAndSettle();

        // Continue competing card should show the race title.
        expect(find.text('Pushup Race'), findsOneWidget);
        // No "Your races" section label (only 1 race, it's in Continue competing).
        expect(find.textContaining('Your races'), findsNothing);
      },
    );

    testWidgets(
      '5 active races: Continue competing + 3 capped rows + See all',
      (tester) async {
        await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
        await tester.pumpAndSettle();

        // Continue competing shows first race.
        expect(find.textContaining('Race 1'), findsOneWidget);
        // "Your races" section with 4 remaining (5 - 1 featured).
        expect(find.textContaining('Your races'), findsOneWidget);
        // 3 capped rows visible (Race 2, Race 3, Race 4).
        expect(find.textContaining('Race 2'), findsOneWidget);
        expect(find.textContaining('Race 3'), findsOneWidget);
        expect(find.textContaining('Race 4'), findsOneWidget);
        // Race 5 should NOT be visible (capped at 3).
        expect(find.textContaining('Race 5'), findsNothing);
        // "See all" should be visible.
        expect(find.text('See all'), findsOneWidget);
      },
    );

    testWidgets('40 active races: initial list capped at 3', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(40))));
      await tester.pumpAndSettle();

      // Continue competing shows first race.
      expect(find.textContaining('Race 1'), findsOneWidget);
      // 3 capped rows visible.
      expect(find.textContaining('Race 2'), findsOneWidget);
      expect(find.textContaining('Race 3'), findsOneWidget);
      expect(find.textContaining('Race 4'), findsOneWidget);
      // Race 5 should NOT be visible.
      expect(find.textContaining('Race 5'), findsNothing);
      // "See all" should be visible.
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('See all expands to show all remaining rows', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();

      // Initially Race 5 is hidden.
      expect(find.textContaining('Race 5'), findsNothing);

      // Tap "See all".
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();

      // Now Race 5 should be visible.
      expect(find.textContaining('Race 5'), findsOneWidget);
      // "Show less" should be visible.
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('Show less collapses back to capped list', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();

      // Expand.
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Race 5'), findsOneWidget);

      // Collapse.
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();

      // Race 5 should be hidden again.
      expect(find.textContaining('Race 5'), findsNothing);
      // "See all" should be visible again.
      expect(find.text('See all'), findsOneWidget);
    });

    testWidgets('loading state preserved', (tester) async {
      await tester.pumpWidget(_buildApp(_PendingRaceRepo()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty state preserved', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(find.text('No races yet.'), findsOneWidget);
    });

    testWidgets('error state preserved with friendly copy', (tester) async {
      await tester.pumpWidget(_buildApp(_ThrowRaceRepo()));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text('Internal Server Error'), findsNothing);
      expect(find.text("Couldn't load your races."), findsOneWidget);
    });

    testWidgets('no per-row Verify buttons on race rows', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();

      // The old design had "Verify" text buttons on every row.
      // The new design should NOT have any "Verify" text on race rows.
      expect(find.text('Verify'), findsNothing);
    });

    testWidgets('Start race and Join buttons present in compact header', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();

      expect(find.text('Start race'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('small viewport (375x667) does not overflow', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(10))));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Waiting for crew summary row shows count', (tester) async {
      // Races with 1 participant (waiting for crew).
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

      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(find.textContaining('2 races need crew'), findsOneWidget);
    });

    testWidgets('Finished summary row shows count', (tester) async {
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

      expect(find.text('Finished'), findsOneWidget);
      expect(find.textContaining('1 race'), findsWidgets);
    });
  });
}
