/// Real presence, derived from `PublicUser.lastActiveAt` (a server timestamp
/// touched on session restore) — never fabricated. Null in means null out.
library;

enum CrewPresence { active, recentlyActive, away, unknown }

CrewPresence crewPresenceFor(DateTime? lastActiveAt, {DateTime? now}) {
  if (lastActiveAt == null) return CrewPresence.unknown;
  final reference = now ?? DateTime.now().toUtc();
  final age = reference.difference(lastActiveAt);
  if (age.isNegative || age <= const Duration(minutes: 5)) {
    return CrewPresence.active;
  }
  if (age <= const Duration(hours: 24)) return CrewPresence.recentlyActive;
  return CrewPresence.away;
}

/// Short label for a crew row — omitted entirely (returns null) once someone
/// hasn't been seen in over a week, so the UI doesn't dwell on stale absence.
String? crewPresenceLabel(DateTime? lastActiveAt, {DateTime? now}) {
  if (lastActiveAt == null) return null;
  final reference = now ?? DateTime.now().toUtc();
  final age = reference.difference(lastActiveAt);
  if (age.isNegative || age <= const Duration(minutes: 5)) return 'Active now';
  if (age <= const Duration(hours: 1)) {
    final mins = age.inMinutes.clamp(1, 59);
    return 'Active ${mins}m ago';
  }
  if (age <= const Duration(hours: 24)) {
    return 'Active ${age.inHours}h ago';
  }
  if (age <= const Duration(days: 7)) {
    return 'Active ${age.inDays}d ago';
  }
  return null;
}
