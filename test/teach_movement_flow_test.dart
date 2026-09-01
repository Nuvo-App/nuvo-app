import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_flow.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/presentation/custom_pose/teach_movement_screen.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

import 'fixtures/pose_fixtures.dart';

void _recordExample(SingleSessionTeachingCapture c, PoseNormalizer n, DateTime t) {
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
  final c = SingleSessionTeachingCapture(now: () => now, buildDelay: Duration.zero);
  c.setMovementName('Side reach');
  for (var r = 0; r < 3; r++) {
    now = now.add(const Duration(seconds: 2));
    _recordExample(c, n, now);
  }
  c.buildWhenReady();
  return c.verifierSpec!;
}

void main() {
  const normalizer = PoseNormalizer();

  group('capture contract — training is explicit, never auto-built', () {
    test('three discrete examples do NOT auto-build; learning is explicit', () {
      var now = DateTime.utc(2026, 1, 1);
      final c = SingleSessionTeachingCapture(now: () => now, buildDelay: Duration.zero);
      expect(c.setMovementName('Invented move'), isNull);
      for (var rep = 0; rep < 3; rep++) {
        now = now.add(const Duration(seconds: 2));
        _recordExample(c, normalizer, now);
        expect(c.stage, TeachMovementStage.readyToRecord,
            reason: 'example ${rep + 1} must not auto-advance');
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
    testWidgets('with a name arg, opens straight on "Example 1 of 3"',
        (tester) async {
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => const TeachMovementScreen(
            args: TeachMovementArgs(movementName: 'Side reach', unit: 'reps'),
          ),
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Example 1 of 3'), findsOneWidget);
      expect(find.text('Record example 1'), findsOneWidget);
      // It must NOT re-ask for the movement name.
      expect(find.widgetWithText(TextField, ''), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });
  });

  group('race composer — custom movement state machine', () {
    Widget host({required CustomPoseVerifierSpec teachResult}) {
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
      final spec = _realSpec(normalizer);
      await tester.pumpWidget(host(teachResult: spec));
      await tester.pumpAndSettle();

      // nameRace → chooseActivity
      await tester.enterText(find.byType(TextField).first, 'Friday burner');
      await tester.pump();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();

      // choose CUSTOM movement
      await tester.tap(find.text("Don't see your movement?"));
      await tester.pumpAndSettle();

      // customMovementDetails: name + unit
      await tester.enterText(
          find.widgetWithText(TextField, '').first, 'Side reach');
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
  });
}
