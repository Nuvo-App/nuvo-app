import '../data/race_models.dart';
import 'motion_activity.dart';

/// One place that knows what each race format *means*. Mirrors the Worker's
/// `scoringRuleForFormat` / `applyVerifiedSubmission` — UI layers read from
/// here instead of scattering `format == 'best_attempt'` conditionals.
///
/// Backend truth (server/worker/src/domain/raceScoring.ts):
///   maximum_attempt  → newScore = max(previous, submitted)
///   minimum_attempt  → newScore = min(previous, submitted)  (0 = no score yet)
///   cumulative_sum   → newScore = previous + submitted
///   completed        → only first_to_goal reaching its target
extension RaceFormatSemantics on RaceFormat {
  /// The finish-line quantity is the rule only in first-to-goal. Attempt
  /// races keep their own score; most-in-window is decided by the deadline.
  bool get usesScoreTarget => this == RaceFormat.firstToGoal;

  /// Proofs add onto the banked score — first-to-goal and most-in-window.
  /// Attempt races replace (max/min), never add.
  bool get isCumulative =>
      this == RaceFormat.firstToGoal || this == RaceFormat.mostInWindow;

  /// Each proof is a self-contained attempt whose result stands alone —
  /// the Worker's `formatUsesAttempts` (attempts must be declared open).
  bool get isAttemptBased =>
      this == RaceFormat.bestAttempt || this == RaceFormat.timedAttempt;

  /// Every mode except first-to-goal closes on a finish line.
  bool get usesDeadline => this != RaceFormat.firstToGoal;

  /// Timed battles are the only mode where attempt length changes scoring.
  bool get usesAttemptDuration => this == RaceFormat.timedAttempt;

  /// Mirrors `scoringRuleForFormat(format, scoreDirection)` on the Worker.
  String scoringRuleFor(String scoreDirection) => isAttemptBased
      ? (scoreDirection == 'lower' ? 'minimum_attempt' : 'maximum_attempt')
      : 'cumulative_sum';
}

/// The competitive context a verifier needs to talk about the race it's
/// measuring — built from the race payload (`viewerContext` first: it is
/// server-computed truth; participant standings are the fallback).
///
/// Three numbers are deliberately separate:
///   [raceScoreBefore]  — verified score banked before this session
///   sessionScore       — what this attempt produces (lives in the runtime)
///   raceScoreAfter()   — the two combined *by the scoring rule*, not by a
///                        blanket "+"
///
/// Non-applicable fields stay null — no fake zeros: a best-attempt race has
/// no goalTarget, a first-to-goal race has no scoreToBeat.
class VerifierRaceContext {
  const VerifierRaceContext({
    required this.format,
    required this.scoreDirection,
    required this.raceScoreBefore,
    this.goalTarget,
    this.leaderScore,
    this.personalBest,
    this.deadline,
    this.timeRemainingSeconds,
    this.attemptDurationSeconds,
    this.isFinished = false,
  });

  /// The stored format — null-safe parsed elsewhere, so callers should use
  /// [VerifierRaceContext.forRace] rather than hand-constructing.
  final RaceFormat format;

  /// 'higher' | 'lower' — which way the leaderboard reads.
  final String scoreDirection;

  /// Verified score banked on the race before this session opened.
  final int raceScoreBefore;

  /// The literal finish line — only when the format has one.
  final int? goalTarget;

  /// The strongest score on the board that isn't mine (direction-aware:
  /// the *lowest* rival score in a lower-wins race).
  final int? leaderScore;

  /// My own banked score in an attempt race — null when I have none yet.
  /// (Backend convention: 0 means "no score", never "score of zero".)
  final int? personalBest;

  /// The race's finish line, when one exists.
  final DateTime? deadline;

  /// Server-provided seconds until the finish line, when it ships one.
  final int? timeRemainingSeconds;

  /// Timed battles only — how long this attempt runs.
  final int? attemptDurationSeconds;

  /// The race is already over — no meaningful "finish the goal" flow.
  final bool isFinished;

  bool get lowerWins => scoreDirection == 'lower';
  bool get isCumulative => format.isCumulative;
  bool get isAttemptBased => format.isAttemptBased;
  String get scoringRule => format.scoringRuleFor(scoreDirection);

  /// first_to_goal: how far the finish line still is. Null when the format
  /// has no goal or the goal is already banked.
  int? get remainingToGoal {
    final target = goalTarget;
    if (target == null || target <= 0) return null;
    final left = target - raceScoreBefore;
    return left > 0 ? left : 0;
  }

  /// I currently hold the board — no rival score beats my banked one
  /// (a tie counts: nobody is ahead of me).
  bool get iHoldLead {
    final lead = leaderScore;
    if (lead == null || raceScoreBefore <= 0) return lead == null;
    return lowerWins
        ? raceScoreBefore <= lead
        : raceScoreBefore >= lead;
  }

