import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_calibration_flow.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

import 'fixtures/pose_fixtures.dart';

/// Records one discrete example (neutral → move → neutral) and stops.
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

void main() {
  const normalizer = PoseNormalizer();

  group('deterministic teach flow — capture contract', () {
    test('three discrete examples do NOT auto-build; learning is explicit', () {
      var now = DateTime.utc(2026, 1, 1);
      final c = SingleSessionTeachingCapture(now: () => now, buildDelay: Duration.zero);
      expect(c.setMovementName('Invented move'), isNull);

      for (var rep = 0; rep < 3; rep++) {
        now = now.add(const Duration(seconds: 2));
        _recordExample(c, normalizer, now);
        // After every Stop the flow is idle and waiting for the user — never
        // building or learned on its own.
        expect(c.stage, TeachMovementStage.readyToRecord,
            reason: 'example ${rep + 1} must not auto-advance');
        expect(c.acceptedCount, rep + 1);
      }

      // Still not learned until the user explicitly asks.
      expect(c.stage, TeachMovementStage.readyToRecord);
      expect(c.verifierSpec, isNull);
      expect(c.canLearn, isTrue);

      c.buildWhenReady();
      expect(c.stage, TeachMovementStage.learned);
      expect(c.verifierSpec, isNotNull);
    });

    test('canLearn is false until three examples are captured', () {
      var now = DateTime.utc(2026, 1, 1);
      final c = SingleSessionTeachingCapture(now: () => now, buildDelay: Duration.zero);
      c.setMovementName('Invented move');
      expect(c.canLearn, isFalse);
      now = now.add(const Duration(seconds: 2));
      _recordExample(c, normalizer, now);
      expect(c.canLearn, isFalse);
      now = now.add(const Duration(seconds: 2));
      _recordExample(c, normalizer, now);
      expect(c.canLearn, isFalse);
      now = now.add(const Duration(seconds: 2));
      _recordExample(c, normalizer, now);
      expect(c.canLearn, isTrue);
    });
  });

  group('race composer route — Teach Nuvo is reachable before any unit step', () {
    Widget host(Widget child) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (context, state) => child),
          GoRoute(
            path: '/races/teach',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('TEACH_SCREEN_ROUTE'))),
          ),
        ],
      );
      return ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('activity step surfaces Teach Nuvo and no goal/unit prompt',
        (tester) async {
      await tester.pumpWidget(host(const RaceComposerScreen()));
      await tester.pumpAndSettle();

      // Name step → type a name → advance to the activity step.
      await tester.enterText(find.byType(TextField).first, 'Invented move');
      await tester.pump();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();

      expect(find.text("Don't see your movement?"), findsOneWidget);
      // The finish-line / unit question must not appear before teaching.
      expect(find.textContaining('to win'), findsNothing);
    });

    testWidgets('tapping Teach Nuvo routes to the teach screen', (tester) async {
      await tester.pumpWidget(host(const RaceComposerScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Invented move');
      await tester.pump();
      await tester.tap(find.text('Choose activity'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Don't see your movement?"));
      await tester.pumpAndSettle();

      expect(find.text('TEACH_SCREEN_ROUTE'), findsOneWidget);
    });
  });
}
