import 'dart:io';

import 'lab/motion_lab.dart';

/// Phase 1: 20-experiment smoke test for burn-in verification.
void main() {
  final labDir = Directory('test/motion_qa/lab');
  if (Platform.environment.containsKey('MOTION_LAB_CLEAN')) {
    final artifacts = [
      'EXPERIMENTS.jsonl', 'CHAMPION.json', 'FAMILY_STATE.json',
      'FAILURE_CLUSTERS.json', 'LEARNING_CURVE.json',
      'STATUS.md', 'LEADERBOARD.json', 'LEADERBOARD.csv', 'LEADERBOARD.md',
      'OVERNIGHT_MOTION_REPORT.md', 'DATA_REQUEST.md',
    ];
    for (final name in artifacts) {
      final f = File('${labDir.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  }

  final lab = MotionLab(
    labDir: 'test/motion_qa/lab',
    fixtureDir: 'test/motion_qa/fixtures/real',
    budgetHours: 0.5,
    maxExperiments: 20,
    plateauWindow: 40,
    productionWrite: false,
  );

  lab.load();
  lab.run();
}
