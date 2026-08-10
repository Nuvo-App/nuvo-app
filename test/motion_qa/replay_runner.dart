import 'replay_fixture.dart';
import 'motion_diagnostics.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Result of replaying a single fixture through the production validator.
class ReplayResult {
  const ReplayResult({
    required this.fixtureId,
    required this.movement,
    required this.expectedReps,
    required this.detectedReps,
    required this.shouldMatch,
    required this.matched,
    required this.totalFrames,
    required this.missingLandmarkFrames,
    required this.awaitingBaselineFrames,
    required this.airborneFrames,
    required this.groundedFrames,
    required this.trackingFrames,
    required this.idleFramesAfterStart,
    required this.awaitingResetFrames,
    required this.completedFrames,
    required this.failureReasons,
  });

  final String fixtureId;
  final String movement;
  final int expectedReps;
  final int detectedReps;
  final bool shouldMatch;
  final bool matched;
  final int totalFrames;
  final int missingLandmarkFrames;
  final int awaitingBaselineFrames;
  final int airborneFrames;
  final int groundedFrames;
  final int trackingFrames;
  final int idleFramesAfterStart;
  final int awaitingResetFrames;
  final int completedFrames;
  final List<String> failureReasons;

  bool get isCorrect => matched;
  bool get isFalsePositive => shouldMatch == false && detectedReps > 0;
  bool get isFalseNegative => shouldMatch == true && detectedReps < expectedReps;
}

/// Replays a recorded fixture through the actual production validator.
///
/// Uses [DiagnosticCollector] which wraps [createMotionValidator] — the same
/// factory used by the live verification path. This ensures the replay
/// exercises the real runtime, not a parallel fake.
class ReplayRunner {
  ReplayRunner();

  /// Replays a single fixture and returns detailed results.
  ReplayResult run(ReplayFixture fixture) {
    final activity = _activityForMovement(fixture.movement);
    final collector = DiagnosticCollector(activity: activity, target: 99);
    collector.start();

    for (final recordedFrame in fixture.frames) {
      collector.update(recordedFrame.toPoseFrame());
    }

    final detected = collector.validator.currentValue;
    final expected = fixture.expected.reps;
    final shouldMatch = fixture.expected.shouldMatch;

    final matched = shouldMatch
        ? detected == expected
        : detected == 0;

    final failureReasons = <String>[];
    if (collector.missingLandmarkFrames > 0) {
      failureReasons.add(
          'missing_landmarks: ${collector.missingLandmarkFrames}/${collector.totalFrames} frames');
    }
    if (collector.awaitingBaselineFrames > collector.totalFrames * 0.5) {
      failureReasons.add(
          'baseline_not_established: ${collector.awaitingBaselineFrames} frames awaiting');
    }
    if (collector.airborneFrames == 0 && shouldMatch) {
      failureReasons.add('airborne_never_detected');
    }
    if (collector.trackingFrames == 0 && shouldMatch) {
      failureReasons.add('tracker_never_progressed');
    }
    if (collector.idleFramesAfterStart > collector.totalFrames * 0.5 && shouldMatch) {
      failureReasons.add(
          'stuck_in_idle: ${collector.idleFramesAfterStart} frames idle after start');
    }
    if (shouldMatch && detected < expected) {
      failureReasons.add(
          'undercounted: expected=$expected detected=$detected');
    }
    if (!shouldMatch && detected > 0) {
      failureReasons.add(
          'false_positive: expected=0 detected=$detected');
    }

    return ReplayResult(
      fixtureId: fixture.id,
      movement: fixture.movement,
      expectedReps: expected,
      detectedReps: detected,
      shouldMatch: shouldMatch,
      matched: matched,
      totalFrames: collector.totalFrames,
      missingLandmarkFrames: collector.missingLandmarkFrames,
      awaitingBaselineFrames: collector.awaitingBaselineFrames,
      airborneFrames: collector.airborneFrames,
      groundedFrames: collector.groundedFrames,
      trackingFrames: collector.trackingFrames,
      idleFramesAfterStart: collector.idleFramesAfterStart,
      awaitingResetFrames: collector.awaitingResetFrames,
      completedFrames: collector.completedFrames,
      failureReasons: failureReasons,
    );
  }

  /// Runs multiple fixtures and returns all results.
  List<ReplayResult> runAll(List<ReplayFixture> fixtures) =>
      fixtures.map(run).toList();

  AiMotionActivity _activityForMovement(String movement) {
    return switch (movement) {
      'push_ups' => AiMotionActivity.pushUps,
      'jumping_jacks' => AiMotionActivity.jumpingJacks,
      'squats' => AiMotionActivity.squats,
      'normal_squats' => AiMotionActivity.squats,
      'lunges' => AiMotionActivity.lunges,
      'plank_hold' => AiMotionActivity.plankHold,
      'high_knees' => AiMotionActivity.highKnees,
      'arm_raises' => AiMotionActivity.armRaises,
      'sumo_squats' => AiMotionActivity.sumoSquats,
      'side_lunges' => AiMotionActivity.sideLunges,
      'deep_squats' => AiMotionActivity.deepSquats,
      'squat_jacks' => AiMotionActivity.squatJacks,
      'jump_squats' => AiMotionActivity.jumpSquats,
      'vertical_jumps' => AiMotionActivity.jumpSquats,
      'lunge_jumps' => AiMotionActivity.lungeJumps,
      _ => throw ArgumentError('Unknown movement: $movement'),
    };
  }
}
