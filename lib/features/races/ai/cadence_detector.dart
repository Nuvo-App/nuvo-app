/// Which side (leg) a cadence movement's current active phase belongs to.
enum CadenceSide { left, right }

/// Reusable alternating-cadence primitive: Running in Place, Treadmill
/// Running, Walking in Place, Marching in Place, Butt Kicks, Mountain
/// Climbers, Lateral Steps, Step-Ups. Not used by, and shares no code with,
/// Pushups / Jumping Jacks / Plank.
///
/// ## Count semantics (documented once — every cadence preset uses this
/// same convention, so counts are never an invisible per-movement choice):
/// **one count = one confirmed alternation step.** Left activating after
/// right (or vice versa) is +1 — the same granularity [HighKneesValidator]
/// already uses (each knee raise is its own +1, not a left+right pair). A
/// full left-right cycle is therefore 2 counts.
///
/// ## Why this rejects same-side noise for free
/// A rep only counts when the newly-confirmed side DIFFERS from the last
/// confirmed side. Repeated left-only motion confirms "left" once, then every
/// further left confirmation matches the already-stable side and is a no-op —
/// there is no separate "return to neutral" requirement to get this right.
///
/// ## Frame-count based, not time-based
/// [stableFrames] consecutive frames of the SAME side are required before a
/// side is confirmed — this is pose noise tolerance, identical in spirit to
/// [RepCounterStateMachine]'s stability model. There is no wall-clock cooldown
/// anywhere in this class, so it scales with whatever effective FPS the
/// device delivers instead of penalizing a fast cadence.
class CadenceDetector {
  CadenceDetector({this.stableFrames = 2});

  /// Consecutive frames a side must read before it is confirmed. Tune per
  /// movement — a deliberate, slower movement (Marching) can use a larger
  /// value than a fast one (Running) without losing real cycles, since a
  /// slower movement naturally produces more processed frames per phase.
  final int stableFrames;

  CadenceSide? _stableSide;
  CadenceSide? _candidateSide;
  int _candidateFrames = 0;
  int _cycles = 0;

  /// The last confirmed side, or null before the first side is confirmed.
  CadenceSide? get currentSide => _stableSide;

  /// Confirmed alternation count (see class doc for the counting convention).
  int get cycles => _cycles;

  void reset() {
    _stableSide = null;
    _candidateSide = null;
    _candidateFrames = 0;
    _cycles = 0;
  }

  /// Feed the side measured on this frame — null means neither side clearly
  /// reads as active this frame (neutral / both / ambiguous). Returns true
  /// exactly when this frame confirmed a new alternation (i.e. counted).
  bool update(CadenceSide? measuredSide) {
    if (measuredSide == null) return false;

    if (measuredSide == _candidateSide) {
      _candidateFrames++;
    } else {
      _candidateSide = measuredSide;
      _candidateFrames = 1;
    }
    if (_candidateFrames < stableFrames || measuredSide == _stableSide) {
      return false;
    }

    // The first side ever confirmed just establishes a baseline — it isn't
    // a completed alternation yet, so it doesn't count.
    final counted = _stableSide != null;
    _stableSide = measuredSide;
    if (counted) _cycles++;
    return counted;
  }
}
