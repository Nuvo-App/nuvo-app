import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/core/widgets/nuvo_toggle.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

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

Race _activeRace(String id, String title,
        {int myProgress = 18, int opponentProgress = 41, int target = 50}) =>
    Race(
      id: id,
      creatorId: 'user-1',
      title: title,
      goalType: 'first_to_goal',
      targetValue: target,
      unit: 'reps',
      proofRequirement: 'ai_check',
      proofMode: 'ai_check',
      verificationMethod: 'camera_pose',
      status: 'active',
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
        RaceParticipant(
          id: 'part-op',
          userId: 'user-2',
          displayName: 'Noah Williams',
          progressValue: opponentProgress,
          progressPercent: (opponentProgress / target * 100).round(),
          joinedAt: '2026-01-01T00:00:00Z',
        ),
      ],
    );

Race _finishedRace(String id, String title,
        {int myProgress = 100, int? opponentProgress}) => Race(
  id: id,
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'reps',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'completed',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'part-1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: myProgress,
      progressPercent: myProgress,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    if (opponentProgress != null)
      RaceParticipant(
        id: 'part-2',
        userId: 'user-2',
        displayName: 'Jules Carter',
        progressValue: opponentProgress,
        progressPercent: opponentProgress,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
  ],
);

Widget _buildApp(RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  );
}

void main() {
  group('Profile screen defects', () {
    testWidgets('content scrolls when race history exceeds screen height', (
      tester,
    ) async {
      // 20 finished races should exceed the screen height on any device.
      final races = [
        for (var i = 0; i < 20; i++)
          _finishedRace('race-$i', 'Pushup Race ${i + 1}'),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify the screen has a scrollable view.
      expect(find.byType(Scrollable), findsWidgets);
    });

    testWidgets('no overflow at 375x667 with many races', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        for (var i = 0; i < 15; i++)
          _finishedRace('race-$i', 'Pushup Race ${i + 1}'),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 390x844 with many races', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        for (var i = 0; i < 15; i++)
          _finishedRace('race-$i', 'Pushup Race ${i + 1}'),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 320x568 — active row with icon column',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        _activeRace(
          'r1',
          'Pushup Race With An Extremely Long Title That Must Wrap',
        ),
        _finishedRace('r2', 'Squat Race'),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The movement icon leads the active row even at the narrowest width.
      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
    });

    testWidgets('long race title wraps to 2 lines, does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final races = [
        _finishedRace(
          'r1',
          'Pushup Race With An Extremely Long Title That Must Wrap',
        ),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('racing now tile shows the track and my placement',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _activeRace('r1', 'First To 50 Pushups'),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.textContaining('Racing now'), findsOneWidget);
      // Me 18 vs opponent 41 — I'm #2, and the position is earned on
      // the row, not buried in a subtitle.
      expect(find.text('#2'), findsWidgets);
      expect(find.textContaining('18'), findsWidgets);
    });

    testWidgets('race at the start line stays quiet — no empty bar',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _activeRace('r1', 'First To 50 Pushups', myProgress: 0),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Start line'), findsOneWidget);
    });

    testWidgets('a win reads as achievement — gold 1ST + trophy',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _finishedRace('r1', 'First To 100 Pushups'),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('1ST'), findsOneWidget);
      // Result row trophy + Best-finish trophy — both earned, both gold.
      expect(find.byIcon(Icons.emoji_events_rounded), findsWidgets);
    });

    testWidgets('win rate shows an em-dash with no finished races',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _activeRace('r1', 'First To 50 Pushups'),
      ])));
      await tester.pumpAndSettle();
      // The strip never invents a 0% stat.
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('Racing now is a horizontal shelf; See all lists all races',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _activeRace('r1', 'First To 50 Pushups'),
        _activeRace('r2', 'First To 25 Squats',
            myProgress: 5, opponentProgress: 10, target: 25),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The shelf carries every live race as a scrollable tile — the
      // closest-to-finish leads (18/50 before 5/25). See all drops into
      // the vertical list.
      expect(find.text('First To 50 Pushups'), findsOneWidget);
      expect(find.text('First To 25 Squats'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('First To 50 Pushups'), findsOneWidget);
      expect(find.text('First To 25 Squats'), findsOneWidget);
    });

    testWidgets('featured race carries remaining-to-finish context',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _activeRace('r1', 'First To 50 Pushups'),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 18/50 → "32 reps to finish" through the canonical score formatter.
      expect(find.textContaining('to finish'), findsOneWidget);
      expect(find.textContaining('32 reps'), findsOneWidget);
    });

    testWidgets('a non-win result stays neutral — plain placement, no trophy',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _finishedRace('r1', 'First To 20 Burpees',
            myProgress: 19, opponentProgress: 20),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('2ND'), findsWidgets);
      // The result row's trophy is reserved for wins.
      expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
    });

    testWidgets('best finish surfaces the strongest canonical placement',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _finishedRace('r1', 'First To 100 Pushups'),
        _finishedRace('r2', 'First To 20 Burpees',
            myProgress: 19, opponentProgress: 20),
      ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('BEST FINISH'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('1ST · First To 100 Pushups'),
          findsOneWidget);
    });

    testWidgets('best finish hides when nothing has been earned',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([
        _activeRace('r1', 'First To 50 Pushups'),
      ])));
      await tester.pumpAndSettle();
      expect(find.text('BEST FINISH'), findsNothing);
    });

    testWidgets('controls are organized — Your Nuvo, App, Account, Legal',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final label in ['Your Nuvo', 'App', 'Account', 'Legal']) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(label), findsOneWidget);
      }
      // Real destinations only — My Nuvo, Appearance (real theme store),
      // Edit profile, sign out, legal links. 'My Nuvo'/'Member Pass' also
      // appear as identity chips, so scroll on the last match.
      for (final row in [
        'My Nuvo',
        'Member pass',
        'Notifications',
        'Appearance',
        'Edit profile',
        'Sign out',
        'Privacy Policy',
        'Terms of Service',
      ]) {
        await tester.scrollUntilVisible(
          find.text(row).last,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(row), findsWidgets);
      }
    });

    testWidgets('Appearance toggles the real theme store', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Appearance'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Light by default; the whole app re-themes on toggle.
      expect(find.text('Light'), findsOneWidget);
      await tester.tap(find.byType(NuvoToggle).first);
      await tester.pumpAndSettle();
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('Edit action is icon-only with a minimum tap target',
        (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      // The header edit action is an icon — no floating text pill.
      final editIcon = find.byIcon(Icons.edit_outlined);
      expect(editIcon, findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      // The standard header-icon hit target is 44px (same contract as Crew).
      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(of: editIcon, matching: find.byType(SizedBox)).first,
      );
      expect(sizedBox.width, greaterThanOrEqualTo(44));
      expect(sizedBox.height, greaterThanOrEqualTo(44));
    });
  });
}
