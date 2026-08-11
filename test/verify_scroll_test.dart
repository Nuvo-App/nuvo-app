import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Race _r({
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
  testWidgets(
    'Verify short content does not allow bounce scroll (ClampingScrollPhysics)',
    (tester) async {
      // Short dataset: 1 ready race — content fits in viewport, no scroll needed.
      final races = [
        _r(id: 'a1', title: 'Pushup Race', participantCount: 2, progressPercent: 20),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      tester.takeException();

      // Find the ListView and verify it uses ClampingScrollPhysics.
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(
        listView.physics,
        isA<ClampingScrollPhysics>(),
        reason:
            'Verify ListView should use ClampingScrollPhysics so short content '
            'does not bounce/overscroll.',
      );
    },
  );

  testWidgets(
    'Verify remains scrollable when content exceeds viewport',
    (tester) async {
      // Use a small viewport to force content to exceed it.
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final races = [
        for (var i = 0; i < 10; i++)
          _r(
            id: 'a$i',
            title: 'Race $i with a long name',
            participantCount: 3,
            progressPercent: 10 + i,
          ),
      ];
      await tester.pumpWidget(_buildApp(_StubRaceRepo(races)));
      await tester.pumpAndSettle();
      tester.takeException();

      // Content should exceed the small viewport.
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0),
          reason: 'Content should exceed viewport and be scrollable.');

      // Drag up to scroll.
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0),
          reason: 'Should have scrolled downward.');
    },
  );
}
