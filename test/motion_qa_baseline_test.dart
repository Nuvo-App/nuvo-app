import 'package:flutter_test/flutter_test.dart';
import 'motion_qa/synthetic_fixture_factory.dart';
import 'motion_qa/fixture_augmenter.dart';
import 'motion_qa/replay_runner.dart';
import 'motion_qa/qa_report.dart';

/// Baseline QA test: runs all pilot fixtures through the production validator
/// BEFORE any tolerance changes. This establishes the failure baseline.
void main() {
  final factory = SyntheticFixtureFactory(seed: 42);
  final augmenter = FixtureAugmenter(seed: 42);
  final runner = ReplayRunner();
  final reportGen = const QaReportGenerator();

  final baseFixtures = factory.allPilotFixtures();
  final augmented = baseFixtures.expand(augmenter.generateVariants).toList();
  final allFixtures = [...baseFixtures, ...augmented];

  group('QA Baseline — Jump Squat', () {
    final jsqFixtures = allFixtures.where((f) => f.movement == 'jump_squats').toList();
    final results = runner.runAll(jsqFixtures);
    final report = reportGen.generate(results, 'Jump Squat');

    test('baseline report is generated', () {
      // ignore: avoid_print
      print('\n${report.toMarkdown()}');
      expect(report.positiveTotal, greaterThan(0));
    });

    test('clean jump squats are accepted', () {
      final clean = results.firstWhere((r) => r.fixtureId == 'jsq_clean_3');
      expect(clean.detectedReps, equals(3),
          reason: 'Clean 3-rep jump squat should count 3 reps');
    });

    test('noisy jump squats are accepted', () {
      final noisy = results.firstWhere((r) => r.fixtureId == 'jsq_noisy_3');
      // ignore: avoid_print
      print('Noisy 3-rep: detected=${noisy.detectedReps}, expected=3, '
          'missing=${noisy.missingLandmarkFrames}, '
          'airborne=${noisy.airborneFrames}, '
          'idle=${noisy.idleFramesAfterStart}, '
          'reasons=${noisy.failureReasons}');
      expect(noisy.detectedReps, equals(3),
          reason: 'Noisy 3-rep jump squat should count 3 reps');
    });

    test('very noisy jump squats — baseline measurement', () {
      final vn = results.firstWhere((r) => r.fixtureId == 'jsq_very_noisy_2');
      // ignore: avoid_print
      print('Very noisy 2-rep: detected=${vn.detectedReps}, expected=2, '
          'missing=${vn.missingLandmarkFrames}, '
          'airborne=${vn.airborneFrames}, '
          'idle=${vn.idleFramesAfterStart}, '
          'reasons=${vn.failureReasons}');
      // This is a measurement test — we record the baseline, not assert pass
    });

    test('normal squat confuser does NOT count', () {
      final squat = results.firstWhere((r) => r.fixtureId == 'squat_confuser_3');
      expect(squat.detectedReps, equals(0),
          reason: 'Normal squat should not count as jump squat');
    });

    test('plain jump confuser does NOT count', () {
      final jump = results.firstWhere((r) => r.fixtureId == 'jump_confuser_3');
      expect(jump.detectedReps, equals(0),
          reason: 'Plain jump should not count as jump squat');
    });

    test('jumping jack confuser does NOT count', () {
      final jacks = results.firstWhere((r) => r.fixtureId == 'jacks_confuser_3');
      expect(jacks.detectedReps, equals(0),
          reason: 'Jumping jacks should not count as jump squat');
    });

    test('partial squat confuser does NOT count', () {
      final partial = results.firstWhere((r) => r.fixtureId == 'partial_confuser_3');
      expect(partial.detectedReps, equals(0),
          reason: 'Partial squat + jump should not count as jump squat');
    });

    test('confuser false-accept rate is 0%', () {
      expect(report.falseAccepts.values.fold(0, (a, b) => a + b), equals(0),
          reason: 'No confusers should false-accept');
    });
  });

  group('QA Baseline — Lunge Jump', () {
    final ljsFixtures = allFixtures.where((f) => f.movement == 'lunge_jumps').toList();
    final results = runner.runAll(ljsFixtures);
    final report = reportGen.generate(results, 'Lunge Jump');

    test('baseline report is generated', () {
      // ignore: avoid_print
      print('\n${report.toMarkdown()}');
      expect(report.positiveTotal, greaterThan(0));
    });

    test('clean lunge jumps are accepted', () {
      final clean = results.firstWhere((r) => r.fixtureId == 'ljs_clean_2');
      expect(clean.detectedReps, equals(2),
          reason: 'Clean 2-rep lunge jump should count 2 reps');
    });

    test('noisy lunge jumps — baseline measurement', () {
      final noisy = results.firstWhere((r) => r.fixtureId == 'ljs_noisy_2');
      // ignore: avoid_print
      print('Noisy 2-rep: detected=${noisy.detectedReps}, expected=2, '
          'missing=${noisy.missingLandmarkFrames}, '
          'airborne=${noisy.airborneFrames}, '
          'reasons=${noisy.failureReasons}');
    });
  });

  group('QA Robustness — Augmented Variants', () {
    final augmentedResults = runner.runAll(augmented);

    test('all augmented variants run without crashing', () {
      for (final result in augmentedResults) {
        expect(result.totalFrames, greaterThan(0));
      }
    });

    test('augmented variants report', () {
      for (final r in augmentedResults) {
        // ignore: avoid_print
        print('${r.fixtureId}: detected=${r.detectedReps} '
            'expected=${r.expectedReps} '
            'matched=${r.matched} '
            'reasons=${r.failureReasons}');
      }
    });
  });
}
