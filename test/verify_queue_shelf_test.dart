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

/// Ready-next shelf contracts: the queue below the focused hero is a
/// shallow ice shelf carrying ONE horizontal ticket carousel — never a
/// vertical list of every waiting race. The peek is the affordance, the
/// NEXT tab marks the immediate race, and See all still opens the full
/// listing. All content resolves from canonical race fields.
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
  int target = 50,
  int otherProgress = 0,
  String status = 'active',
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
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: [
      RaceParticipant(
        id: 'part-me',
        userId: 'user-1',
        displayName: 'Test User',
        progressValue: myProgress,
        progressPercent: (myProgress / target * 100).round(),
        rank: myProgress >= otherProgress ? 1 : 2,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
      RaceParticipant(
        id: 'part-other',
        userId: 'user-2',
        displayName: 'Racer Two',
        progressValue: otherProgress,
        progressPercent: (otherProgress / target * 100).round(),
        rank: myProgress >= otherProgress ? 2 : 1,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
    ],
  );
}

// Equal progress keeps the canonical closest-to-finish ordering stable —
// queued races stay in seed order, so 'Queued Race 1' is the NEXT ticket.
List<Race> _queue(int n) => [
      _race(id: 'hero', title: 'Hero Race', myProgress: 39, otherProgress: 42),
      for (var i = 0; i < n; i++)
        _race(
          id: 'q$i',
          title: 'Queued Race ${i + 1}',
          myProgress: 10,
          otherProgress: 12,
        ),
    ];

Widget _app(List<Race> races) => ProviderScope(
      overrides: [
        raceRepositoryProvider.overrideWithValue(_StubRaceRepo(races)),
        authControllerProvider.overrideWith(
          (ref) => AuthController(_FakeAuthRepo()),
        ),
      ],
      child: const MaterialApp(home: MoveScreen()),
    );

Future<void> _pump(WidgetTester tester, List<Race> races,
    {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(_app(races));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  group('Ready-next shelf', () {
    testWidgets('the shelf is a horizontal snap carousel, not a list', (
      tester,
    ) async {
      await _pump(tester, _queue(4));
      expect(find.byType(PageView), findsOneWidget);
      // The ticket slot is narrower than the viewport, so the next race's
      // title is already laid out inside the viewport — the peek itself
      // is the swipe affordance.
      final first = tester.getTopLeft(find.text('Queued Race 1'));
      final second = tester.getTopLeft(find.text('Queued Race 2'));
      expect(first.dx, lessThan(second.dx));
      expect(second.dx, lessThan(390));
    });

    testWidgets('immediate next race carries the NEXT tab', (tester) async {
      await _pump(tester, _queue(4));
      expect(find.text('NEXT'), findsOneWidget);
    });

    testWidgets('horizontal swipe reveals the next ticket', (tester) async {
      await _pump(tester, _queue(4));
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The second ticket is now the selected page — its title sits
      // inside the viewport, readable and tappable.
      final second = tester.getTopLeft(find.text('Queued Race 2'));
      expect(second.dx, lessThan(390));
    });

    testWidgets('See all opens the existing full listing', (tester) async {
      await _pump(tester, _queue(10));
      expect(find.text('See all 10'), findsOneWidget);
      await tester.tap(find.text('See all 10'));
      await tester.pumpAndSettle();
      // The carousel is gone; the board listing took its place — the
      // deepest race is a real row now.
      expect(find.byType(PageView), findsNothing);
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('40-race queue never renders vertically', (tester) async {
      await _pump(tester, _queue(40));
      // The deepest queued race is off the PageView's built pages —
      // nothing below the shelf is laid out vertically.
      expect(find.text('Queued Race 40'), findsNothing);
      expect(find.text('Queued Race 5'), findsNothing);
      expect(find.text('See all 40'), findsOneWidget);
    });

    testWidgets('single race centers one ticket, no fake peek', (
      tester,
    ) async {
      await _pump(tester, _queue(1));
      expect(find.byType(PageView), findsNothing);
      expect(find.text('Queued Race 1'), findsOneWidget);
      expect(find.text('NEXT'), findsOneWidget);
    });

    testWidgets('canonical lane lives on every ticket', (tester) async {
      await _pump(tester, _queue(2));
      // Both pages' rows build the compact canonical track.
      expect(find.byType(AnimatedScale), findsWidgets);
      expect(find.text('Queued Race 2'), findsOneWidget);
    });
  });
}
