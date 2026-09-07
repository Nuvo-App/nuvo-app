import 'motion_activity.dart';

/// Continuing a race: a verification session is another contribution to the
/// SAME cumulative race progress. The verifier counts a *session* (from 0)
/// toward the amount still owed; the athlete sees *race progress*, and only
/// the session's contribution is ever submitted.
class ContinuationProgress {
  const ContinuationProgress({
    required this.startingRaceProgress,
    required this.raceTarget,
  });

  /// Progress already banked on the race before this session opened.
  final int startingRaceProgress;

  /// The full race goal (reps / seconds / metres).
  final int raceTarget;

  /// What the verifier's own machine should aim for this session — the
  /// remaining amount (never below 1 so the machine can still fire once).
  int get sessionTarget => raceTarget <= 0
      ? 1
      : (raceTarget - startingRaceProgress).clamp(1, raceTarget);

  /// The primary number the athlete sees, given this session's contribution
  /// so far. Opens at [startingRaceProgress] (a rep in a `4/6` race shows
  /// `4/6`, not `0/2`); caps at [raceTarget].
  int displayedProgress(int sessionContribution) {
    final v = startingRaceProgress + (sessionContribution < 0 ? 0 : sessionContribution);
    if (raceTarget <= 0) return v;
    return v.clamp(0, raceTarget);
  }

  /// The amount to persist as new progress — the session only, never the
  /// already-banked total.
  int contributionToSubmit(int sessionContribution) =>
      sessionContribution < 0 ? 0 : sessionContribution;

  bool completedAfter(int sessionContribution) =>
      raceTarget > 0 && displayedProgress(sessionContribution) >= raceTarget;
}

/// The single place that decides how a verification session *presents*
/// progress, based on the measurement type and the race goal scale. Widgets
/// read from here — they never carry their own threshold.

/// Milestone "+1 / +2 / +3" bursts (the RepBurst visual) are shown when each
/// milestone represents something the athlete can feel land:
///  - reps / step-cadence goals: always (one rep = one +1)
///  - a **short** distance sprint: yes — one +1 per whole metre crossed. The
///    metre is real (accumulated by [VirtualDistanceEstimator]); the burst
///    reacts to it, it does not fabricate it.
///  - a mile-scale run: no — hundreds of +1s is noise. Show distance + pace +
///    intensity instead.
///  - a duration hold: no — a per-second +1 is noise.
bool motionProgressUsesMilestoneBursts(MotionMeasurementType type, int target) {
  switch (type) {
    case MotionMeasurementType.repetitions:
      return true;
    case MotionMeasurementType.duration:
      return false;
    case MotionMeasurementType.distance:
      // Same crossover as the metres/miles formatter — a metre-scale goal.
      return target > 0 && target < kMetresMilesCrossover;
  }
}

/// Whether the verification HUD should show the pace + intensity line
/// (distance races that aren't in milestone-burst mode).
bool motionProgressShowsPace(MotionMeasurementType type, int target) =>
    type == MotionMeasurementType.distance &&
    !motionProgressUsesMilestoneBursts(type, target);

/// Coarse progress state for the "KEEP GOING / HALFWAY / ALMOST THERE / FINISH"
/// line. Derived from real progress — restrained, not a game show.
enum MotionProgressPhase { ready, keepGoing, halfway, almostThere, finish }

MotionProgressPhase motionProgressPhase({
  required int current,
  required int target,
}) {
  if (target <= 0) return MotionProgressPhase.keepGoing;
  final pct = current / target;
  if (current <= 0) return MotionProgressPhase.ready;
  if (pct >= 1.0) return MotionProgressPhase.finish;
  if (pct >= 0.85) return MotionProgressPhase.almostThere;
  if (pct >= 0.5) return MotionProgressPhase.halfway;
  return MotionProgressPhase.keepGoing;
}

extension MotionProgressPhaseLabel on MotionProgressPhase {
  String get label => switch (this) {
        MotionProgressPhase.ready => 'READY',
        MotionProgressPhase.keepGoing => 'KEEP GOING',
        MotionProgressPhase.halfway => 'HALFWAY',
        MotionProgressPhase.almostThere => 'ALMOST THERE',
        MotionProgressPhase.finish => 'FINISH',
      };
}
