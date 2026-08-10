import 'dart:convert';
import 'dart:io';
import 'synthetic_fixture_factory.dart';
import 'fixture_augmenter.dart';
import 'replay_runner.dart';
import 'qa_report.dart';

/// Generates the permanent QA fixture bank.
///
/// This script serializes all pilot fixtures (base + augmented variants)
/// to JSON files in `test/motion_qa/fixtures/` and creates a manifest
/// listing all fixtures with their expected outcomes.
///
/// Run with:
///   dart run test/motion_qa/generate_fixture_bank.dart
void main() async {
  final factory = SyntheticFixtureFactory(seed: 42);
  final augmenter = FixtureAugmenter(seed: 42);
  final runner = ReplayRunner();
  final reportGen = const QaReportGenerator();

  final baseFixtures = factory.allPilotFixtures();
  final augmented = baseFixtures.expand(augmenter.generateVariants).toList();
  final allFixtures = [...baseFixtures, ...augmented];

  // Run all fixtures through the production validator.
  final results = runner.runAll(allFixtures);

  // Create fixture directory.
  final fixtureDir = Directory('test/motion_qa/fixtures');
  if (!fixtureDir.existsSync()) {
    fixtureDir.createSync(recursive: true);
  }

  // Serialize each fixture to JSON.
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

  // Generate reports.
  final jsqFixtures = allFixtures.where((f) => f.movement == 'jump_squats').toList();
  final jsqResultList = runner.runAll(jsqFixtures);
  final jsqReport = reportGen.generate(jsqResultList, 'Jump Squat');

  final ljsFixtures = allFixtures.where((f) => f.movement == 'lunge_jumps').toList();
  final ljsResultList = runner.runAll(ljsFixtures);
  final ljsReport = reportGen.generate(ljsResultList, 'Lunge Jump');

  // Write manifest.
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

  // Write human-readable reports.
  final reportFile = File('${fixtureDir.path}/qa_report.md');
  reportFile.writeAsStringSync(
    '${jsqReport.toMarkdown()}\n\n---\n\n${ljsReport.toMarkdown()}\n',
  );

  stdout.writeln('Generated ${allFixtures.length} fixtures in ${fixtureDir.path}');
  stdout.writeln('Manifest: ${manifestFile.path}');
  stdout.writeln('Report: ${reportFile.path}');
  stdout.writeln('\nJump Squat accept rate: ${(jsqReport.acceptRate * 100).toStringAsFixed(1)}%');
  stdout.writeln('Lunge Jump accept rate: ${(ljsReport.acceptRate * 100).toStringAsFixed(1)}%');
  stdout.writeln('False accepts: ${jsqReport.falseAccepts}');
}