  /// The number that matters on an attempt race: the leader's score when
  /// someone else holds it, my own best when I'm the one to beat.
  int? get scoreToBeat => switch (format) {
    RaceFormat.bestAttempt || RaceFormat.timedAttempt =>
      iHoldLead ? personalBest : leaderScore,
    _ => null,
  };

  /// Combines this session's score with the banked score using the actual
  /// scoring rule — never assumes addition.
  /// Mirrors `applyVerifiedSubmission` in raceScoring.ts.
  int raceScoreAfter(int sessionScore) {
    final value = sessionScore < 0 ? 0 : sessionScore;
    return switch (scoringRule) {
      'maximum_attempt' =>
        value > raceScoreBefore ? value : raceScoreBefore,
      'minimum_attempt' =>
        raceScoreBefore > 0 && raceScoreBefore < value
            ? raceScoreBefore
            : value,
      _ => raceScoreBefore + value,
    };
  }

  /// first_to_goal only: the session reaches the finish line.
  bool completesGoal(int sessionScore) =>
      format == RaceFormat.firstToGoal &&
      goalTarget != null &&
      raceScoreAfter(sessionScore) >= goalTarget!;

  /// Attempt modes only: did this session produce a new personal best —
  /// or take the lead outright? Presentation hooks for "new best" moments.
  bool beatsPersonalBest(int sessionScore) {
    if (!isAttemptBased) return false;
    final best = personalBest;
    if (best == null || best <= 0) return sessionScore > 0;
    return lowerWins
        ? sessionScore < best
        : sessionScore > best;
  }

  bool beatsLeader(int sessionScore) {
    final lead = leaderScore;
    if (lead == null) return false;
    return lowerWins ? sessionScore < lead : sessionScore > lead;
  }

  /// One line that names what this session is for — the verifier's
  /// mode-aware status copy. Standings-only facts ("you're 2nd") stay out;
  /// this is about the attempt in front of the athlete.
  String get statusLine => switch (format) {
    RaceFormat.firstToGoal => switch (remainingToGoal) {
        null || 0 => 'Goal reached',
        1 => '1 more to finish',
        final left => '$left to finish',
      },
    RaceFormat.bestAttempt => switch ((lowerWins, scoreToBeat)) {
        (_, null) => 'Best verified attempt wins',
        (true, final beat) =>
          iHoldLead ? 'Go under your best: $beat' : 'Go under $beat',
        (false, final beat) =>
          iHoldLead ? 'Beat your best: $beat' : 'Beat $beat',
      },
    RaceFormat.timedAttempt => switch (scoreToBeat) {
        null =>
          'Most in ${formatDurationShort(attemptDurationSeconds ?? 0)} wins',
        final beat =>
          lowerWins ? 'Go under $beat' : 'Beat $beat',
      },
    RaceFormat.mostInWindow => 'Most verified score before the deadline wins',
  };

  /// Builds the context from the race payload — `viewerContext` carries
  /// server-computed standings when present; participant rows are the
  /// fallback so older payloads still describe a real race.
  factory VerifierRaceContext.forRace(Race race, String? userId) {
    final format =
        RaceFormat.fromBackendValue(race.format) ?? RaceFormat.firstToGoal;
    final me = userId == null ? null : race.participantFor(userId);
    final vc = race.viewerContext;

    // Leader score — direction-aware, and never the viewer's own number.
    int? leaderScore = vc?.leaderScore;
    if (leaderScore == null || vc?.leaderUserId == userId) {
      leaderScore = null;
      for (final p in race.participants) {
        if (p.userId == userId || p.progressValue <= 0) continue;
        if (leaderScore == null) {
          leaderScore = p.progressValue;
        } else {
          final better = race.scoreDirection == 'lower'
              ? p.progressValue < leaderScore
              : p.progressValue > leaderScore;
          if (better) leaderScore = p.progressValue;
        }
      }
    }

    final myScore = vc?.viewerScore ?? me?.progressValue ?? 0;

    return VerifierRaceContext(
      format: format,
      scoreDirection: race.scoreDirection,
      raceScoreBefore: myScore,
      goalTarget: format.usesScoreTarget ? race.targetValue : null,
      leaderScore: leaderScore,
      personalBest:
          format.isAttemptBased && myScore > 0 ? myScore : null,
      deadline: DateTime.tryParse(race.finishLineAt ?? ''),
      timeRemainingSeconds: vc?.timeRemainingSeconds,
      attemptDurationSeconds: race.attemptDurationSeconds,
      isFinished: vc?.isFinished ?? race.status == 'completed',
    );
  }
}
