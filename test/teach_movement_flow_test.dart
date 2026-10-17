import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_flow.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/presentation/custom_pose/learned_custom_movement_provider.dart';
import 'package:nuvo/features/races/presentation/custom_pose/teach_movement_screen.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

import 'fixtures/pose_fixtures.dart';

void _recordExample(
  SingleSessionTeachingCapture c,
  PoseNormalizer n,
  DateTime t,
) {
  c.startRecordingExample();
  final poses = [
    n.normalize(neutralStandingPose()),
    n.normalize(neutralStandingPose()),
    n.normalize(armsOverheadPose()),
    n.normalize(armsOverheadPose()),
    n.normalize(armsOverheadPose()),
    n.normalize(armsOverheadPose()),
    n.normalize(neutralStandingPose()),
    n.normalize(neutralStandingPose()),
  ];
  for (var i = 0; i < poses.length; i++) {
    c.addFrame(poses[i], t.add(Duration(milliseconds: 120 * i)));
  }
  c.stopRecordingExampleAt(t.add(const Duration(milliseconds: 1200)));
}

CustomPoseVerifierSpec _realSpec(PoseNormalizer n) {
  var now = DateTime.utc(2026, 1, 1);
  final c = SingleSessionTeachingCapture(
    now: () => now,
    buildDelay: Duration.zero,
  );
  c.setMovementName('Side reach');
  for (var r = 0; r < 3; r++) {
    now = now.add(const Duration(seconds: 2));
    _recordExample(c, n, now);
  }
  c.buildWhenReady();
  return c.verifierSpec!;
}

