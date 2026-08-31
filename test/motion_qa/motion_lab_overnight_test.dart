import 'dart:io';

import 'lab/motion_lab.dart';

/// Overnight long-run entry point for the Nuvo Motion Lab.
///
/// Usage:
///   flutter test test/motion_qa/motion_lab_overnight_test.dart --timeout 36000s
///
/// Or with environment override:
///   MOTION_LAB_CLEAN=1 flutter test test/motion_qa/motion_lab_overnight_test.dart --timeout 36000s
///
/// Configuration:
///   maxExperiments: 100000 (safety ceiling only — time is primary budget)
///   budgetHours: 8
///   plateauWindow: 200
///   productionWrite: false
///
/// Features:
///   - Hierarchical search (broad→select→refine→confirm)
///   - Proper train/dev/validation/holdout splits with no leakage
///   - Conservative champion promotion with validation confirmation runs
///   - Single final holdout evaluation (holdout never queried during search)
///   - Failure-driven research feedback loop
///   - Rich live STATUS.md with throughput, stage, family breakdown
///   - Comprehensive morning report with overfitting analysis
///   - Atomic writes for crash safety
///   - Run-scoped artifact directories (no cross-run overwrites)
void main() {
  // Clean previous run artifacts if requested
  final labDir = Directory('test/motion_qa/lab');
  if (Platform.environment.containsKey('MOTION_LAB_CLEAN')) {
    final runsDir = Directory('${labDir.path}/runs');
    if (runsDir.existsSync()) {
      runsDir.deleteSync(recursive: true);
    }
    print('Cleaned previous run artifacts.');
  }

  final lab = MotionLab(
    labDir: 'test/motion_qa/lab',
    fixtureDir: 'test/motion_qa/fixtures/real',
    budgetHours: 8.0,
    maxExperiments: 2000000,
    plateauWindow: 200,
    productionWrite: false,
  );

  lab.load();
  lab.run();
}
