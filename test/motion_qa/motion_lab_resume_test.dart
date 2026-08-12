import 'dart:io';

import 'lab/motion_lab.dart';

/// Phase 6: Resume test — runs 10 more experiments on top of existing state.
/// Does NOT clean artifacts. Verifies resumability.
void main() {
  // Do NOT clean — testing resume
  final lab = MotionLab(
    labDir: 'test/motion_qa/lab',
    fixtureDir: 'test/motion_qa/fixtures/real',
    budgetHours: 0.05,
    maxExperiments: 160, // 150 existing + 10 new
    plateauWindow: 40,
    productionWrite: false,
  );

  lab.load();
  lab.run();
}
