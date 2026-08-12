import 'dart:io';

import 'lab/motion_lab.dart';

/// Phase 2: Burn-in run — 150 experiments or 25 minutes.
/// Launched inside tmux for detached execution.
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
    budgetHours: 0.42, // ~25 minutes
    maxExperiments: 150,
    plateauWindow: 40,
    productionWrite: false,
  );

  lab.load();
  lab.run();
}
