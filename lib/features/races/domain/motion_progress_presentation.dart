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

/// Live encouragement copy during a take. Copy pools are keyed on the
/// moment — progress phase, elapsed time, streak depth, milestone and
/// new-best beats — and every pool rotates through its lines without
/// repeating the one it just showed, so a take keeps talking like Nuvo
/// instead of looping a single string.
///
/// Deterministic on purpose: each pool serves its lines in order, so the
/// rotation is unit-testable and never random-dependent. Lines that are
/// moment flashes (milestone / new best) are drawn once per beat via
/// [triggerMilestone] / [triggerNewBest] and read through [flashLine].
class SessionEncouragement {
  /// A keep-going take switches to the long-take voice once it has run
  /// this long without reaching halfway — elapsed time picks the pool.
  static const lateElapsedSeconds = 45;

  /// The phase line redraws on this cadence — the recording HUD ticks
  /// once a second, so the line rotates every [rotationSeconds] ticks.
  static const rotationSeconds = 8;

  // Phase pools — the HUD's status line, uppercase like the fixed labels
  // they replace.
  static const readyPool = ['READY', 'SET AT THE START LINE', 'IN POSITION'];
  static const keepGoingPool = [
    'KEEP GOING',
    'EVERY REP BANKS',
    'STAY WITH IT',
    'STACK THE REPS',
  ];
  static const keepGoingLatePool = [
    'STILL WITH IT',
    'STEADY — REPS COUNT THE SAME',
    'LONG TAKE — KEEP MOVING',
  ];
  static const halfwayPool = [
    'HALFWAY',
    'HALF THE PUSH DONE',
    'MIDDLE OF THE RACE',
  ];
  static const almostTherePool = [
    'ALMOST THERE',
    'THE FINISH LINE IS CLOSE',
    'LAST STRETCH',
  ];
  static const finishPool = ['FINISH', 'FINISH LINE CROSSED', 'GOAL REACHED'];

  // Streak pools — the badge inside the rep flash, title case like the
  // lines it replaces. Depth picks the band.
  static const streakPool = [
    'Keep going',
    'Reps landing',
    "That's a run",
    'Building a streak',
  ];
  static const streakHotPool = [
    'Keep your streak!',
    'Rolling now',
    'Streak alive',
  ];
  static const streakOnFirePool = ['On fire!', 'Unstoppable', 'Double digits'];

  // Moment flashes — a crossed checkpoint or a new best holds the HUD line
  // for a beat before the phase line returns.
  static const milestonePool = [
    'CHECKPOINT BANKED',
    'ANOTHER MARK DOWN',
    'PROGRESS LANDING',
  ];
  static const newBestPool = [
    'NEW BEST — KEEP ROLLING',
    'PAST YOUR BEST',
    "THAT'S A NEW BEST",
  ];

  static const _phasePools = {
    MotionProgressPhase.ready: readyPool,
    MotionProgressPhase.keepGoing: keepGoingPool,
    MotionProgressPhase.halfway: halfwayPool,
    MotionProgressPhase.almostThere: almostTherePool,
    MotionProgressPhase.finish: finishPool,
  };

  final Map<String, int> _cursors = {};
  String _phaseKey = '';
  int _phaseTick = -1;
  String _phaseLine = readyPool.first;
  int _streak = -1;
  String _streakLine = streakPool.first;
  String _flashLine = '';

  /// The next line in a pool — round-robin, so consecutive draws never
  /// repeat while the pool holds more than one line.
  String _next(String key, List<String> pool) {
    final index = (_cursors[key] ?? 0) % pool.length;
    _cursors[key] = index + 1;
    return pool[index];
  }

  /// The HUD's phase line. Stable while [rotationTick] holds (one tick is
  /// [rotationSeconds] of take time); a new tick or a new phase draws the
  /// pool's next line — never the one just shown.
  String phaseLine(
    MotionProgressPhase phase, {
    int elapsedSeconds = 0,
    int rotationTick = 0,
  }) {
    final late =
        phase == MotionProgressPhase.keepGoing &&
        elapsedSeconds >= lateElapsedSeconds;
    final key = late ? 'keepGoingLate' : 'phase:${phase.name}';
    final pool = late ? keepGoingLatePool : _phasePools[phase]!;
    if (key != _phaseKey || rotationTick != _phaseTick) {
      _phaseKey = key;
      _phaseTick = rotationTick;
      _phaseLine = _next(key, pool);
    }
    return _phaseLine;
  }

  /// The streak badge — the band picks the pool, each new streak value
  /// draws the next line.
  String streakLine(int streak) {
    if (streak != _streak) {
      _streak = streak;
      _streakLine = streak >= 10
          ? _next('streakOnFire', streakOnFirePool)
          : streak >= 5
          ? _next('streakHot', streakHotPool)
          : _next('streak', streakPool);
    }
    return _streakLine;
  }

  /// The line a milestone or new-best flash is showing — read while the
  /// screen holds its flash window.
  String get flashLine => _flashLine;

  /// A checkpoint crossed (a phase step) — flashes one milestone line.
  void triggerMilestone() => _flashLine = _next('milestone', milestonePool);

  /// This take just beat the athlete's best — flashes one new-best line.
  void triggerNewBest() => _flashLine = _next('newBest', newBestPool);

  /// Between takes — the next take starts its own rotation, not the tail
  /// of this one.
  void reset() {
    _phaseKey = '';
    _phaseTick = -1;
    _phaseLine = readyPool.first;
    _streak = -1;
    _streakLine = streakPool.first;
    _flashLine = '';
  }
}
