import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/crew/domain/crew_presence.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('crewPresenceFor', () {
    test('null lastActiveAt is unknown', () {
      expect(crewPresenceFor(null, now: now), CrewPresence.unknown);
    });

    test('within 5 minutes is active', () {
      expect(
        crewPresenceFor(now.subtract(const Duration(minutes: 3)), now: now),
        CrewPresence.active,
      );
    });

    test('within 24 hours but past 5 minutes is recentlyActive', () {
      expect(
        crewPresenceFor(now.subtract(const Duration(hours: 5)), now: now),
        CrewPresence.recentlyActive,
      );
    });

    test('past 24 hours is away', () {
      expect(
        crewPresenceFor(now.subtract(const Duration(days: 2)), now: now),
        CrewPresence.away,
      );
    });
  });

  group('crewPresenceLabel', () {
    test('null lastActiveAt has no label', () {
      expect(crewPresenceLabel(null, now: now), isNull);
    });

    test('just now reads Active now', () {
      expect(
        crewPresenceLabel(now.subtract(const Duration(seconds: 30)), now: now),
        'Active now',
      );
    });

    test('minutes ago reads Active Xm ago', () {
      expect(
        crewPresenceLabel(now.subtract(const Duration(minutes: 20)), now: now),
        'Active 20m ago',
      );
    });

    test('hours ago reads Active Xh ago', () {
      expect(
        crewPresenceLabel(now.subtract(const Duration(hours: 4)), now: now),
        'Active 4h ago',
      );
    });

    test('days ago reads Active Xd ago', () {
      expect(
        crewPresenceLabel(now.subtract(const Duration(days: 3)), now: now),
        'Active 3d ago',
      );
    });

    test('over a week ago has no label', () {
      expect(
        crewPresenceLabel(now.subtract(const Duration(days: 10)), now: now),
        isNull,
      );
    });
  });
}
