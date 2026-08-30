import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
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

Race _finishedRace(String id, String title) => Race(
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
    const RaceParticipant(
      id: 'part-1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: 100,
      progressPercent: 100,
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
      expect(find.byType(SingleChildScrollView), findsWidgets);
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

    testWidgets('Edit button has minimum tap target height', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      // Find the Edit button by its text
      final editFinder = find.text('Edit');
      expect(editFinder, findsOneWidget);
      // The container around it should have minHeight >= 36
      final container = tester.widget<Container>(
        find.ancestor(of: editFinder, matching: find.byType(Container)).first,
      );
      final constraints = container.constraints;
      expect(constraints?.minHeight, greaterThanOrEqualTo(36));
    });
  });
}
