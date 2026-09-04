/// Pure-Dart burst/streak bookkeeping for live rep feedback.
///
/// This is presentation-only bookkeeping. It never decides whether a rep
/// counts — it is fed the validator's already-authoritative running total
/// (`currentValue`/`output.count`) and only tracks how to *animate* a run of
/// reps that land close together in time. Detection and counting must never
/// wait on this, or on anything downstream of it.
///
/// Used by [NuvoRepPulse] and the live preset verification screen so both
/// share one burst-window rule instead of two hand-rolled copies.
class RepBurstController {
  RepBurstController({
    this.burstWindow = const Duration(milliseconds: 1400),
  });

  /// Reps landing within this window of the previous rep grow the same
  /// burst instead of starting a new one. Visual timing only — never fed
  /// back into recognition.
  final Duration burstWindow;

  int _lastSeenCount = 0;
  int _streakCount = 0;
  int _sequence = 0;
  DateTime? _lastRepAt;

  /// How many reps have landed in the current burst.
  int get streakCount => _streakCount;

  /// Bumps on every registered rep — key an animation on this so a fast
  /// back-to-back rep restarts the punch instead of waiting for the last
  /// one to finish.
  int get sequence => _sequence;

  /// True once 2+ reps have landed inside the same burst window.
  bool get isOnStreak => _streakCount >= 2;

  void reset() {
    _lastSeenCount = 0;
    _streakCount = 0;
    _sequence = 0;
    _lastRepAt = null;
  }

  /// Call with the validator's current authoritative count every time it is
  /// observed (e.g. every processed camera frame). If it has increased since
  /// the last call, this registers one-or-more new reps (a count can jump by
  /// more than 1 if several reps landed between two observations — e.g. two
  /// frame-processing passes coalesced) and returns the result to animate.
  /// Returns null when the count did not increase (nothing to animate).
  RepBurstEvent? update(int newCount, {DateTime? now}) {
    final at = now ?? DateTime.now();
    if (newCount <= _lastSeenCount) {
      if (newCount < _lastSeenCount) reset();
      _lastSeenCount = newCount;
      return null;
    }
    final delta = newCount - _lastSeenCount;
    final lastRepAt = _lastRepAt;
    final onStreak =
        lastRepAt != null && at.difference(lastRepAt) < burstWindow;
    _streakCount = onStreak ? _streakCount + delta : delta;
    _lastRepAt = at;
    _lastSeenCount = newCount;
    _sequence++;
    return RepBurstEvent(
      totalCount: newCount,
      delta: delta,
      streakCount: _streakCount,
      sequence: _sequence,
      isOnStreak: isOnStreak,
    );
  }
}

/// One burst-worthy rep observation, ready to hand straight to the UI.
class RepBurstEvent {
  const RepBurstEvent({
    required this.totalCount,
    required this.delta,
    required this.streakCount,
    required this.sequence,
    required this.isOnStreak,
  });

  /// The validator's authoritative running total after this rep.
  final int totalCount;

  /// How much the total moved since the last observation (normally 1).
  final int delta;

  /// Reps landed in the current burst — what the "+N" badge should show.
  final int streakCount;

  /// Monotonic — key a keyed animation on this so every rep replays it.
  final int sequence;

  final bool isOnStreak;
}
