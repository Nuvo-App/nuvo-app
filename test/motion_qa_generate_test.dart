import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'motion_qa/synthetic_fixture_factory.dart';
import 'motion_qa/fixture_augmenter.dart';
import 'motion_qa/replay_runner.dart';
import 'motion_qa/qa_report.dart';

/// Generates the permanent QA fixture bank.
///
/// Run with:
///   flutter test test/motion_qa_generate_test.dart
///
/// This creates JSON fixture files in `test/motion_qa/fixtures/` and a
/// manifest listing all fixtures with their expected outcomes.
void main() {
  final factory = SyntheticFixtureFactory(seed: 42);
  final augmenter = FixtureAugmenter(seed: 42);
  final runner = ReplayRunner();
  final reportGen = const QaReportGenerator();

  final baseFixtures = factory.allPilotFixtures();
  final augmented = baseFixtures.expand(augmenter.generateVariants).toList();
  final allFixtures = [...baseFixtures, ...augmented];

  test('generate QA fixture bank', () {
    final results = runner.runAll(allFixtures);

    final fixtureDir = Directory('test/motion_qa/fixtures');
    if (!fixtureDir.existsSync()) {
      fixtureDir.createSync(recursive: true);
    }

    final manifest = <Map<String, dynamic>>[];
    for (var i = 0; i < allFixtures.length; i++) {
      final fixture = allFixtures[i];
      final result = results[i];
      final filename = '${fixture.id}.json';
      final file = File('${fixtureDir.path}/$filename');
      file.writeAsStringSync(fixture.toJsonString());

      manifest.add({
        'id': fixture.id,
        'file': filename,
        'movement': fixture.movement,
        'expectedReps': fixture.expected.reps,
        'shouldMatch': fixture.expected.shouldMatch,
        'source': fixture.source.name,
        'detectedReps': result.detectedReps,
        'matched': result.matched,
        'failureReasons': result.failureReasons,
      });
    }

    final jsqFixtures =
        allFixtures.where((f) => f.movement == 'jump_squats').toList();
    final jsqResultList = runner.runAll(jsqFixtures);
    final jsqReport = reportGen.generate(jsqResultList, 'Jump Squat');

    final ljsFixtures =
        allFixtures.where((f) => f.movement == 'lunge_jumps').toList();
    final ljsResultList = runner.runAll(ljsFixtures);
    final ljsReport = reportGen.generate(ljsResultList, 'Lunge Jump');

    final manifestFile = File('${fixtureDir.path}/manifest.json');
    manifestFile.writeAsStringSync(
      JsonEncoder.withIndent('  ').convert({
        'generatedAt': DateTime.now().toIso8601String(),
        'totalFixtures': allFixtures.length,
        'baseFixtures': baseFixtures.length,
        'augmentedFixtures': augmented.length,
        'fixtures': manifest,
        'reports': {
          'jump_squats': jsqReport.toJson(),
          'lunge_jumps': ljsReport.toJson(),
        },
      }),
    );

    final reportFile = File('${fixtureDir.path}/qa_report.md');
    reportFile.writeAsStringSync(
      '${jsqReport.toMarkdown()}\n\n---\n\n${ljsReport.toMarkdown()}\n',
    );

    // ignore: avoid_print
    print('Generated ${allFixtures.length} fixtures in ${fixtureDir.path}');
    // ignore: avoid_print
    print('Manifest: ${manifestFile.path}');
    // ignore: avoid_print
    print('Report: ${reportFile.path}');
    // ignore: avoid_print
    print(
        'Jump Squat accept rate: ${(jsqReport.acceptRate * 100).toStringAsFixed(1)}%');
    // ignore: avoid_print
    print(
        'Lunge Jump accept rate: ${(ljsReport.acceptRate * 100).toStringAsFixed(1)}%');
    // ignore: avoid_print
    print('False accepts: ${jsqReport.falseAccepts}');

    expect(allFixtures.length, greaterThan(0));
  });
}
