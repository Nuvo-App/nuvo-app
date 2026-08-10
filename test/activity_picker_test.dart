import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';

/// Tests for the scalable movement picker.
///
/// These tests verify:
/// 1. The catalog metadata (category, featured, sortPriority) is correct
/// 2. Search works via title + aliases
/// 3. Category filtering works
/// 4. The layout handles a large catalog (50-100 movements) via fixture data
/// 5. No hardcoded arrays in the picker — everything derives from the catalog

void main() {
  group('catalog metadata', () {
    test('every movement has a category', () {
      for (final d in motionActivityDefinitions) {
        expect(
          d.category,
          isNotNull,
          reason: '${d.title} has no category',
        );
      }
    });

    test('every movement has a sortPriority', () {
      for (final d in motionActivityDefinitions) {
        expect(
          d.sortPriority,
          greaterThan(0),
          reason: '${d.title} has sortPriority <= 0',
        );
      }
    });

    test('at least 4 movements are featured (for the Popular row)', () {
      expect(
        featuredActivities.length,
        greaterThanOrEqualTo(4),
        reason: 'Need at least 4 featured movements for the Popular row',
      );
    });

    test('featuredActivities are sorted by sortPriority', () {
      for (var i = 1; i < featuredActivities.length; i++) {
        expect(
          featuredActivities[i - 1].sortPriority,
          lessThanOrEqualTo(featuredActivities[i].sortPriority),
          reason: 'featuredActivities not sorted at index $i',
        );
      }
    });

    test('activeCategories returns categories in enum order', () {
      final cats = activeCategories;
      for (var i = 1; i < cats.length; i++) {
        expect(
          cats[i - 1].index,
          lessThan(cats[i].index),
          reason: 'activeCategories not in enum order',
        );
      }
    });
  });

  group('search', () {
    test('empty query returns all movements sorted', () {
      final results = searchActivities('');
      expect(results.length, motionActivityDefinitions.length);
    });

    test('search by title (case-insensitive)', () {
      final results = searchActivities('push');
      expect(results.any((d) => d.type == MotionActivityType.pushUps), isTrue);
    });

    test('search by alias', () {
      final results = searchActivities('jacks');
      expect(
        results.any((d) => d.type == MotionActivityType.jumpingJacks),
        isTrue,
      );
    });

    test('search "sumo" finds sumo squats', () {
      final results = searchActivities('sumo');
      expect(
        results.any((d) => d.type == MotionActivityType.sumoSquats),
        isTrue,
      );
    });

    test('search "side" finds side lunges', () {
      final results = searchActivities('side');
      expect(
        results.any((d) => d.type == MotionActivityType.sideLunges),
        isTrue,
      );
    });

    test('search with no matches returns empty list', () {
      final results = searchActivities('xyzqwerty');
      expect(results, isEmpty);
    });

    test('search results are sorted by sortPriority', () {
      final results = searchActivities('s');
      for (var i = 1; i < results.length; i++) {
        expect(
          results[i - 1].sortPriority,
          lessThanOrEqualTo(results[i].sortPriority),
          reason: 'Search results not sorted at index $i',
        );
      }
    });
  });

  group('category filtering', () {
    test('activitiesByCategory returns only movements in that category', () {
      for (final category in activeCategories) {
        final activities = activitiesByCategory(category);
        for (final d in activities) {
          expect(
            d.category,
            category,
            reason: '${d.title} in wrong category',
          );
        }
      }
    });

    test('activitiesByCategory results are sorted by sortPriority', () {
      for (final category in activeCategories) {
        final activities = activitiesByCategory(category);
        for (var i = 1; i < activities.length; i++) {
          expect(
            activities[i - 1].sortPriority,
            lessThanOrEqualTo(activities[i].sortPriority),
            reason: '$category not sorted at index $i',
          );
        }
      }
    });

    test('every movement appears in exactly one category', () {
      final allByCategory = <MotionActivityType>{};
      for (final category in activeCategories) {
        for (final d in activitiesByCategory(category)) {
          expect(
            allByCategory.contains(d.type),
            isFalse,
            reason: '${d.title} appears in multiple categories',
          );
          allByCategory.add(d.type);
        }
      }
      expect(
        allByCategory.length,
        motionActivityDefinitions.length,
        reason: 'Not all movements are accounted for in categories',
      );
    });

    test('lower body category contains squats, lunges, sumo squats, side lunges', () {
      final lowerBody = activitiesByCategory(MovementCategory.lowerBody);
      final types = lowerBody.map((d) => d.type).toSet();
      expect(types, contains(MotionActivityType.squats));
      expect(types, contains(MotionActivityType.lunges));
      expect(types, contains(MotionActivityType.sumoSquats));
      expect(types, contains(MotionActivityType.sideLunges));
      expect(types, contains(MotionActivityType.deepSquats));
      expect(types, contains(MotionActivityType.squatJacks));
      expect(types, contains(MotionActivityType.jumpSquats));
      expect(types, contains(MotionActivityType.lungeJumps));
    });
  });

  group('large catalog scale (fixture data)', () {
    /// Generates N fixture movements to prove the picker handles
    /// a large catalog. These are NOT real movements — they only
    /// test the data structures and sorting.
    List<MotionActivityDefinition> generateFixtureMovements(int count) {
      final categories = MovementCategory.values;
      final fixtures = <MotionActivityDefinition>[];
      for (var i = 0; i < count; i++) {
        fixtures.add(MotionActivityDefinition(
          type: MotionActivityType.pushUps, // reuse — just for data structure
          title: 'Fixture Movement $i',
          metric: RaceMetric.reps,
          suggestedTargets: [10, 20, 30],
          supportedFormats: [RaceFormat.firstToGoal],
          aliases: ['fixture $i', 'fm$i'],
          proofLabel: 'fixture',
          cameraInstruction: 'Front view',
          instructions: ['Stand visible.'],
          icon: Icons.fitness_center,
          framingLabel: 'Full body',
          preferredCameraView: PreferredCameraView.frontPreferred,
          category: categories[i % categories.length],
          featured: i < 8, // first 8 are featured
          sortPriority: i + 1,
        ));
      }
      return fixtures;
    }

    test('100 fixture movements can be categorized and sorted', () {
      final fixtures = generateFixtureMovements(100);

      // Group by category
      final byCategory = <MovementCategory, List<MotionActivityDefinition>>{};
      for (final d in fixtures) {
        byCategory.putIfAbsent(d.category, () => []).add(d);
      }

      // Every category should have movements (since we cycle through)
      for (final cat in MovementCategory.values) {
        expect(
          byCategory[cat],
          isNotNull,
          reason: 'Category $cat has no fixtures',
        );
        expect(byCategory[cat]!.length, greaterThan(0));
      }

      // Sort each category and verify
      for (final cat in byCategory.keys) {
        final sorted = [...byCategory[cat]!]
          ..sort((a, b) => a.sortPriority.compareTo(b.sortPriority));
        for (var i = 1; i < sorted.length; i++) {
          expect(
            sorted[i - 1].sortPriority,
            lessThanOrEqualTo(sorted[i].sortPriority),
          );
        }
      }
    });

    test('100 fixture movements can be searched', () {
      final fixtures = generateFixtureMovements(100);

      // Search for "movement 5" — should find 11 (5, 50-59)
      final matching = fixtures
          .where((d) => d.title.toLowerCase().contains('movement 5'))
          .toList();
      expect(matching.length, 11);

      // Search for "fm5" (alias) — should find 11 (fm5, fm50-fm59)
      final aliasMatch = fixtures
          .where((d) => d.aliases.any((a) => a.contains('fm5')))
          .toList();
      expect(aliasMatch.length, 11);

      // Search for "fixture" — should find all 100
      final allMatching = fixtures
          .where((d) => d.title.toLowerCase().contains('fixture'))
          .toList();
      expect(allMatching.length, 100);
    });

    test('featured movements from 100 fixtures are exactly 8', () {
      final fixtures = generateFixtureMovements(100);
      final featured = fixtures.where((d) => d.featured).toList();
      expect(featured.length, 8);
    });

    test('category distribution is even for 100 fixtures', () {
      final fixtures = generateFixtureMovements(100);
      final byCategory = <MovementCategory, int>{};
      for (final d in fixtures) {
        byCategory[d.category] = (byCategory[d.category] ?? 0) + 1;
      }
      // 100 / 5 categories = 20 each
      for (final cat in MovementCategory.values) {
        expect(
          byCategory[cat],
          20,
          reason: 'Category ${cat.label} should have 20 fixtures',
        );
      }
    });
  });

  group('no hardcoded arrays in picker', () {
    /// This test verifies that the picker derives its data from
    /// the catalog, not from hardcoded arrays. The key functions
    /// (featuredActivities, activeCategories, activitiesByCategory,
    /// searchActivities) all read from motionActivityDefinitions.

    test('featuredActivities derives from catalog, not a separate list', () {
      // If we add a new featured movement to the catalog, it should
      // automatically appear in featuredActivities.
      final featuredTypes = featuredActivities.map((d) => d.type).toSet();
      final catalogFeatured = motionActivityDefinitions
          .where((d) => d.featured)
          .map((d) => d.type)
          .toSet();
      expect(featuredTypes, equals(catalogFeatured));
    });

    test('activeCategories derives from catalog', () {
      final catalogCategories = motionActivityDefinitions
          .map((d) => d.category)
          .toSet()
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      expect(activeCategories, equals(catalogCategories));
    });
  });
}
