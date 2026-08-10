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

// ── Test fixtures ─────────────────────────────────────────────────────────────

/// All preset movements that must show a pre-verify demo.
const _presetCases = <(String id, String title, String unit)>[
  ('push_ups', 'First to 15 Pushups', 'reps'),
  ('squats', 'First to 25 Squats', 'reps'),
  ('jumping_jacks', 'First to 30 Jumping Jacks', 'reps'),
  ('lunges', 'First to 20 Lunges', 'reps'),
  ('plank_hold', 'First to 60 Plank Seconds', 'seconds'),
  ('high_knees', 'First to 40 High Knees', 'reps'),
  ('arm_raises', 'First to 20 Arm Raises', 'reps'),
  ('sumo_squats', 'First to 20 Sumo Squats', 'reps'),
  ('side_lunges', 'First to 16 Side Lunges', 'reps'),
  ('deep_squats', 'First to 15 Deep Squats', 'reps'),
  ('squat_jacks', 'First to 15 Squat Jacks', 'reps'),
  ('jump_squats', 'First to 15 Jump Squats', 'reps'),
  ('lunge_jumps', 'First to 15 Lunge Jumps', 'reps'),
];

Race _raceFor(String activityId, String title, String unit) => Race(
  id: 'race-test',
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: 15,
  unit: unit,
  targetUnit: unit,
  activityId: activityId,
  metric: unit,
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

Widget _buildTestApp(Race race) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(_FakeRaceRepo(race)),
      authControllerProvider.overrideWith((ref) {
        return AuthController(_FakeAuthRepo());
      }),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/race/race-test/proof',
        routes: [
          GoRoute(
            path: '/race/race-test/proof',
            builder: (context, state) =>
                const SubmitProofScreen(raceId: 'race-test'),
          ),
          GoRoute(
            path: '/race/race-test/proof/ai-motion',
            builder: (context, state) => const _AiMotionPlaceholder(),
          ),
        ],
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SubmitProofScreen pre-verify demo for all 13 presets', () {
    for (final (id, title, unit) in _presetCases) {
      testWidgets(
        '$id shows NuvoMovementAnimation BEFORE Begin (no auto-skip)',
        (tester) async {
          final race = _raceFor(id, title, unit);
          await tester.pumpWidget(_buildTestApp(race));

          // Pump a few frames to let the async race load + animation start.
          // The looping animation never settles, so use pump with duration.
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));

          // The pre-verify animation must be visible.
          expect(
            find.byType(NuvoMovementAnimation),
            findsOneWidget,
            reason: '$id should show NuvoMovementAnimation before Begin',
          );

          // "Do this" label must be present.
          expect(
            find.text('Do this'),
            findsOneWidget,
            reason: '$id should show "Do this" label',
          );

          // Begin button must be present.
          expect(
            find.text('Begin'),
            findsOneWidget,
            reason: '$id should show Begin button',
          );

          // AI Motion screen must NOT have opened yet.
          expect(
            find.byType(_AiMotionPlaceholder),
            findsNothing,
            reason: '$id should NOT auto-navigate to AI Motion screen',
          );
        },
      );

      testWidgets('$id tapping Begin navigates to the ai-motion route', (
        tester,
      ) async {
        final race = _raceFor(id, title, unit);
        await tester.pumpWidget(_buildTestApp(race));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Begin'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byType(_AiMotionPlaceholder),
          findsOneWidget,
          reason: '$id should navigate to AI Motion after Begin tap',
        );
      });
    }
  });

  group('preset movement demo coverage', () {
    test('every supported preset movement has a pre-verify demo', () {
      for (final definition in motionActivityDefinitions) {
        final demo = movementDemoForType(definition.type);
        expect(
          demo,
          isNotNull,
          reason: '${definition.type.name} has no pre-verify MovementDemo',
        );
        expect(
          demo!.poses.length,
          greaterThan(1),
          reason: '${definition.type.name} demo needs at least 2 poses',
        );
      }
    });

    test('movementDemoForType returns non-null for all 13 preset IDs', () {
      for (final (id, _, _) in _presetCases) {
        // Verify via the catalog that each ID resolves to a definition
        // and that definition has a demo.
        final def = motionActivityForBackendValue(id);
        expect(def, isNotNull, reason: 'No catalog definition for $id');
        final demo = movementDemoForType(def!.type);
        expect(demo, isNotNull, reason: 'No demo for $id');
      }
    });
  });

  group('AI Motion screen isolation', () {
    testWidgets(
      'movement animation is NOT rendered inside the AI Motion screen',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: _AiMotionPlaceholder()),
        );
        expect(find.byType(NuvoMovementAnimation), findsNothing);
      },
    );
  });
}
