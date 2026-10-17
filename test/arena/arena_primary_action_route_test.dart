// Arena's primary hero action opens the proof entry directly (no Verify tab):
// camera races -> the AI Motion Proof route (behind the helper), manual races
// -> the proof chooser, races that cannot be proven now -> the race page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

const _user = AuthUser(
  id: 'user-1',
  email: 'test@getnuvo.net',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

class _AuthRepo extends AuthRepository {
  _AuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(_user);
}

class _Repo extends RaceRepository {
  _Repo() : super(RaceApi(), SecureTokenStore(), AuthApi());
}

class _SeededRaces extends RaceController {
  _SeededRaces(List<Race> races) : super(_Repo()) {
    state = RaceState(races: races);
  }
}

Race _race({
  required String id,
  required String status,
  String? activityId,
  bool camera = true,
}) => Race(
  id: id,
  creatorId: 'user-1',
  title: 'Race $id',
  goalType: 'first_to_goal',
  targetValue: 15,
  unit: 'reps',
  targetUnit: 'reps',
  activityId: activityId,
  metric: 'reps',
  proofRequirement: camera ? 'ai_check' : 'manual',
  proofMode: camera ? 'ai_check' : 'manual',
  verificationMethod: camera ? 'camera_pose' : 'manual',
  status: status,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

ArenaSnapshot _snap(String id, {bool result = false}) => ArenaSnapshot(
  mode: 'real',
  headerPulse: '1 moving',
  focusBoard: ArenaBoard(
    id: id,
    source: 'real',
    title: 'Race $id',
    progressLabel: '3 / 15 reps',
    boardContext: '',
    primaryActionLabel: 'Submit proof',
    primaryActionType: 'submit_proof',
    progressPercent: 20,
    racerCount: 1,
    isResult: result,
  ),
);

Future<List<String>> _tapSubmit(WidgetTester tester, Race race) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final visited = <String>[];
  final store = FirstUseStore.memory();
  await store.markCameraPrimerSeen();
  final router = GoRouter(
    initialLocation: '/arena',
    routes: [
      GoRoute(
        path: '/arena',
        builder: (c, s) =>
            ArenaScreen(debugSnapshot: _snap(race.id)),
      ),
      GoRoute(
        path: '/race/:id',
        builder: (c, s) {
          visited.add(s.uri.path);
          return const Scaffold(body: Text('dest'));
        },
        routes: [
          GoRoute(
            path: 'proof',
            builder: (c, s) {
              visited.add(s.uri.path);
              return const Scaffold(body: Text('dest'));
            },
            routes: [
              GoRoute(
                path: 'ai-motion',
                builder: (c, s) {
                  visited.add(s.uri.path);
                  return const Scaffold(body: Text('dest'));
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => AuthController(_AuthRepo())),
        raceControllerProvider.overrideWith((ref) => _SeededRaces([race])),
        firstUseStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Submit proof'));
  await tester.pumpAndSettle();
  return visited;
}

void main() {
  testWidgets('camera race opens the AI Motion Proof route directly', (
    tester,
  ) async {
    final v = await _tapSubmit(
      tester,
      _race(id: 'r1', status: 'active', activityId: 'push_ups'),
    );
    expect(v, ['/race/r1/proof/ai-motion']);
  });

  testWidgets('manual race opens the proof chooser', (tester) async {
    final v = await _tapSubmit(
      tester,
      _race(id: 'r2', status: 'active', camera: false),
    );
    expect(v, ['/race/r2/proof']);
  });

  testWidgets('a race that cannot be proven now opens the race page', (
    tester,
  ) async {
    final v = await _tapSubmit(
      tester,
      _race(id: 'r3', status: 'completed', activityId: 'push_ups'),
    );
    expect(v, ['/race/r3']);
  });
}
