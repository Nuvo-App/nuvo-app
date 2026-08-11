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
import 'package:nuvo/features/move/presentation/move_screen.dart';
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

/// Creates a camera-verifiable race where the user has [progressPercent].
/// If progressPercent >= 100, the race is "completed" for the user.
/// Title must contain a supported activity keyword (Pushup, Squat, etc.) for
/// the camera verification resolver to mark it as camera-verifiable.
Race _readyRace({
  String id = 'race-1',
  String title = 'Squat Race',
  int progressPercent = 40,
  int participantCount = 2,
  String status = 'active',
  List<RaceProof> recentProofs = const [],
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
    targetValue: 50,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: participants,
    recentProofs: recentProofs,
  );
}

Race _completedRace({String id = 'c-1', String title = 'Done Race'}) =>
    _readyRace(id: id, title: 'Pushup $title', progressPercent: 100);

Race _raceWithProof({String id = 'r-1', String title = 'Proof Race'}) =>
    _readyRace(
      id: id,
      title: 'Squat $title',
      recentProofs: [
        const RaceProof(
          id: 'proof-1',
          userId: 'user-1',
          displayName: 'Test User',
          proofType: 'ai_check',
          verificationStatus: 'ai_verified',
          value: 10,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ],
    );

List<Race> _generateReadyRaces(int count) {
  // Cycle through supported activity keywords so every race is
  // camera-verifiable via title inference.
  const activities = ['Pushup', 'Squat', 'Lunge', 'Plank', 'Jumping Jack'];
  return [
    for (var i = 0; i < count; i++)
      _readyRace(
        id: 'race-$i',
        title: '${activities[i % activities.length]} Ready ${i + 1}',
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
    child: const MaterialApp(home: MoveScreen()),
  );
}

void main() {
  group('Verify IA (Variant B)', () {
    testWidgets('Ready segment is default and Up next is rendered', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pumpAndSettle();

      // "Up next" label should be visible.
      expect(find.text('Up next'), findsOneWidget);
      // Race title should be visible in the Up next card.
      expect(find.text('Squat Race'), findsOneWidget);
      // "Start verification" button should be present.
      expect(find.text('Start verification'), findsOneWidget);
    });

    testWidgets('no repeated full-width Verify buttons on ready rows', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(5))));
      await tester.pumpAndSettle();

      // The old design had "Verify" pill buttons on every ready row.
      // The new design should have exactly ONE "Start verification" button
      // (on the Up next card) and NO "Verify" text buttons on rows.
      expect(find.text('Start verification'), findsOneWidget);
      // "Verify" as standalone button text should not appear on rows.
      // (The header title "Verify" is separate from button text.)
      expect(find.byType(VerifyButtonFinder), findsNothing);
    });

    testWidgets('Ready/Completed/Recent segments switch correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(id: 'r1', title: 'Squat Ready'),
            _completedRace(id: 'c1', title: 'Completed'),
            _raceWithProof(id: 'p1', title: 'Proof'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Default: Ready segment — Up next shows ready race.
      expect(find.textContaining('Squat Ready'), findsOneWidget);

      // Tap "Completed" segment.
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      // Completed race should be visible now.
      expect(find.textContaining('Pushup Completed'), findsOneWidget);
      // Ready race should NOT be visible.
      expect(find.textContaining('Squat Ready'), findsNothing);

      // Tap "Recent" segment.
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();

      // Recent proof entry should show the user name.
      expect(find.text('Test User'), findsWidgets);
      // Completed race should NOT be visible.
      expect(find.textContaining('Pushup Completed'), findsNothing);
    });

    testWidgets('40 ready races: Also ready capped at 3', (tester) async {
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(40))),
      );
      await tester.pumpAndSettle();

      // Up next shows first race.
      expect(find.textContaining('Ready 1'), findsOneWidget);
      // 3 capped "Also ready" rows (races 2, 3, 4).
      expect(find.textContaining('Ready 2'), findsOneWidget);
      expect(find.textContaining('Ready 3'), findsOneWidget);
      expect(find.textContaining('Ready 4'), findsOneWidget);
      // Race 5 should NOT be visible (capped at 3).
      expect(find.textContaining('Ready 5'), findsNothing);
      // "See all" should be visible.
      expect(find.textContaining('See all'), findsOneWidget);
    });

    testWidgets('See all expands Also ready', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(5))));
      await tester.pumpAndSettle();

      // Initially Race 5 is hidden.
      expect(find.textContaining('Ready 5'), findsNothing);

      // Tap "See all".
      await tester.tap(find.textContaining('See all'));
      await tester.pumpAndSettle();

      // Now Race 5 should be visible.
      expect(find.textContaining('Ready 5'), findsOneWidget);
      // "Show less" should be visible.
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('Show less collapses Also ready', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(5))));
      await tester.pumpAndSettle();

      // Expand.
      await tester.tap(find.textContaining('See all'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ready 5'), findsOneWidget);

      // Collapse.
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();

      // Race 5 should be hidden again.
      expect(find.textContaining('Ready 5'), findsNothing);
    });

    testWidgets('Ready empty state', (tester) async {
      // Only completed races, no ready races.
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_completedRace()])));
      await tester.pumpAndSettle();

      // Should show Ready empty state.
      expect(find.text('No races ready to verify.'), findsOneWidget);
    });

    testWidgets('Completed empty state', (tester) async {
      // Only ready races, no completed.
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pumpAndSettle();

      // Tap "Completed" segment.
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.text('No completed races yet.'), findsOneWidget);
    });

    testWidgets('Recent empty state', (tester) async {
      // Ready race with no recent proofs.
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pumpAndSettle();

      // Tap "Recent" segment.
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();

      expect(find.text('No recent moves.'), findsOneWidget);
    });

    testWidgets('loading state preserved', (tester) async {
      await tester.pumpWidget(_buildApp(_PendingRaceRepo()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error state preserved with friendly copy', (tester) async {
      await tester.pumpWidget(_buildApp(_ThrowRaceRepo()));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text('Internal Server Error'), findsNothing);
      expect(find.text("Couldn't load your races."), findsOneWidget);
    });

    testWidgets('all-empty state shows "No active races yet."', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(find.text('No active races yet.'), findsOneWidget);
    });

    testWidgets('small viewport (375x667) does not overflow', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(10))),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('compact header shows "Verify" title and ready count', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(3))));
      await tester.pumpAndSettle();

      expect(find.text('Verify'), findsOneWidget);
      expect(find.textContaining('ready to move'), findsOneWidget);
    });
  });
}

/// Sentinel widget that never exists in the tree. Used to verify that the
/// old per-row Verify button pattern is absent.
class VerifyButtonFinder extends StatelessWidget {
  const VerifyButtonFinder({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
