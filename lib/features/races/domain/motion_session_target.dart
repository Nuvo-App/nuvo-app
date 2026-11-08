/// The camera session's target for a race.
///
/// Every motion validator reports `currentValue = min(count, targetValue)`,
/// so the session target is also a hard ceiling on what a proof can count.
///
/// * `first_to_goal` — the real remaining amount to the goal (at least 1);
///   without a stored goal, the movement's default (custom movements: 1).
/// * Every other format (most total, timed battle, best single) has no
///   finish number, so it gets [kOpenEndedSessionTarget] — effectively no
///   ceiling. Before this, those sessions fell back to the movement's small
///   default (or 1 for custom movements) and the count froze there.
library;

const int kOpenEndedSessionTarget = 100000;

int motionSessionTarget({
  required String? format,
  required bool isCustom,
  required int? raceTarget,
  required int alreadyDone,
  required int? defaultTarget,
}) {
  if (format == 'first_to_goal') {
    if (raceTarget != null && raceTarget > 0) {
      return (raceTarget - alreadyDone).clamp(1, raceTarget);
    }
    return isCustom ? 1 : (defaultTarget ?? 1);
  }
  return kOpenEndedSessionTarget;
}