/// A real phone-sized window: the default 800x600 test surface is shorter than
/// the intro, which would scroll the primary button out of reach.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  const normalizer = PoseNormalizer();

  group('capture contract — training is explicit, never auto-built', () {
    test('three discrete examples do NOT auto-build; learning is explicit', () {
      var now = DateTime.utc(2026, 1, 1);
      final c = SingleSessionTeachingCapture(
        now: () => now,
        buildDelay: Duration.zero,
      );
      expect(c.setMovementName('Invented move'), isNull);
      for (var rep = 0; rep < 3; rep++) {
        now = now.add(const Duration(seconds: 2));
        _recordExample(c, normalizer, now);
        expect(
          c.stage,
          TeachMovementStage.readyToRecord,
          reason: 'example ${rep + 1} must not auto-advance',
        );
        expect(c.acceptedCount, rep + 1);
      }
      expect(c.verifierSpec, isNull);
      expect(c.canLearn, isTrue);
      c.buildWhenReady();
      expect(c.stage, TeachMovementStage.learned);
      expect(c.verifierSpec, isNotNull);
    });
  });

  group('TeachMovementScreen', () {
    testWidgets(
      'with a name arg, shows a centred intro first, then "Example 1 of 3"',
      (tester) async {
        _phone(tester);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (c, s) => const TeachMovementScreen(
                args: TeachMovementArgs(
                  movementName: 'Side reach',
                  unit: 'reps',
                ),
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Intro first — nobody is dropped into a live camera cold.
        expect(find.text('Teach Nuvo Side reach'), findsOneWidget);
        expect(find.text('Start'), findsOneWidget);
        expect(find.text('Example 1 of 3'), findsNothing);
        // It must NOT re-ask for the movement name.
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Continue'), findsNothing);

        await tester.tap(find.text('Start'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Example 1 of 3'), findsOneWidget);
        expect(find.text('Record example 1'), findsOneWidget);
        expect(find.text('Teach Nuvo Side reach'), findsNothing);
      },
    );
  });

  group('Teach Nuvo result screen', () {
    testWidgets('Use this movement hands the spec back (never a silent no-op); '
        'edit actions are quiet text, not buttons', (tester) async {
      _phone(tester);
      LearnedCustomMovement? result;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await c.push<LearnedCustomMovement>('/teach');
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/teach',
            builder: (c, s) => const TeachMovementScreen(
              seedReadyFixture: true,
              args: TeachMovementArgs(movementName: 'Side reach', unit: 'reps'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nuvo can count'), findsOneWidget);
      // The two edit actions are plain tappable text — no button widget
      // around them at all (they must never read as a second CTA).
      for (final label in ['Retry teaching', 'Change name']) {
        expect(find.text(label), findsOneWidget);
        for (final kind in [
          TextButton,
          ElevatedButton,
          OutlinedButton,
          FilledButton,
        ]) {
          expect(find.widgetWithText(kind, label), findsNothing);
        }
      }

      await tester.tap(find.text('Use this movement'));
      await tester.pumpAndSettle();
      expect(result, isNotNull, reason: 'tapping Use must return the spec');
    });
  });

  group('race composer — custom movement state machine', () {
    Widget host({required LearnedCustomMovement teachResult}) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (c, s) => const RaceComposerScreen()),
          GoRoute(
            path: '/races/teach',
            builder: (c, s) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => c.pop(teachResult),
                  child: const Text('FAKE_FINISH_TEACHING'),
                ),
              ),
            ),
          ),
        ],
      );
      return ProviderScope(child: MaterialApp.router(routerConfig: router));
    }

    testWidgets('custom flow reaches training BEFORE amount / solo / review, '
        'then advances only after a spec is returned', (tester) async {
      _phone(tester);
      final spec = _realSpec(normalizer);
      await tester.pumpWidget(
        host(teachResult: LearnedCustomMovement(verifierSpec: spec)),
      );
      await tester.pumpAndSettle();

      // nameRace → chooseActivity
      await tester.enterText(find.byType(TextField).first, 'Friday burner');
      await tester.pump();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();

      // 'Friday burner' resolves to a custom goal — the movement picker
      // still leads, with Teach Nuvo as a direct path.
      // choose CUSTOM movement
      await tester.tap(find.textContaining('Teach Nuvo', findRichText: true));
      await tester.pumpAndSettle();

      // customMovementDetails: name + unit
      await tester.enterText(find.byType(TextField).first, 'Side reach');
      await tester.pump();
      await tester.tap(find.text('Continue to training'));
      await tester.pumpAndSettle();

      // We are now in the training stage (it auto-opened Teach Nuvo).
      expect(find.text('FAKE_FINISH_TEACHING'), findsOneWidget);
      // The target / participation / review steps must NOT be reachable yet.
      expect(find.textContaining('to win'), findsNothing);
      expect(find.text('Start solo'), findsNothing);
      expect(find.text('Start race'), findsNothing);

      // Finish teaching → spec returned → composer advances to the target step.
      await tester.tap(find.text('FAKE_FINISH_TEACHING'));
      await tester.pumpAndSettle();

      expect(find.textContaining('to win'), findsOneWidget);
    });

    testWidgets(
      '"pull ups" asks ONE centred question; Teach Nuvo goes straight to '
      'training with the name filled in',
      (tester) async {
        _phone(tester);
        final spec = _realSpec(normalizer);
        await tester.pumpWidget(
          host(teachResult: LearnedCustomMovement(verifierSpec: spec)),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'pull ups');
        await tester.pump();
        await tester.tap(find.text('Choose activity'));
        await tester.pumpAndSettle();

        expect(find.text('Count Pull Ups with the camera?'), findsOneWidget);
        expect(find.text('Teach Nuvo'), findsOneWidget);
        expect(find.text('Count it by hand'), findsOneWidget);
        // No busy picker, no second name form.
        expect(find.text('Movement name'), findsNothing);

        await tester.tap(find.text('Teach Nuvo'));
        await tester.pumpAndSettle();
        // Went straight to the Teach screen — never asked for the name again.
        expect(find.text('FAKE_FINISH_TEACHING'), findsOneWidget);
        await tester.tap(find.text('FAKE_FINISH_TEACHING'));
        await tester.pumpAndSettle();
        expect(find.textContaining('to win'), findsOneWidget);
      },
    );

    testWidgets('"Count it by hand" keeps it a normal goal', (tester) async {
      _phone(tester);
      final spec = _realSpec(normalizer);
      await tester.pumpWidget(
        host(teachResult: LearnedCustomMovement(verifierSpec: spec)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'pull ups');
      await tester.pump();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count it by hand'));
      await tester.pumpAndSettle();

      expect(find.text('Count Pull Ups with the camera?'), findsNothing);
      expect(find.text('FAKE_FINISH_TEACHING'), findsNothing);
    });

    testWidgets('a non-movement name never gets the teach question', (
      tester,
    ) async {
      final spec = _realSpec(normalizer);
      await tester.pumpWidget(
        host(teachResult: LearnedCustomMovement(verifierSpec: spec)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'who can sleep the most',
      );
      await tester.pump();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();

      expect(find.textContaining('with the camera?'), findsNothing);
    });
  });
}
