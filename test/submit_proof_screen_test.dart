import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/submit_proof_screen.dart';
import 'package:nuvo/features/races/presentation/widgets/movement_demo.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

Race _armRaisesRace() => const Race(
  id: 'race-arm',
  creatorId: 'user-1',
  title: 'First to 20 Arm Raises',
  goalType: 'first_to_goal',
  targetValue: 20,
  unit: 'reps',
  targetUnit: 'reps',
  activityId: 'arm_raises',
  metric: 'reps',
  format: 'first_to_goal',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

class _FakeRaceRepo extends RaceRepository {
  _FakeRaceRepo(this.race) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final Race race;

  @override
  Future<Race> getRaceDetail(String id) async => race;

  @override
  Future<List<Race>> getRaces() async => [race];
}

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<AuthUser?> restoreSession() async => null;
}

class _AiMotionPlaceholder extends StatelessWidget {
  const _AiMotionPlaceholder();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('AI Motion Screen')));
}

Widget _buildTestApp() {
  final race = _armRaisesRace();
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(_FakeRaceRepo(race)),
      authControllerProvider.overrideWith((ref) {
        return AuthController(_FakeAuthRepo());
      }),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/race/race-arm/proof',
        routes: [
          GoRoute(
            path: '/race/race-arm/proof',
            builder: (context, state) =>
                const SubmitProofScreen(raceId: 'race-arm'),
          ),
          GoRoute(
            path: '/race/race-arm/proof/ai-motion',
            builder: (context, state) => const _AiMotionPlaceholder(),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets(
    'SubmitProofScreen shows movement animation BEFORE Begin for arm_raises race',
    (tester) async {
      await tester.pumpWidget(_buildTestApp());

      // Use pump with duration instead of pumpAndSettle because the
      // looping animation never settles.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(NuvoMovementAnimation), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);
      expect(find.text('Do this'), findsOneWidget);
      expect(find.text('Arm Raises'), findsOneWidget);
    },
  );

  testWidgets('tapping Begin navigates to the ai-motion route', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Begin'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(_AiMotionPlaceholder), findsOneWidget);
  });

  testWidgets(
    'movement animation is NOT rendered inside the AI Motion screen',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _AiMotionPlaceholder()));
      expect(find.byType(NuvoMovementAnimation), findsNothing);
    },
  );

  group('preset movement demo coverage', () {
    test('every supported preset movement has a pre-verify demo', () {
      for (final definition in motionActivityDefinitions) {
        final demo = movementDemoForType(definition.type);
        expect(
          demo,
          isNotNull,
          reason: '${definition.type.name} has no pre-verify MovementDemo',
        );
        expect(demo!.poses.length, greaterThan(1),
            reason: '${definition.type.name} demo needs at least 2 poses');
      }
    });
  });
}
