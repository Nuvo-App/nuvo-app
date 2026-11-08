/// Timed battle take — the 3-2-1 countdown, the fixed attempt window, and
/// the attempt bookkeeping for one camera take on a `timed_attempt` race.
///
/// Pure state: the proof screen's 1 s timers drive [tickCountdown] /
/// [tickWindow] and its controller makes the network calls, so the whole
/// timing contract is testable without a camera.
class TimedAttemptTake {
  TimedAttemptTake({
    required this.durationSeconds,
    required this.clientAttemptId,
  });

  /// Seconds of 3-2-1 shown before the attempt opens.
  static const countdownTicks = 3;

  /// The declared attempt length — the take counts exactly this long.
  final int durationSeconds;

  /// Stable per take: the idempotency key for POST /attempts, reused across
  /// retries of THIS take only. A new take mints a new one — the server
  /// dedupes on it, so reusing it would resurrect the cancelled attempt.
  final String clientAttemptId;

  /// 3 → 2 → 1; at 0 the attempt window starts.
  int countdownRemaining = countdownTicks;

  /// Seconds left in the attempt window — null until the countdown ends.
  int? secondsRemaining;

  /// The server attempt id once the open lands — needed to release it.
  String? openAttemptId;

  /// A proof bound to this attempt — once true there is nothing to release.
  bool proofSubmitted = false;

  /// Still in the 3-2-1 — no attempt has been opened yet.
  bool get countingDown => countdownRemaining > 0;

  /// The take must release its attempt: it is open and no proof bound to
  /// it. Only submitted attempts spend the limit, so abandoning the take
  /// before submit cancels instead of burning a slot.
  bool get needsRelease => openAttemptId != null && !proofSubmitted;

  /// One second of the 3-2-1. Returns true exactly once — the take's window
  /// (and its server attempt) should start now.
  bool tickCountdown() {
    if (countdownRemaining <= 0) return false;
    countdownRemaining -= 1;
    if (countdownRemaining != 0) return false;
    secondsRemaining = durationSeconds;
    return true;
  }

  /// One second of the attempt window. Returns true exactly when the clock
  /// hits zero — the take then finishes through the same path as Done.
  bool tickWindow() {
    final left = secondsRemaining;
    if (left == null || left <= 0) return false;
    secondsRemaining = left - 1;
    return secondsRemaining == 0;
  }

  void markOpened(String attemptId) => openAttemptId = attemptId;

  void markSubmitted() => proofSubmitted = true;
}

/// Whether the race's attempt limit leaves room for another take. No limit
/// (null) never blocks.
bool timedAttemptLimitReached({
  required int? attemptLimit,
  required int attemptsUsed,
}) => attemptLimit != null && attemptsUsed >= attemptLimit;

/// "1 of 3 attempts used" — shown before the take starts when a limit
/// exists. Empty when the race has no limit (nothing meaningful to show).
String timedAttemptsUsedLabel(int? attemptLimit, int attemptsUsed) =>
    attemptLimit == null ? '' : '$attemptsUsed of $attemptLimit attempts used';
