import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/presentation/custom_pose/recent_movements_provider.dart';

/// Focused tests for the Recent movements feature.
///
/// These tests verify the pure logic functions (addRecent, filterValidIds,
/// recentActivitiesFromIds) without needing flutter_secure_storage,
/// which doesn't work in unit tests.
void main() {
  group('addRecent', () {
    test('adds a new ID to the front of an empty list', () {
      final result = addRecent([], 'push_ups', 5);
      expect(result, ['push_ups']);
    });

    test('adds a new ID to the front of a non-empty list', () {
      final result = addRecent(['squats'], 'push_ups', 5);
      expect(result, ['push_ups', 'squats']);
    });

    test('moves an existing ID to the front (deduplication)', () {
      final result = addRecent(['push_ups', 'squats', 'lunges'], 'squats', 5);
      expect(result, ['squats', 'push_ups', 'lunges']);
    });

    test('duplicate selection moves item to front, appears once', () {
      var current = <String>[];
      current = addRecent(current, 'push_ups', 5);
      current = addRecent(current, 'squats', 5);
      current = addRecent(current, 'push_ups', 5); // duplicate
      expect(current, ['push_ups', 'squats']);
      expect(current.where((id) => id == 'push_ups').length, 1);
    });

    test('trims to maxItems (5)', () {
      var current = <String>[];
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        current = addRecent(current, id, 5);
      }
      expect(current.length, 5);
      // Adding a 6th should push the oldest out
      current = addRecent(current, 'f', 5);
      expect(current.length, 5);
      expect(current.first, 'f');
      expect(current, isNot(contains('a'))); // oldest was pushed out
    });

    test('maxItems boundary: exactly 5 items', () {
      final result = addRecent(['a', 'b', 'c', 'd'], 'e', 5);
      expect(result.length, 5);
      expect(result, ['e', 'a', 'b', 'c', 'd']);
    });

    test('order is newest-first after multiple selections', () {
      var current = <String>[];
      current = addRecent(current, 'push_ups', 5);
      current = addRecent(current, 'squats', 5);
      current = addRecent(current, 'lunges', 5);
      expect(current, ['lunges', 'squats', 'push_ups']);
    });
  });

  group('filterValidIds', () {
    test('keeps all valid IDs', () {
      final result = filterValidIds(['push_ups', 'squats', 'lunges']);
      expect(result, ['push_ups', 'squats', 'lunges']);
    });

    test('removes stale/unknown IDs', () {
      final result = filterValidIds([
        'push_ups',
        'unknown_movement',
        'squats',
        'deprecated_exercise',
      ]);
      expect(result, ['push_ups', 'squats']);
    });

    test('returns empty list if all IDs are stale', () {
      final result = filterValidIds(['foo', 'bar', 'baz']);
      expect(result, isEmpty);
    });

    test('returns empty list for empty input', () {
      final result = filterValidIds([]);
      expect(result, isEmpty);
    });

    test('handles new movement IDs (sumo_squats, side_lunges)', () {
      final result = filterValidIds(['sumo_squats', 'side_lunges']);
      expect(result, ['sumo_squats', 'side_lunges']);
    });
  });

  group('recentActivitiesFromIds', () {
    test('returns empty list for empty IDs', () {
      final result = recentActivitiesFromIds([]);
      expect(result, isEmpty);
    });

    test('resolves valid IDs to catalog definitions', () {
      final result = recentActivitiesFromIds(['push_ups', 'squats']);
      expect(result.length, 2);
      expect(result[0].type, MotionActivityType.pushUps);
      expect(result[1].type, MotionActivityType.squats);
    });

    test('filters out stale IDs', () {
      final result = recentActivitiesFromIds(['push_ups', 'unknown', 'squats']);
      expect(result.length, 2);
      expect(result[0].type, MotionActivityType.pushUps);
      expect(result[1].type, MotionActivityType.squats);
    });

    test('preserves newest-first order', () {
      final result = recentActivitiesFromIds(['lunges', 'squats', 'push_ups']);
      expect(result[0].type, MotionActivityType.lunges);
      expect(result[1].type, MotionActivityType.squats);
      expect(result[2].type, MotionActivityType.pushUps);
    });

    test('resolves new movement IDs', () {
      final result = recentActivitiesFromIds(['sumo_squats', 'side_lunges']);
      expect(result[0].type, MotionActivityType.sumoSquats);
      expect(result[1].type, MotionActivityType.sideLunges);
    });
  });

  group('Recent section visibility', () {
    /// The picker shows the Recent section only when recentActivitiesFromIds
    /// returns a non-empty list. This is verified by checking that an empty
    /// ID list produces an empty activities list (which the picker uses to
    /// hide the section).
    test('empty history → no Recent activities → section hidden', () {
      final activities = recentActivitiesFromIds([]);
      expect(activities, isEmpty);
      // The picker checks: if (recentActivities.isNotEmpty) ... show section
    });

    test('non-empty history → Recent activities → section visible', () {
      final activities = recentActivitiesFromIds(['push_ups']);
      expect(activities, isNotEmpty);
    });

    test('all-stale history → no Recent activities → section hidden', () {
      final activities = recentActivitiesFromIds(['unknown1', 'unknown2']);
      expect(activities, isEmpty);
    });
  });

  group('RecentMovementsStore.maxItems', () {
    test('maxItems is 5', () {
      expect(RecentMovementsStore.maxItems, 5);
    });
  });

  group('integration: addRecent + filterValidIds + recentActivitiesFromIds', () {
    test('full cycle: select 7 movements, only 5 kept, all valid', () {
      var current = <String>[];
      final selections = [
        'push_ups',
        'squats',
        'lunges',
        'jumping_jacks',
        'high_knees',
        'arm_raises',
        'plank_hold',
      ];
      for (final id in selections) {
        current = addRecent(current, id, 5);
      }
      // Only 5 kept, newest first
      expect(current.length, 5);
      expect(current.first, 'plank_hold');
      // All should be valid
      final filtered = filterValidIds(current);
      expect(filtered.length, 5);
      // All should resolve to catalog definitions
      final activities = recentActivitiesFromIds(filtered);
      expect(activities.length, 5);
      expect(activities[0].type, MotionActivityType.plankHold);
    });

    test('stale ID in storage is filtered on read', () {
      // Simulate stored state with a stale ID
      final storedIds = ['push_ups', 'stale_id', 'squats'];
      final filtered = filterValidIds(storedIds);
      final activities = recentActivitiesFromIds(filtered);
      expect(activities.length, 2);
      expect(activities[0].type, MotionActivityType.pushUps);
      expect(activities[1].type, MotionActivityType.squats);
    });

    test('selecting a movement that is already recent moves it to front', () {
      var current = ['push_ups', 'squats', 'lunges'];
      current = addRecent(current, 'squats', 5);
      expect(current, ['squats', 'push_ups', 'lunges']);
      final activities = recentActivitiesFromIds(current);
      expect(activities[0].type, MotionActivityType.squats);
    });
  });

  group('category and search still work with recent', () {
    test('search finds movements regardless of recent state', () {
      final results = searchActivities('push');
      expect(results.any((d) => d.type == MotionActivityType.pushUps), isTrue);
    });

    test('category filtering works regardless of recent state', () {
      final lowerBody = activitiesByCategory(MovementCategory.lowerBody);
      expect(lowerBody.any((d) => d.type == MotionActivityType.squats), isTrue);
      expect(
        lowerBody.any((d) => d.type == MotionActivityType.sumoSquats),
        isTrue,
      );
    });

    test('recent does not affect the full catalog', () {
      // The catalog should still have all 23 movements (13 original +
      // 10 preset-motion-expansion).
      expect(motionActivityDefinitions.length, 23);
      // Recent is a subset
      final recent = recentActivitiesFromIds(['push_ups', 'squats']);
      expect(recent.length, lessThan(motionActivityDefinitions.length));
    });
  });
}
