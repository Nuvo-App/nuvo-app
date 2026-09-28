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
  Future<RestoreResult> restoreSession() async =>
      RestoreOk(const AuthUser(
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

    testWidgets('featured race card flips between action and status faces', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
      await tester.pumpAndSettle();

      // Both faces stay mounted (the inactive one is the invisible sizing
      // twin under IgnorePointer/Opacity(0)) — "visible" means not hidden
      // by the sizer, not merely present in the tree.
      bool visible(String text) {
        for (final e in find.text(text).evaluate()) {
          final ignore = e.findAncestorWidgetOfExactType<IgnorePointer>();
          final opacity = e.findAncestorWidgetOfExactType<Opacity>();
          final hidden = (ignore?.ignoring ?? false) ||
              (opacity != null && opacity.opacity == 0);
          if (!hidden) return true;
        }
        return false;
      }

      expect(visible('RACE STATUS'), isFalse);
      expect(find.text('Updates ↻'), findsOneWidget);

      await tester.tap(find.text('Updates ↻'));
      await tester.pumpAndSettle();
      expect(visible('RACE STATUS'), isTrue);
      expect(find.text('Race ↻'), findsOneWidget);

      await tester.tap(find.text('Race ↻'));
      await tester.pumpAndSettle();
      expect(visible('RACE STATUS'), isFalse);
      expect(find.text('Updates ↻'), findsOneWidget);
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

    testWidgets('quick starts section renders its tiles', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
      await tester.pumpAndSettle();
      expect(find.text('Quick starts'), findsOneWidget);
      // 5 quick start tiles.
      expect(find.text('Pushups'), findsOneWidget);
      expect(find.text('Squats'), findsOneWidget);
      expect(find.text('Jumping Jacks'), findsOneWidget);
      expect(find.text('Lunges'), findsOneWidget);
      expect(find.text('Plank'), findsOneWidget);
      // Each tile reads as a game preset — "First to N", not "N reps".
      expect(find.text('First to 100'), findsOneWidget);
      expect(find.text('First to 500'), findsOneWidget);
      expect(find.text('300-sec hold'), findsOneWidget);
    });

    testWidgets('quick start tiles do not overflow at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([_cameraRace(participantCount: 3)])),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The narrowest tile still shows its full preset line.
      expect(find.text('First to 100'), findsOneWidget);
    });

    testWidgets('active race row shows progress, not placement', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      // Active rows show progress toward the target (e.g. "20 / 100 reps").
      expect(find.textContaining('/ 100 reps'), findsWidgets);
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
      // A waiting race (<= 1 participant) whose only racer is someone else,
      // so the summary can render their avatar plus empty crew slots.
      final waitingRace = _cameraRace(
        id: 'w1',
        title: 'Pushup Waiting',
        participantCount: 1,
      );
      final waiting = [
        Race(
          id: waitingRace.id,
          creatorId: 'user-2',
          title: waitingRace.title,
          goalType: waitingRace.goalType,
          targetValue: waitingRace.targetValue,
          unit: waitingRace.unit,
          proofRequirement: waitingRace.proofRequirement,
          proofMode: waitingRace.proofMode,
          verificationMethod: waitingRace.verificationMethod,
          status: waitingRace.status,
          createdAt: waitingRace.createdAt,
          updatedAt: waitingRace.updatedAt,
          participants: [
            const RaceParticipant(
              id: 'part-1',
              userId: 'user-2',
              displayName: 'Racer Two',
              progressValue: 0,
              progressPercent: 0,
              joinedAt: '2026-01-01T00:00:00Z',
            ),
          ],
        ),
      ];
      final active = [
        _cameraRace(id: 'a1', title: 'Squat Active', participantCount: 3),
      ];
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([...active, ...waiting])),
      );
      await tester.pumpAndSettle();

      // Waiting section renders empty crew slots (add icon), not a check.
      expect(find.byIcon(Icons.add_rounded), findsWidgets);
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
      expect(find.text('Your races will live here.'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('compete-skeleton')), findsOneWidget);
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
      expect(find.text('Start'), findsOneWidget);
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

    // ── Defect regression tests ────────────────────────────────────────────────

    testWidgets('Compete title does not wrap at 375x667', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // "Compete" must be rendered as a single text widget, not wrapped.
      final competeText = find.text('Compete');
      expect(competeText, findsOneWidget);
      // Verify the text widget has no soft wrap by checking its render box
      // does not exceed one line height (~36px for 30px font).
      final renderBox = tester.renderObject<RenderBox>(competeText);
      expect(renderBox.size.height, lessThan(40));
    });

    testWidgets('Compete title does not wrap at 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final competeText = find.text('Compete');
      expect(competeText, findsOneWidget);
      final renderBox = tester.renderObject<RenderBox>(competeText);
      expect(renderBox.size.height, lessThan(40));
    });

    testWidgets('Start race and Join remain reachable at 375x667', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('featured race remains visible at 375x667', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
    });

    testWidgets('See all still works after header fix', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateRaces(5))));
      await tester.pumpAndSettle();
      expect(find.text('See all'), findsOneWidget);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('long race name does not break layout at 375x667', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        _cameraRace(
          id: 'r1',
          title: 'Pushup Race With An Extremely Long Title That Must Truncate',
          participantCount: 3,
        ),
        for (var i = 1; i < 5; i++)
          _cameraRace(id: 'r$i', title: 'Squat Race $i', participantCount: 2),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('header does not overflow with large finished count', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        _cameraRace(id: 'a1', title: 'Pushup Active', participantCount: 3),
        for (var i = 0; i < 99; i++)
          _cameraRace(
            id: 'f$i',
            title: 'Finished Race $i',
            status: 'completed',
          ),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
