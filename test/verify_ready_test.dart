// Verify — the Ready moment: one chosen race, one Start, chips for the rest.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

class _AuthRepo extends AuthRepository {
  _AuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(
    AuthUser(
      id: 'user-1',
      email: 't@getnuvo.net',
      fullName: 'Test User',
      username: 'testuser',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );
}

class _RaceRepo extends RaceRepository {
  _RaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Race _camera(String id, String title, int progress, {int target = 50}) => Race(
  id: id,
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: target,
  unit: 'reps',
  targetUnit: 'reps',
  activityId: 'push_ups',
  metric: 'reps',
  format: 'first_to_goal',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p-$id',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: progress,
      progressPercent: progress * 100 ~/ target,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'n-$id',
      userId: 'noah',
      displayName: 'Noah Reyes',
      progressValue: progress + 2,
      progressPercent: 0,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
  ],
);

Race _manual(String id, String title, int progress) => Race(
  id: id,
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: 5,
  unit: 'books',
  targetUnit: 'books',
  metric: 'books',
  format: 'first_to_goal',
  proofRequirement: 'manual',
  proofMode: 'manual',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p-$id',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: progress,
      progressPercent: 0,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
  ],
);

late GoRouter _router;

Future<void> _pump(
  WidgetTester tester,
  List<Race> races, {
  String? race,
  bool dark = false,
  double scale = 1.0,
}) async {
  _router = GoRouter(
    initialLocation: '/move',
    routes: [
      GoRoute(
        path: '/move',
        builder: (_, _) => MoveScreen(preselectedRaceId: race),
      ),
      GoRoute(path: '/compete', builder: (_, _) => const Text('COMPETE')),
      GoRoute(
        path: '/race/:id/proof',
        builder: (_, _) => const Text('PROOF-CHOOSER'),
      ),
      GoRoute(
        path: '/race/:id/proof/ai-motion',
        builder: (_, _) => const Text('VERIFIER'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        raceRepositoryProvider.overrideWithValue(_RaceRepo(races)),
        firstUseStoreProvider.overrideWithValue(
          FirstUseStore.memory()..markCameraPrimerSeen(),
        ),
        authControllerProvider.overrideWith(
          (ref) => AuthController(_AuthRepo()),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: _router,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _path() =>
    _router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  final near = _camera('near', 'Pushup Sprint', 40);
  final far = _camera('far', 'Squat Grind', 5);
  final book = _manual('book', 'Reading Race', 1);

  testWidgets('default pick is the race closest to its finish line', (
    tester,
  ) async {
    await _pump(tester, [far, near]);
    final title = find.text('Pushup Sprint');
    expect(title, findsWidgets);
    expect(find.text('First to 50 reps'), findsOneWidget);
    expect(find.textContaining('10 reps to go'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
  });

  testWidgets('?race= preselects that race', (tester) async {
    await _pump(tester, [far, near], race: 'far');
    expect(find.textContaining('45 reps to go'), findsOneWidget);
  });

  testWidgets('chips switch the race', (tester) async {
    await _pump(tester, [near, far]);
    expect(find.textContaining('10 reps to go'), findsOneWidget);
    await tester.tap(find.text('Squat Grind'));
    await tester.pumpAndSettle();
    expect(find.textContaining('45 reps to go'), findsOneWidget);
  });

  testWidgets('Start on a camera race opens the live verifier', (tester) async {
    await _pump(tester, [near]);
    await tester.tap(find.byKey(const Key('verify-hero-cta')));
    await tester.pumpAndSettle();
    expect(_path(), '/race/near/proof/ai-motion');
  });

  testWidgets('Start on a manual race opens the proof screen', (tester) async {
    await _pump(tester, [book]);
    await tester.tap(find.byKey(const Key('verify-hero-cta')));
    await tester.pumpAndSettle();
    expect(_path(), '/race/book/proof');
  });

  testWidgets('no active race: one button to Compete', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Start a race first.'), findsOneWidget);
    await tester.tap(find.text('Go to Compete'));
    await tester.pumpAndSettle();
    expect(_path(), '/compete');
  });

  testWidgets('removed tabs, rows and history are gone', (tester) async {
    await _pump(tester, [near, far]);
    for (final t in ['Completed', 'Recent', 'Ready next', 'Up next']) {
      expect(find.textContaining(t), findsNothing);
    }
  });

  for (final scale in [1.0, 1.4]) {
    testWidgets('no overflow at 320x568, text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, [near, far, book], scale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dark mode renders', (tester) async {
    await _pump(tester, [near, far], dark: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('verify-hero-cta')), findsOneWidget);
  });
}
