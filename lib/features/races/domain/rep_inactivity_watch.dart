/// The "Are you still there?" guard for rep takes — pure timing policy,
/// no widgets, so the 30-second rule is unit-testable and the camera
/// screen only wires its decisions to UI.
///
/// Only rep takes arm the watch: a hold IS the stillness, a timed window
/// is already racing a deadline, and the basketball pipeline has its own
/// shot flow. The screen owns that gating; this class owns the clock.
library;

/// What the prompt's two actions resolve to. `finish` is the same end the
/// Done button takes — the screen routes it through `_finishRecording`.
enum RepInactivityResolution { resume, endTake }

/// The dialog's answer, or null when it was dismissed without a choice.
enum RepInactivityChoice { keepGoing, finish }

class RepInactivityWatch {
  RepInactivityWatch({this.threshold = const Duration(seconds: 30)});

  /// How long a rep take may go without a counted rep before the prompt.
  final Duration threshold;

  DateTime? _armedAt;
  DateTime? _lastCountedAt;

  /// Already fired for the current quiet stretch — one prompt at a time.
  bool _spent = false;

  /// (Re)starts the silence clock — recording start, or "Keep going".
  void arm(DateTime now) {
    _armedAt = now;
    _spent = false;
  }

  /// The take ended (or never qualified) — no prompt can fire.
  void disarm() {
    _armedAt = null;
    _spent = false;
  }

  /// A rep counted at [at]. A same-or-older timestamp is a stale echo,
  /// not a new rep — the silence keeps running.
  void noteCounted(DateTime at) {
    final last = _lastCountedAt;
    if (last != null && !at.isAfter(last)) return;
    _lastCountedAt = at;
    _spent = false;
  }

  /// True once per quiet stretch: [threshold] with nothing counted since
  /// arming (or since the last rep, whichever is later). Anchoring at the
  /// arm time means a take that never lands rep one still asks.
  bool isSilent(DateTime now) {
    final armed = _armedAt;
    if (armed == null || _spent) return false;
    var since = armed;
    final last = _lastCountedAt;
    if (last != null && last.isAfter(armed)) since = last;
    return now.difference(since) >= threshold;
  }

  /// The prompt is up — swallow further fires until a rep lands or the
  /// user re-arms with "Keep going".
  void markPrompted() => _spent = true;

  /// Resolves the dialog's answer. "Keep going" re-arms the clock; a
  /// dismissed dialog resumes the same take the same way (nothing about
  /// the silence changed, but the user was seen — the next quiet stretch
  /// asks again).
  RepInactivityResolution resolve(RepInactivityChoice? choice, DateTime now) {
    switch (choice) {
      case RepInactivityChoice.finish:
        disarm();
        return RepInactivityResolution.endTake;
      case RepInactivityChoice.keepGoing:
      case null:
        arm(now);
        return RepInactivityResolution.resume;
    }
  }
}
