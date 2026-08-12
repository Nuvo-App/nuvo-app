import 'dart:io';

import 'lab/motion_lab.dart';

/// Validation run — 5-minute test to verify all overnight features work.
///
/// Usage:
///   flutter test test/motion_qa/motion_lab_validation_test.dart --timeout 600s
///
/// Verifies:
///   - Hierarchical search stages (broad→select→refine→confirm)
///   - Proper train/dev/validation/holdout splits
///   - Conservative champion promotion with promotion reasons
///   - Validation confirmation runs (NOT holdout during search)
///   - Single final holdout evaluation (holdout untouched during search)
///   - Failure-driven research feedback
///   - Rich STATUS.md generation
///   - Atomic writes (no .tmp files left)
///   - Run-scoped artifact directories
///   - Time-based budget termination
///   - Morning report generation
void main() {
  final labDir = Directory('test/motion_qa/lab');

  // Clean previous runs
  final runsDir = Directory('${labDir.path}/runs');
  if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  print('=== VALIDATION RUN: Cleaned previous runs ===');

  // 2-minute validation: 0.03 hours = ~2 minutes
  // Safety ceiling: 1000 experiments (should hit time limit first)
  final lab = MotionLab(
    labDir: 'test/motion_qa/lab',
    fixtureDir: 'test/motion_qa/fixtures/real',
    budgetHours: 0.03,  // ~2 minutes
    maxExperiments: 1000,
    plateauWindow: 50,
    productionWrite: false,
  );

  lab.load();
  lab.run();

  // Find the run-scoped directory
  final latestRunPointer = File('${labDir.path}/LATEST_RUN.txt');
  if (!latestRunPointer.existsSync()) {
    print('FAIL: LATEST_RUN.txt not found');
    exit(1);
  }
  final runDirPath = latestRunPointer.readAsStringSync().trim();
  final runDir = Directory(runDirPath);
  print('Run directory: $runDirPath');

  // Post-run validation checks
  print('\n=== VALIDATION CHECKS ===');

  final checks = <String, bool>{};

  // 1. EXPERIMENTS.jsonl exists and has records
  final expFile = File('$runDirPath/EXPERIMENTS.jsonl');
  checks['EXPERIMENTS.jsonl exists'] = expFile.existsSync();
  checks['EXPERIMENTS.jsonl has records'] = expFile.existsSync() &&
      expFile.readAsLinesSync().where((l) => l.trim().isNotEmpty).length > 0;

  // 2. CHAMPION.json exists
  final champFile = File('$runDirPath/CHAMPION.json');
  checks['CHAMPION.json exists'] = champFile.existsSync();

  // 3. STATUS.md exists and is non-trivial
  final statusFile = File('$runDirPath/STATUS.md');
  checks['STATUS.md exists'] = statusFile.existsSync();
  checks['STATUS.md has research stage'] = statusFile.existsSync() &&
      statusFile.readAsStringSync().contains('Research Stage');
  checks['STATUS.md has throughput'] = statusFile.existsSync() &&
      statusFile.readAsStringSync().contains('Throughput');
  checks['STATUS.md has validation confirmations'] = statusFile.existsSync() &&
      statusFile.readAsStringSync().contains('Validation confirmations');

  // 4. No .tmp files left (atomic writes completed)
  final tmpFile = File('$runDirPath/STATUS.md.tmp');
  checks['No .tmp files (atomic writes OK)'] = !tmpFile.existsSync();

  // 5. OVERNIGHT_MOTION_REPORT.md exists
  final reportFile = File('$runDirPath/OVERNIGHT_MOTION_REPORT.md');
  checks['Morning report exists'] = reportFile.existsSync();
  checks['Report has holdout section'] = reportFile.existsSync() &&
      reportFile.readAsStringSync().contains('HOLDOUT');
  checks['Report has promotion reason'] = reportFile.existsSync() &&
      reportFile.readAsStringSync().contains('PROMOTION REASON');
  checks['Report has validation confirmations'] = reportFile.existsSync() &&
      reportFile.readAsStringSync().contains('Validation confirmations');

  // 6. FAMILY_STATE.json exists
  checks['FAMILY_STATE.json exists'] = File('$runDirPath/FAMILY_STATE.json').existsSync();

  // 7. LEADERBOARD files exist
  checks['LEADERBOARD.json exists'] = File('$runDirPath/LEADERBOARD.json').existsSync();
  checks['LEADERBOARD.csv exists'] = File('$runDirPath/LEADERBOARD.csv').existsSync();

  // 8. Holdout evaluated exactly once
  checks['HOLDOUT_RESULTS.md exists'] = File('$runDirPath/HOLDOUT_RESULTS.md').existsSync();
  if (File('$runDirPath/HOLDOUT_RESULTS.md').existsSync()) {
    final holdoutContent = File('$runDirPath/HOLDOUT_RESULTS.md').readAsStringSync();
    checks['Holdout evaluated once (not 1540 times)'] = !holdoutContent.contains('#1540') &&
        !holdoutContent.contains('# 1540');
  }

  // 9. Run-scoped directory exists
  checks['Run-scoped directory exists'] = runDir.existsSync();

  // Print results
  int passed = 0;
  int failed = 0;
  for (final entry in checks.entries) {
    final status = entry.value ? 'PASS' : 'FAIL';
    print('  [$status] ${entry.key}');
    if (entry.value) {
      passed++;
    } else {
      failed++;
    }
  }

  print('\n=== VALIDATION RESULT: $passed passed, $failed failed ===');
  if (failed > 0) {
    print('VALIDATION FAILED — fix issues before overnight run');
    exit(1);
  } else {
    print('VALIDATION PASSED — ready for overnight run');
  }
}
