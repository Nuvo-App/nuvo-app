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
/// read from here — they never carry a threshold of their own.
///
/// ## Why distance is special
/// Virtual distance is an **estimate**. A "+1" every estimated metre would fire
/// constantly at running speed and imply metre-level precision Nuvo does not
/// have. So a distance milestone means "**cumulative progress crossed a
/// presentation checkpoint**", spaced by the goal scale — never "one exact
/// metre was measured". The large authoritative number underneath always
/// shows the real cumulative estimate, updating smoothly.
class DistancePresentationPolicy {
  const DistancePresentationPolicy._(this.milestoneStepMetres, this.showsPace);

  /// Metres between milestone bursts. 0 → no burst animation (long runs).
  final int milestoneStepMetres;

  /// Show the pace + intensity line instead of / alongside bursts.
  final bool showsPace;

  bool get usesMilestoneBursts => milestoneStepMetres > 0;

  /// Chosen from the race target. Thresholds are here, and only here.
  factory DistancePresentationPolicy.forTarget(int targetMetres) {
    if (targetMetres <= 0) {
      return const DistancePresentationPolicy._(10, false);
    }
    if (targetMetres <= 25) {
      return const DistancePresentationPolicy._(5, false);
    }
    if (targetMetres <= 100) {
      return const DistancePresentationPolicy._(10, false);
    }
    if (targetMetres < kMetresMilesCrossover) {
      // ~200 m band — milestones far enough apart to feel earned.
      return const DistancePresentationPolicy._(25, false);
    }
    // Mile-scale: no metre bursts, pace + intensity carry the feedback.
    return const DistancePresentationPolicy._(0, true);
  }

  /// How many milestone checkpoints [metres] of cumulative distance has
  /// crossed. Feed this to the burst controller; it increments once per step.
  int milestonesCrossed(int metres) =>
      usesMilestoneBursts ? (metres < 0 ? 0 : metres) ~/ milestoneStepMetres : 0;

  /// The distance a milestone index represents, for the burst label
  /// ("15 m" — a checkpoint, not "+1").
  int metresAtMilestone(int milestoneIndex) =>
      milestoneIndex * milestoneStepMetres;
}

/// Milestone bursts (the RepBurst visual):
///  - reps / step-cadence: always (one rep = one +1).
///  - distance: only in a metre-scale sprint, spaced by
///    [DistancePresentationPolicy] — the burst reacts to a *checkpoint*, not a
///    fabricated metre.
///  - duration hold: never (a per-second +1 is noise).
bool motionProgressUsesMilestoneBursts(MotionMeasurementType type, int target) {
  switch (type) {
    case MotionMeasurementType.repetitions:
      return true;
    case MotionMeasurementType.duration:
      return false;
    case MotionMeasurementType.distance:
      return DistancePresentationPolicy.forTarget(target).usesMilestoneBursts;
  }
}

/// Whether the verification HUD should show the pace + intensity line.
bool motionProgressShowsPace(MotionMeasurementType type, int target) =>
    type == MotionMeasurementType.distance &&
    DistancePresentationPolicy.forTarget(target).showsPace;

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
