import 'dart:io';

import 'lab/motion_lab.dart';

/// Smoke test: runs the motion lab with a small budget to verify all systems.
void main() {
  // Clean any previous smoke test artifacts
  final labDir = Directory('test/motion_qa/lab');
  final artifacts = [
    'EXPERIMENTS.jsonl', 'CHAMPION.json', 'FAMILY_STATE.json',
    'FAILURE_CLUSTERS.json', 'LEARNING_CURVE.json',
    'STATUS.md', 'LEADERBOARD.json', 'LEADERBOARD.csv', 'LEADERBOARD.md',
    'OVERNIGHT_MOTION_REPORT.md', 'DATA_REQUEST.md',
  ];

  // Don't clean — test resumability by keeping existing state
  // Only clean if --clean flag is passed
  if (Platform.environment.containsKey('MOTION_LAB_CLEAN')) {
    for (final name in artifacts) {
      final f = File('${labDir.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  }

  final lab = MotionLab(
    labDir: 'test/motion_qa/lab',
    fixtureDir: 'test/motion_qa/fixtures/real',
    budgetHours: 0.05, // ~3 minutes
    maxExperiments: 15,
    plateauWindow: 40,
    productionWrite: false,
  );

  lab.load();
  lab.run();
}
