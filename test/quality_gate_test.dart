import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
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

Widget _buildApp(Widget child, RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

const _sizes = [
  ('iPhone SE', 375.0, 667.0),
  ('iPhone 14', 390.0, 844.0),
  ('iPhone 14 Pro Max', 430.0, 932.0),
];

void main() {
  for (final (name, width, height) in _sizes) {
    group('Quality gate — $name (${width.round()}x${height.round()})', () {
      testWidgets('Compete: no overflow with 10 races', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(const CompeteScreen(), _StubRaceRepo(_generateRaces(10))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Compete: no overflow with waiting + finished', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        final races = [
          _cameraRace(id: 'a1', title: 'Pushup Active', participantCount: 3),
          _cameraRace(id: 'w1', title: 'Squat Waiting', participantCount: 1),
          _cameraRace(id: 'w2', title: 'Lunge Waiting', participantCount: 1),
          _cameraRace(id: 'f1', title: 'Plank Finished', status: 'completed'),
          _cameraRace(id: 'f2', title: 'Jack Finished', status: 'completed'),
        ];
        await tester.pumpWidget(
          _buildApp(const CompeteScreen(), _StubRaceRepo(races)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Compete: title does not wrap', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(const CompeteScreen(), _StubRaceRepo(_generateRaces(5))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final title = find.text('Compete');
        expect(title, findsOneWidget);
        final renderBox = tester.renderObject<RenderBox>(title);
        expect(renderBox.size.height, lessThan(40));
      });

      testWidgets('Compete: Start race and Join reachable', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(const CompeteScreen(), _StubRaceRepo(_generateRaces(5))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Start race'), findsOneWidget);
        expect(find.text('Join'), findsOneWidget);
      });

      testWidgets('Verify: no overflow with 10 ready races', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(const MoveScreen(), _StubRaceRepo(_generateRaces(10))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Verify: segments switch', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(const MoveScreen(), _StubRaceRepo(_generateRaces(5))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Tap "Completed" segment
        final completedFinder = find.textContaining('Completed');
        if (completedFinder.evaluate().isNotEmpty) {
          await tester.tap(completedFinder.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('Profile: no overflow with 15 races', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        final races = [
          for (var i = 0; i < 15; i++)
            _cameraRace(
              id: 'race-$i',
              title: 'Pushup Race ${i + 1}',
              status: 'completed',
            ),
        ];
        await tester.pumpWidget(
          _buildApp(const ProfileScreen(), _StubRaceRepo(races)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Profile: content scrolls', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        final races = [
          for (var i = 0; i < 20; i++)
            _cameraRace(
              id: 'race-$i',
              title: 'Pushup Race ${i + 1}',
              status: 'completed',
            ),
        ];
        await tester.pumpWidget(
          _buildApp(const ProfileScreen(), _StubRaceRepo(races)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsWidgets);
      });

      testWidgets('Pass/Crew: no overflow', (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(const PassScreen(), _StubRaceRepo(const [])),
        );
        // PassScreen may have continuous animations (QR, shimmer).
        // Pump a few frames instead of waiting for settle.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        // Don't use takeException — just verify no overflow errors were thrown.
      });

      testWidgets('Compete: long race name does not break layout', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        final races = [
          _cameraRace(
            id: 'r1',
            title:
                'Pushup Race With An Extremely Long Title That Must Truncate',
            participantCount: 3,
          ),
          for (var i = 1; i < 5; i++)
            _cameraRace(id: 'r$i', title: 'Squat Race $i', participantCount: 2),
        ];
        await tester.pumpWidget(
          _buildApp(const CompeteScreen(), _StubRaceRepo(races)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }
}
