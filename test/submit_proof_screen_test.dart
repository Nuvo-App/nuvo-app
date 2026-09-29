import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/presentation/movement_preview/rive_movement_sequences.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/submit_proof_screen.dart';
import 'package:nuvo/features/races/presentation/widgets/movement_demo.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';
import 'package:nuvo/features/races/presentation/widgets/rive_movement_preview.dart';

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

final originalPresetCases = {
  for (final (id, _, _) in _presetCases)
    motionActivityForBackendValue(id)!.type,
};

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
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

class _AiMotionPlaceholder extends StatelessWidget {
  const _AiMotionPlaceholder();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('AI Motion Screen')));
}

Widget _buildTestApp(Race race, {FirstUseStore? firstUseStore}) {
  final store =
      firstUseStore ?? (FirstUseStore.memory()..markCameraPrimerSeen());
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(_FakeRaceRepo(race)),
      firstUseStoreProvider.overrideWithValue(store),
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
  group('SubmitProofScreen pre-verify setup for all 13 presets', () {
    for (final (id, title, unit) in _presetCases) {
      testWidgets('$id shows movement setup BEFORE Begin', (tester) async {
        final race = _raceFor(id, title, unit);
        await tester.pumpWidget(_buildTestApp(race));

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final movementType = motionActivityForBackendValue(id)!.type;
        // Assert the preview pipeline's public type, not its internals —
        // the native renderer can't link in flutter_test, so the widget
        // degrades to its fallback while still owning the preview slot.
        if (RiveMovementPreview.supports(movementType)) {
          expect(
            find.byType(RiveMovementPreview),
            findsOneWidget,
            reason: '$id should use the data-bound Nuvo Rive preview',
          );
        } else {
          expect(
            find.text('Camera opens after Begin'),
            findsOneWidget,
            reason: '$id should show the static verification setup',
          );
          expect(
            find.byType(RiveMovementPreview),
            findsNothing,
            reason: '$id should keep its existing fallback preview',
          );
        }

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
      });

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
    test('every original preset movement has a pre-verify demo', () {
      // Scoped to the original 13 — the preset-motion-expansion movements
      // (running/walking/marching/burpees/etc.) don't have a hand-authored
      // demo pose yet (see movementDemoForType's doc comment); the
      // != null check that gates whether the animation shows at all
      // already handles that gracefully. Not a regression — a deliberate,
      // documented gap.
      for (final definition in motionActivityDefinitions) {
        if (!originalPresetCases.contains(definition.type)) continue;
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

    test(
      'movementDemoForType returns non-null for all 13 original preset IDs',
      () {
        for (final (id, _, _) in _presetCases) {
          // Verify via the catalog that each ID resolves to a definition
          // and that definition has a demo.
          final def = motionActivityForBackendValue(id);
          expect(def, isNotNull, reason: 'No catalog definition for $id');
          final demo = movementDemoForType(def!.type);
          expect(demo, isNotNull, reason: 'No demo for $id');
        }
      },
    );
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

  test('new Rive preview phases match their validator-facing motion', () {
    final lunge = riveMovementSequenceFor(MotionActivityType.lunges);
    expect(lunge.poseAt(0.25).rightKneeAngle, lessThan(0));
    expect(lunge.poseAt(0.75).leftKneeAngle, greaterThan(0));

    final raises = riveMovementSequenceFor(MotionActivityType.armRaises);
    expect(raises.poseAt(0.5).leftShoulderAngle, isNot(-180));
    expect(raises.poseAt(0.5).rightShoulderAngle, isNot(180));

    for (final type in [
      MotionActivityType.runningInPlace,
      MotionActivityType.treadmillRunning,
      MotionActivityType.marchingInPlace,
    ]) {
      final sequence = riveMovementSequenceFor(type);
      expect(sequence.poseAt(0.2).leftKneeAngle, isNot(0));
      expect(sequence.poseAt(0.8).rightKneeAngle, isNot(0));
      expect(sequence.poseAt(1).isFiniteAndPositive, isTrue);
    }
  });
}
